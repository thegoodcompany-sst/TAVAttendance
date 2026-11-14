BEGIN;
CREATE FUNCTION public.defer_quiet(p_at timestamptz) RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT CASE WHEN (p_at AT TIME ZONE 'Asia/Singapore')::time>=quiet_start THEN (((p_at AT TIME ZONE 'Asia/Singapore')::date+1)+quiet_resume) AT TIME ZONE 'Asia/Singapore'
 WHEN (p_at AT TIME ZONE 'Asia/Singapore')::time<quiet_end THEN (((p_at AT TIME ZONE 'Asia/Singapore')::date)+quiet_resume) AT TIME ZONE 'Asia/Singapore' ELSE p_at END FROM public.prompt_policy WHERE id
$$;
CREATE FUNCTION public.cancel_prompt_work(p_id uuid,p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM id FROM public.lessons WHERE id=p_id FOR UPDATE;
 PERFORM id FROM public.notification_plans WHERE lesson_id=p_id ORDER BY id FOR UPDATE;
 UPDATE public.notification_plans SET status='cancelled',cancel_reason=p_reason,updated_at=clock_timestamp() WHERE lesson_id=p_id AND status='pending';
 UPDATE public.notification_outbox o SET status='cancelled',lease_token=NULL,lease_until=NULL,last_error_code='suppressed',updated_at=clock_timestamp() FROM public.notification_plans p WHERE p.id=o.plan_id AND p.lesson_id=p_id AND o.status IN ('pending','claimed');
END $$;
CREATE FUNCTION public.prompt_eligible(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT FROM public.lessons l JOIN public.classes c ON c.id=l.class_id JOIN public.profiles u ON u.id=l.accountable_teacher_id WHERE l.id=p_id AND l.cancelled_at IS NULL AND c.active AND NOT c.is_study_space AND u.active AND u.role='teacher' AND NOT EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id))
$$;
CREATE FUNCTION public.replan_lesson(p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons; pol public.prompt_policy; p public.notification_plans; k text; off_min int; due timestamptz; prev timestamptz; final_due timestamptz; n int:=0;
BEGIN
 SELECT * INTO l FROM public.lessons WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RETURN '{"planned":0}'; END IF;
 IF NOT public.prompt_eligible(p_id) THEN PERFORM public.cancel_prompt_work(p_id,'ineligible'); RETURN '{"planned":0}'; END IF;
 SELECT * INTO pol FROM public.prompt_policy;
 -- Same revision must not undo delayed-worker pacing or rematerialize snapshots.
 IF (SELECT count(*) FROM public.notification_plans WHERE lesson_id=p_id AND kind<>'simulation')=4 AND NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=p_id AND kind<>'simulation' AND status<>'completed' AND revision<>l.plan_revision) THEN RETURN '{"planned":0}'; END IF;
 FOR k,off_min IN SELECT * FROM (VALUES ('heads_up',pol.heads_up_minutes),('attendance',pol.attendance_minutes),('follow_up',pol.follow_up_minutes),('final',pol.final_minutes)) v LOOP
  SELECT * INTO p FROM public.notification_plans WHERE lesson_id=p_id AND kind=k FOR UPDATE;
  IF p.status='completed' THEN prev:=p.due_at; IF k='final' THEN final_due:=p.due_at; END IF; CONTINUE; END IF;
  due:=public.defer_quiet(greatest(l.scheduled_end_at+make_interval(mins=>off_min),l.snoozed_until,prev+interval '5 minutes'));
  IF p.id IS NOT NULL THEN
   UPDATE public.notification_outbox SET status='cancelled',lease_token=NULL,lease_until=NULL,last_error_code='superseded',updated_at=clock_timestamp() WHERE plan_id=p.id AND status IN ('pending','claimed');
  END IF;
  INSERT INTO public.notification_plans(lesson_id,kind,revision,recipient_id,due_at,status) VALUES(p_id,k,l.plan_revision,l.accountable_teacher_id,due,'pending')
  ON CONFLICT(lesson_id,kind) DO UPDATE SET revision=EXCLUDED.revision,recipient_id=EXCLUDED.recipient_id,due_at=EXCLUDED.due_at,status='pending',cancel_reason=NULL,updated_at=clock_timestamp();
  prev:=due; final_due:=due; n:=n+1;
 END LOOP;
 UPDATE public.lessons SET overdue_at=final_due+make_interval(mins=>pol.overdue_grace_minutes) WHERE id=p_id;
 RETURN jsonb_build_object('planned',n);
END $$;
CREATE FUNCTION public.plan_prompts(p_lesson_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN PERFORM public.require_service_or_admin(); RETURN public.replan_lesson(p_lesson_id); END $$;
CREATE FUNCTION public.lesson_plan_hook() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN PERFORM public.replan_lesson(NEW.id); RETURN NULL; END $$;
CREATE TRIGGER lesson_plan_insert AFTER INSERT ON public.lessons FOR EACH ROW EXECUTE FUNCTION public.lesson_plan_hook();
CREATE TRIGGER lesson_plan_update AFTER UPDATE OF plan_revision ON public.lessons FOR EACH ROW WHEN (OLD.plan_revision IS DISTINCT FROM NEW.plan_revision) EXECUTE FUNCTION public.lesson_plan_hook();
CREATE FUNCTION public.submission_plan_hook() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN PERFORM public.cancel_prompt_work(NEW.lesson_id,'submitted'); RETURN NULL; END $$;
CREATE TRIGGER submission_plan_hook AFTER INSERT ON public.lesson_submissions FOR EACH ROW EXECUTE FUNCTION public.submission_plan_hook();
CREATE FUNCTION public.policy_plan_hook() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l record;
BEGIN
 FOR l IN SELECT id FROM public.lessons WHERE cancelled_at IS NULL AND NOT EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=lessons.id) ORDER BY id FOR UPDATE LOOP
  UPDATE public.lessons SET plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=l.id;
  -- A completed final stage stays completed, but a changed grace still applies.
  UPDATE public.lessons SET overdue_at=(SELECT due_at FROM public.notification_plans WHERE lesson_id=l.id AND kind='final')+make_interval(mins=>NEW.overdue_grace_minutes)
  WHERE id=l.id AND public.prompt_eligible(l.id) AND EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=l.id AND kind='final');
 END LOOP;
 RETURN NULL;
END $$;
CREATE TRIGGER policy_plan_hook AFTER UPDATE ON public.prompt_policy FOR EACH ROW EXECUTE FUNCTION public.policy_plan_hook();
CREATE FUNCTION public.snooze_prompt(p_lesson_id uuid,p_minutes int,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:=jsonb_build_array(p_minutes); result jsonb; l public.lessons; ts timestamptz; n timestamptz:=clock_timestamp();
BEGIN
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'snooze_prompt',args); IF result IS NOT NULL THEN RETURN result; END IF;
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 IF p_minutes IS DISTINCT FROM 10 THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 IF l.cancelled_at IS NOT NULL OR EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id) THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
 IF n<l.scheduled_end_at-interval '5 minutes' THEN RAISE EXCEPTION 'TP_TOO_EARLY' USING ERRCODE='P0001'; END IF;
 IF NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=l.id AND kind<>'simulation' AND status='pending') THEN RAISE EXCEPTION 'TP_NO_PENDING_PROMPT' USING ERRCODE='P0001'; END IF;
 ts:=least(greatest(n,l.snoozed_until)+interval '10 minutes',l.scheduled_end_at+interval '60 minutes');
 IF l.snooze_count>=(SELECT max_snoozes FROM public.prompt_policy) OR ts<=greatest(n,l.snoozed_until) THEN RAISE EXCEPTION 'TP_SNOOZE_LIMIT' USING ERRCODE='P0001'; END IF;
 UPDATE public.lessons SET snoozed_until=ts,snooze_count=snooze_count+1,plan_revision=plan_revision+1,updated_at=n WHERE id=l.id;
 SELECT * INTO l FROM public.lessons WHERE id=l.id;
 RETURN public.mutation_finish(l.id,p_mutation_id,'snooze_prompt',args,jsonb_build_object('lesson_id',l.id,'snoozed_until',ts,'next_prompt_at',(SELECT min(due_at) FROM public.notification_plans WHERE lesson_id=l.id AND status='pending' AND kind<>'simulation'),'overdue_at',l.overdue_at));
END $$;
CREATE FUNCTION public.register_device(p_installation_id uuid,p_token text,p_environment text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.teacher_devices; n timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_enabled();
 IF p_installation_id IS NULL OR p_token IS NULL OR p_token !~ '^[0-9a-f]+$' OR length(p_token) NOT BETWEEN 32 AND 512 OR length(p_token)%2<>0 OR p_environment IS NULL OR p_environment NOT IN ('sandbox','production') THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 -- A global token-ownership lock precedes user lock: rotation cannot deadlock swaps.
 PERFORM pg_advisory_xact_lock(70424319);
 PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text,4));
 IF EXISTS(SELECT FROM public.teacher_devices WHERE ((environment=p_environment AND token=p_token) OR installation_id=p_installation_id) AND user_id<>auth.uid()) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 SELECT * INTO d FROM public.teacher_devices WHERE user_id=auth.uid() AND environment=p_environment AND (installation_id=p_installation_id OR token=p_token) ORDER BY (installation_id=p_installation_id) DESC LIMIT 1 FOR UPDATE;
 IF FOUND THEN
  -- Reject ambiguous merge of two existing registrations instead of exposing a constraint error.
  IF EXISTS(SELECT FROM public.teacher_devices WHERE environment=p_environment AND token=p_token AND id<>d.id) THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
  UPDATE public.teacher_devices SET installation_id=p_installation_id,token=p_token,last_seen_at=greatest(n,last_seen_at+interval '1 microsecond'),revoked_at=NULL WHERE id=d.id RETURNING * INTO d;
 ELSE
  INSERT INTO public.teacher_devices(user_id,installation_id,token,environment,last_seen_at) VALUES(auth.uid(),p_installation_id,p_token,p_environment,n) RETURNING * INTO d;
 END IF;
 UPDATE public.teacher_devices SET revoked_at=n WHERE id IN (SELECT id FROM public.teacher_devices WHERE user_id=auth.uid() AND revoked_at IS NULL ORDER BY last_seen_at DESC,id DESC OFFSET 5);
 RETURN jsonb_build_object('device_id',d.id,'last_seen_at',d.last_seen_at,'environment',d.environment);
END $$;
CREATE FUNCTION public.revoke_device(p_device_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM public.require_enabled();
 UPDATE public.teacher_devices SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE id=p_device_id AND user_id=auth.uid();
 RETURN jsonb_build_object('revoked',FOUND);
END $$;
CREATE FUNCTION public.complete_prompt_plan(p_plan uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 UPDATE public.notification_plans p SET status='completed',updated_at=clock_timestamp() WHERE p.id=p_plan AND p.status='pending'
 AND EXISTS(SELECT FROM public.notification_outbox o WHERE o.plan_id=p.id AND o.plan_revision=p.revision)
 AND NOT EXISTS(SELECT FROM public.notification_outbox o WHERE o.plan_id=p.id AND o.plan_revision=p.revision AND o.status IN ('pending','claimed'));
END $$;
CREATE FUNCTION public.dispatch_enabled() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT FROM public.feature_flags WHERE key='teacher_prompts' AND enabled) AND (EXISTS(SELECT FROM public.runtime_settings WHERE demo_enabled) OR EXISTS(SELECT FROM public.feature_flags WHERE key='teacher_prompt_push' AND enabled))
$$;
CREATE FUNCTION public.scheduler_tick(p_now timestamptz,p_limit int DEFAULT 50)
RETURNS TABLE(outbox_id uuid,plan_id uuid,lesson_id uuid,kind text,recipient_id uuid,device_id uuid,plan_revision text,lease_token uuid,lease_until timestamptz,attempt_no int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
#variable_conflict use_column
DECLARE l public.lessons; p public.notification_plans; o public.notification_outbox; later record; n int:=0; paced timestamptz; deferred timestamptz;
BEGIN
 IF p_now IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 IF NOT public.dispatch_enabled() THEN RETURN; END IF;
 -- Lesson lock first; a competing worker skips the whole lesson, never waits on a plan.
 FOR l IN SELECT a.* FROM public.lessons a WHERE EXISTS(SELECT FROM public.notification_plans np WHERE np.lesson_id=a.id AND np.kind<>'simulation' AND np.status='pending' AND np.due_at<=p_now)
 ORDER BY (SELECT min(np.due_at) FROM public.notification_plans np WHERE np.lesson_id=a.id AND np.kind<>'simulation' AND np.status='pending'),a.id LIMIT p_limit FOR UPDATE OF a SKIP LOCKED LOOP
  IF NOT public.prompt_eligible(l.id) THEN PERFORM public.cancel_prompt_work(l.id,'ineligible'); CONTINUE; END IF;
  PERFORM public.replan_lesson(l.id);
  SELECT * INTO p FROM public.notification_plans np WHERE np.lesson_id=l.id AND np.kind<>'simulation' AND np.status='pending' AND np.due_at<=p_now ORDER BY np.due_at,np.id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  -- A revision takes a single device snapshot, including the explicit no-device result.
  IF NOT EXISTS(SELECT FROM public.notification_outbox b WHERE b.plan_id=p.id AND b.plan_revision=p.revision) THEN
   INSERT INTO public.notification_outbox(plan_id,plan_revision,device_id,recipient_id,status,available_at)
   SELECT p.id,p.revision,d.id,p.recipient_id,'pending',p.due_at FROM (SELECT * FROM public.teacher_devices WHERE user_id=p.recipient_id AND revoked_at IS NULL AND last_seen_at>=p_now-interval '90 days' ORDER BY last_seen_at DESC,id LIMIT 5) d
   WHERE NOT EXISTS(SELECT FROM public.notification_outbox old WHERE old.plan_id=p.id AND old.recipient_id=p.recipient_id AND old.device_id=d.id AND old.status='sent') ON CONFLICT DO NOTHING;
   IF NOT FOUND THEN
    -- All chosen devices previously accepted this logical stage: don't resend them.
    IF EXISTS(SELECT FROM public.notification_outbox b WHERE b.plan_id=p.id AND b.recipient_id=p.recipient_id AND b.status='sent') AND EXISTS(SELECT FROM public.teacher_devices WHERE user_id=p.recipient_id AND revoked_at IS NULL AND last_seen_at>=p_now-interval '90 days') THEN
     UPDATE public.notification_plans SET status='completed',updated_at=p_now WHERE id=p.id;
    ELSE
     INSERT INTO public.notification_outbox(plan_id,plan_revision,recipient_id,status,available_at,attempt_count,last_error_code) VALUES(p.id,p.revision,p.recipient_id,'failed',p_now,1,'no_devices') RETURNING * INTO o;
     INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,error_code,attempted_at) VALUES(o.id,1,gen_random_uuid(),'none','no_devices','no_devices',p_now);
     PERFORM public.complete_prompt_plan(p.id);
    END IF;
   END IF;
  END IF;
  -- One logical stage per tick. Delay subsequent stages without moving overdue_at.
  paced:=p_now;
  FOR later IN SELECT * FROM public.notification_plans np WHERE np.lesson_id=l.id AND np.id<>p.id AND np.kind<>'simulation' AND np.status='pending' AND np.due_at>=p.due_at ORDER BY np.due_at,np.id FOR UPDATE LOOP
   paced:=public.defer_quiet(greatest(later.due_at,paced+interval '5 minutes'));
   UPDATE public.notification_plans SET due_at=paced,updated_at=p_now WHERE id=later.id;
   UPDATE public.notification_outbox SET available_at=greatest(available_at,paced) WHERE notification_outbox.plan_id=later.id AND status='pending';
  END LOOP;
  FOR o IN SELECT b.* FROM public.notification_outbox b WHERE b.plan_id=p.id AND b.plan_revision=p.revision AND ((b.status='pending' AND b.available_at<=p_now) OR (b.status='claimed' AND b.lease_until<=p_now)) ORDER BY b.available_at,b.id FOR UPDATE SKIP LOCKED LOOP
   IF o.status='claimed' THEN
    INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,error_code,attempted_at) VALUES(o.id,o.attempt_count,o.lease_token,'none','unknown','lease_expired',p_now) ON CONFLICT DO NOTHING;
    IF o.attempt_count>=3 THEN
     UPDATE public.notification_outbox SET status='failed',lease_token=NULL,lease_until=NULL,last_error_code='lease_expired',updated_at=p_now WHERE id=o.id;
     PERFORM public.complete_prompt_plan(p.id); CONTINUE;
    END IF;
   END IF;
   deferred:=public.defer_quiet(p_now);
   IF deferred>p_now THEN
    UPDATE public.notification_outbox SET status='pending',available_at=deferred,lease_token=NULL,lease_until=NULL,updated_at=p_now WHERE id=o.id;
    CONTINUE;
   END IF;
   UPDATE public.notification_outbox b SET status='claimed',attempt_count=b.attempt_count+1,lease_token=gen_random_uuid(),lease_until=p_now+interval '120 seconds',device_seen_at=NULL,updated_at=p_now WHERE b.id=o.id RETURNING b.* INTO o;
   outbox_id:=o.id; plan_id:=p.id; lesson_id:=l.id; kind:=p.kind; recipient_id:=o.recipient_id; device_id:=o.device_id; plan_revision:=o.plan_revision::text; lease_token:=o.lease_token; lease_until:=o.lease_until; attempt_no:=o.attempt_count;
   RETURN NEXT; n:=n+1; IF n>=p_limit THEN RETURN; END IF;
  END LOOP;
 END LOOP;
END $$;
-- Resolve IDs without locks, then acquire in lesson -> plan -> outbox order.
CREATE FUNCTION public.lock_prompt_outbox(p_id uuid) RETURNS public.notification_outbox LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE pid uuid; lid uuid; o public.notification_outbox;
BEGIN
 SELECT p.id,p.lesson_id INTO pid,lid FROM public.notification_outbox b JOIN public.notification_plans p ON p.id=b.plan_id WHERE b.id=p_id;
 PERFORM id FROM public.lessons WHERE id=lid FOR UPDATE;
 PERFORM id FROM public.notification_plans WHERE id=pid FOR UPDATE;
 SELECT * INTO o FROM public.notification_outbox WHERE id=p_id FOR UPDATE;
 RETURN o;
END $$;
CREATE FUNCTION public.prepare_prompt_delivery(p_outbox_id uuid,p_lease_token uuid,p_now timestamptz) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE o public.notification_outbox; p public.notification_plans; l public.lessons; d public.teacher_devices; expiry timestamptz; deferred timestamptz;
BEGIN
 o:=public.lock_prompt_outbox(p_outbox_id);
 IF p_now IS NULL OR o.id IS NULL OR o.status<>'claimed' OR o.lease_token IS DISTINCT FROM p_lease_token OR o.lease_until<=p_now THEN RETURN NULL; END IF;
 SELECT * INTO p FROM public.notification_plans WHERE id=o.plan_id;
 SELECT * INTO l FROM public.lessons WHERE id=p.lesson_id;
 SELECT * INTO d FROM public.teacher_devices WHERE id=o.device_id FOR UPDATE;
 IF NOT public.dispatch_enabled() OR NOT public.prompt_eligible(l.id) OR p.status<>'pending' OR p.revision<>o.plan_revision OR l.accountable_teacher_id<>o.recipient_id OR p.recipient_id<>o.recipient_id OR d.id IS NULL OR d.user_id<>o.recipient_id OR d.revoked_at IS NOT NULL OR d.last_seen_at<p_now-interval '90 days' THEN
  UPDATE public.notification_outbox SET status='cancelled',lease_token=NULL,lease_until=NULL,last_error_code='suppressed',updated_at=p_now WHERE id=o.id;
  INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,error_code,attempted_at) VALUES(o.id,o.attempt_count,o.lease_token,'none','suppressed','suppressed',p_now) ON CONFLICT DO NOTHING;
  PERFORM public.complete_prompt_plan(p.id); RETURN NULL;
 END IF;
 deferred:=public.defer_quiet(p_now);
 IF deferred>p_now THEN
  UPDATE public.notification_outbox SET status='pending',available_at=deferred,attempt_count=attempt_count-1,lease_token=NULL,lease_until=NULL,device_seen_at=NULL,updated_at=p_now WHERE id=o.id;
  RETURN NULL;
 END IF;
 UPDATE public.notification_outbox SET device_seen_at=d.last_seen_at WHERE id=o.id;
 SELECT least(p_now+interval '1 hour',min(due_at)) INTO expiry FROM public.notification_plans WHERE lesson_id=l.id AND id<>p.id AND kind<>'simulation' AND status='pending' AND due_at>p_now;
 RETURN jsonb_build_object('outbox_id',o.id,'lesson_id',l.id,'kind',p.kind,'token',d.token,'environment',d.environment,'collapse_id','tp:'||l.id,'thread_id','teacher-lesson:'||l.id,'expires_at',expiry,'mode',CASE WHEN (SELECT demo_enabled FROM public.runtime_settings) THEN 'dry_run' ELSE 'apns' END);
END $$;
CREATE FUNCTION public.mark_prompt_sent(p_outbox_id uuid,p_lease_token uuid,p_provider_id uuid,p_transport text,p_now timestamptz) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE o public.notification_outbox;
BEGIN
 o:=public.lock_prompt_outbox(p_outbox_id);
 IF p_now IS NULL OR o.id IS NULL OR o.status<>'claimed' OR o.lease_token IS DISTINCT FROM p_lease_token OR o.lease_until<=p_now THEN RETURN false; END IF;
 IF p_provider_id IS NULL OR p_transport IS NULL OR p_transport NOT IN ('dry_run','apns') OR ((SELECT demo_enabled FROM public.runtime_settings) AND p_transport<>'dry_run') OR o.device_seen_at IS NULL THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 UPDATE public.notification_outbox SET status='sent',accepted_at=p_now,lease_token=NULL,lease_until=NULL,last_error_code=NULL,updated_at=p_now WHERE id=o.id;
 INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,provider_id,attempted_at) VALUES(o.id,o.attempt_count,o.lease_token,p_transport,'accepted',p_provider_id,p_now);
 PERFORM public.complete_prompt_plan(o.plan_id);
 RETURN true;
END $$;
CREATE FUNCTION public.mark_prompt_failed(p_outbox_id uuid,p_lease_token uuid,p_error_code text,p_retryable boolean,p_invalidate_device boolean,p_now timestamptz) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE o public.notification_outbox; code text; retry boolean;
BEGIN
 o:=public.lock_prompt_outbox(p_outbox_id);
 IF p_now IS NULL OR o.id IS NULL OR o.status<>'claimed' OR o.lease_token IS DISTINCT FROM p_lease_token OR o.lease_until<=p_now THEN RETURN false; END IF;
 code:=CASE WHEN p_error_code IN ('timeout','network_error','transport_error','rate_limited','server_error','bad_device_token','unregistered','forbidden','bad_request','provider_error','BadDeviceToken','Unregistered') THEN p_error_code ELSE 'provider_error' END;
 retry:=coalesce(p_retryable,false) AND o.attempt_count<3;
 IF coalesce(p_invalidate_device,false) AND code IN ('bad_device_token','unregistered','BadDeviceToken','Unregistered') THEN
  UPDATE public.teacher_devices SET revoked_at=p_now WHERE id=o.device_id AND last_seen_at=o.device_seen_at;
 END IF;
 UPDATE public.notification_outbox SET status=CASE WHEN retry THEN 'pending' ELSE 'failed' END,available_at=CASE WHEN retry THEN public.defer_quiet(p_now+CASE WHEN o.attempt_count=1 THEN interval '1 minute' ELSE interval '5 minutes' END) ELSE available_at END,lease_token=NULL,lease_until=NULL,last_error_code=code,updated_at=p_now WHERE id=o.id;
 INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,error_code,attempted_at) VALUES(o.id,o.attempt_count,o.lease_token,'none',CASE WHEN retry THEN 'retry' ELSE 'permanent_failure' END,code,p_now);
 PERFORM public.complete_prompt_plan(o.plan_id);
 RETURN true;
END $$;
CREATE FUNCTION public.refresh_prompt_schedule() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date; l record;
BEGIN
 PERFORM public.generate_lessons(d,d+42);
 FOR l IN SELECT id FROM public.lessons WHERE cancelled_at IS NULL AND NOT EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=lessons.id) ORDER BY id FOR UPDATE LOOP PERFORM public.replan_lesson(l.id); END LOOP;
END $$;
CREATE FUNCTION public.simulate_prompt_now(p_lesson_id uuid,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:='[]'; result jsonb; l public.lessons; p public.notification_plans; o public.notification_outbox; n timestamptz:=clock_timestamp();
BEGIN
 IF NOT EXISTS(SELECT FROM public.runtime_settings WHERE demo_enabled) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'simulate_prompt_now',args); IF result IS NOT NULL THEN RETURN result; END IF;
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 IF l.cancelled_at IS NOT NULL OR EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id) THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
 IF EXISTS(SELECT FROM public.mutation_receipts WHERE actor_id=auth.uid() AND lesson_id=l.id AND operation='simulate_prompt_now' AND created_at>n-interval '1 minute') THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 INSERT INTO public.notification_plans(lesson_id,kind,revision,recipient_id,due_at,status) VALUES(l.id,'simulation',1,l.accountable_teacher_id,n,'completed') ON CONFLICT(lesson_id,kind) DO UPDATE SET revision=notification_plans.revision+1,recipient_id=EXCLUDED.recipient_id,due_at=n,updated_at=n RETURNING * INTO p;
 INSERT INTO public.notification_outbox(plan_id,plan_revision,recipient_id,status,available_at,attempt_count,accepted_at) VALUES(p.id,p.revision,p.recipient_id,'sent',n,1,n) RETURNING * INTO o;
 INSERT INTO public.notification_deliveries(outbox_id,attempt_no,lease_token,transport,outcome,provider_id,attempted_at) VALUES(o.id,1,gen_random_uuid(),'dry_run','accepted',o.id,n);
 RETURN public.mutation_finish(l.id,p_mutation_id,'simulate_prompt_now',args,jsonb_build_object('lesson_id',l.id,'outbox_id',o.id,'transport','dry_run','kind','attendance','path','/t/lesson/'||l.id));
END $$;
GRANT EXECUTE ON FUNCTION public.snooze_prompt(uuid,int,uuid),public.register_device(uuid,text,text),public.revoke_device(uuid),public.simulate_prompt_now(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plan_prompts(uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.scheduler_tick(timestamptz,int),public.prepare_prompt_delivery(uuid,uuid,timestamptz),public.mark_prompt_sent(uuid,uuid,uuid,text,timestamptz),public.mark_prompt_failed(uuid,uuid,text,boolean,boolean,timestamptz),public.refresh_prompt_schedule(),public.defer_quiet(timestamptz) TO service_role;
-- Hosted installation is separate; no network, invocation secrets, or extension install here.
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_extension WHERE extname='pg_cron') THEN
  PERFORM cron.schedule('teacher-prompts-plan','* * * * *','SELECT public.refresh_prompt_schedule()');
 END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
