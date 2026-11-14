BEGIN;
-- Advisory receipt lock precedes the lesson row; CURRENT authority precedes replay.
CREATE FUNCTION public.mutation_begin(p_lesson uuid,p_mutation uuid,p_operation text,p_args jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.mutation_receipts; h text;
BEGIN
 IF p_mutation IS NULL THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_mutation::text,1));
 PERFORM id FROM public.lessons WHERE id=p_lesson FOR UPDATE;
 PERFORM public.require_review(p_lesson);
 h:=encode(public.digest(jsonb_build_array(p_operation,p_lesson,p_args)::text,'sha256'),'hex');
 SELECT * INTO r FROM public.mutation_receipts WHERE actor_id=auth.uid() AND mutation_id=p_mutation;
 IF FOUND THEN
  IF r.request_hash<>h THEN RAISE EXCEPTION 'TP_MUTATION_REUSED' USING ERRCODE='P0001'; END IF;
  RETURN r.result||'{"replayed":true}'::jsonb;
 END IF;
 RETURN NULL;
END $$;
CREATE FUNCTION public.mutation_finish(p_lesson uuid,p_mutation uuid,p_operation text,p_args jsonb,p_result jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 INSERT INTO public.mutation_receipts(actor_id,mutation_id,operation,lesson_id,request_hash,result) VALUES(auth.uid(),p_mutation,p_operation,p_lesson,encode(public.digest(jsonb_build_array(p_operation,p_lesson,p_args)::text,'sha256'),'hex'),p_result||'{"replayed":false}');
 INSERT INTO public.audit_events(actor_id,lesson_id,event_code) VALUES(auth.uid(),p_lesson,p_operation);
 RETURN p_result||'{"replayed":false}';
END $$;
CREATE FUNCTION public.require_editable(p_lesson uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons;
BEGIN
 SELECT * INTO STRICT l FROM public.lessons WHERE id=p_lesson FOR UPDATE;
 IF l.cancelled_at IS NOT NULL OR EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id) THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
 IF clock_timestamp()<l.scheduled_start_at THEN RAISE EXCEPTION 'TP_TOO_EARLY' USING ERRCODE='P0001'; END IF;
 IF NOT public.is_admin() AND (clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date-(l.scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date>7 THEN RAISE EXCEPTION 'TP_TOO_OLD' USING ERRCODE='P0001'; END IF;
END $$;
CREATE FUNCTION public.lesson_summary(p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons; s public.lesson_submissions; n timestamptz:=now(); editable boolean; pending boolean; roster_n int; marked_n int;
BEGIN
 PERFORM public.require_review(p_id);
 SELECT * INTO STRICT l FROM public.lessons WHERE id=p_id;
 SELECT * INTO s FROM public.lesson_submissions WHERE lesson_id=p_id;
 SELECT count(*) INTO roster_n FROM public.lesson_roster WHERE lesson_id=p_id;
 SELECT count(*) INTO marked_n FROM public.attendance_records WHERE lesson_id=p_id;
 editable:=l.cancelled_at IS NULL AND s.id IS NULL AND n>=l.scheduled_start_at AND (public.is_admin() OR (n AT TIME ZONE 'Asia/Singapore')::date-(l.scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date<=7);
 pending:=EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=p_id AND kind<>'simulation' AND status='pending');
 RETURN jsonb_build_object('lesson_id',l.id,'class_id',l.class_id,'class_label',(SELECT short_label FROM public.classes WHERE id=l.class_id),
 'scheduled_start_at',l.scheduled_start_at,'scheduled_end_at',l.scheduled_end_at,'state',public.lesson_state(p_id,n),'accountable_teacher_id',l.accountable_teacher_id,
 'accountable_teacher_label',(SELECT display_name FROM public.profiles WHERE id=l.accountable_teacher_id),'is_accountable',l.accountable_teacher_id=auth.uid(),
 'register_revision',l.register_revision::text,'roster_count',roster_n,'marked_count',marked_n,'submitted_at',s.submitted_at,
 'next_prompt_at',(SELECT min(due_at) FROM public.notification_plans WHERE lesson_id=p_id AND kind<>'simulation' AND status='pending'),
 'snoozed_until',l.snoozed_until,'overdue_at',l.overdue_at,'can_edit',editable,'can_submit',editable AND roster_n=marked_n AND (roster_n>0 OR public.is_admin()),
 'can_snooze',l.cancelled_at IS NULL AND s.id IS NULL AND pending AND n>=l.scheduled_end_at-interval '5 minutes' AND l.snooze_count<(SELECT max_snoozes FROM public.prompt_policy) AND greatest(n,coalesce(l.snoozed_until,n))<l.scheduled_end_at+interval '60 minutes');
END $$;
CREATE FUNCTION public.my_lessons_today(p_date date DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d date:=coalesce(p_date,(now() AT TIME ZONE 'Asia/Singapore')::date); todays jsonb; backlog jsonb; outstanding int;
BEGIN
 PERFORM public.require_enabled();
 SELECT coalesce(jsonb_agg(public.lesson_summary(l.id) ORDER BY l.scheduled_start_at,l.id),'[]') INTO todays FROM public.lessons l JOIN public.classes c ON c.id=l.class_id WHERE NOT c.is_study_space AND public.can_review_lesson(l.id) AND (l.scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date=d;
 SELECT coalesce(jsonb_agg(public.lesson_summary(l.id) ORDER BY l.scheduled_start_at,l.id),'[]') INTO backlog FROM public.lessons l JOIN public.classes c ON c.id=l.class_id WHERE NOT c.is_study_space AND public.can_review_lesson(l.id) AND (l.scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date BETWEEN d-CASE WHEN public.is_admin() THEN 92 ELSE 7 END AND d-1 AND l.cancelled_at IS NULL AND NOT EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id);
 SELECT count(*) INTO outstanding FROM jsonb_array_elements(todays||backlog) v WHERE v->>'state' NOT IN ('submitted','cancelled') AND (v->>'scheduled_start_at')::timestamptz<=now();
 RETURN jsonb_build_object('server_now',now(),'date',d,'lessons',todays,'backlog',backlog,'outstanding_count',outstanding);
END $$;
CREATE FUNCTION public.lesson_for_prompt(p_lesson_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE roster jsonb; feedback jsonb; submission jsonb;
BEGIN
 PERFORM public.require_review(p_lesson_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('student_id',r.student_id,'display_name',s.display_name,'status',a.status,'absence_informed',a.absence_informed,'marked_at',a.marked_at) ORDER BY s.display_name,r.student_id),'[]') INTO roster
 FROM public.lesson_roster r JOIN public.students s ON s.id=r.student_id LEFT JOIN public.attendance_records a USING(lesson_id,student_id) WHERE r.lesson_id=p_lesson_id;
 SELECT jsonb_build_object('body',body,'revision',revision::text) INTO feedback FROM public.lesson_feedback WHERE lesson_id=p_lesson_id;
 SELECT jsonb_build_object('id',id,'submitted_at',submitted_at,'submitted_by',submitted_by,'register_revision',register_revision::text) INTO submission FROM public.lesson_submissions WHERE lesson_id=p_lesson_id;
 RETURN jsonb_build_object('server_now',now(),'lesson',public.lesson_summary(p_lesson_id),'roster',roster,'feedback',coalesce(feedback,'{"body":"","revision":"0"}'),'submission',submission);
END $$;
CREATE FUNCTION public.mark_attendance(p_lesson_id uuid,p_student_id uuid,p_status text,p_absence_informed boolean,p_observed_marked_at timestamptz,p_expected_revision bigint,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:=jsonb_build_array(p_student_id,p_status,p_absence_informed,to_char(p_observed_marked_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),p_expected_revision); result jsonb; l public.lessons; a public.attendance_records; ts timestamptz; changed boolean;
BEGIN
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'mark_attendance',args); IF result IS NOT NULL THEN RETURN result; END IF;
 PERFORM public.require_editable(p_lesson_id);
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 IF p_expected_revision IS DISTINCT FROM l.register_revision THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 IF NOT EXISTS(SELECT FROM public.lesson_roster WHERE lesson_id=l.id AND student_id=p_student_id) OR (p_status IS NOT NULL AND p_status NOT IN ('present','late','absent')) OR (p_status IS DISTINCT FROM 'absent' AND p_absence_informed IS NOT NULL) THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM public.attendance_records WHERE lesson_id=l.id AND student_id=p_student_id;
 IF a.marked_at IS DISTINCT FROM p_observed_marked_at THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 changed:=(a.status IS DISTINCT FROM p_status OR a.absence_informed IS DISTINCT FROM p_absence_informed);
 ts:=a.marked_at;
 IF changed THEN
  IF p_status IS NULL THEN DELETE FROM public.attendance_records WHERE lesson_id=l.id AND student_id=p_student_id; ts:=NULL;
  ELSE
   ts:=greatest(clock_timestamp(),a.marked_at+interval '1 microsecond');
   INSERT INTO public.attendance_records VALUES(l.id,p_student_id,p_status,p_absence_informed,auth.uid(),ts,p_mutation_id)
   ON CONFLICT(lesson_id,student_id) DO UPDATE SET status=EXCLUDED.status,absence_informed=EXCLUDED.absence_informed,marked_by=EXCLUDED.marked_by,marked_at=EXCLUDED.marked_at,mutation_id=EXCLUDED.mutation_id;
  END IF;
  UPDATE public.lessons SET register_revision=register_revision+1,updated_at=clock_timestamp() WHERE id=l.id RETURNING * INTO l;
 END IF;
 RETURN public.mutation_finish(l.id,p_mutation_id,'mark_attendance',args,jsonb_build_object('lesson_id',l.id,'student_id',p_student_id,'status',p_status,'absence_informed',p_absence_informed,'marked_at',ts,'register_revision',l.register_revision::text));
END $$;
CREATE FUNCTION public.mark_all_present(p_lesson_id uuid,p_expected_revision bigint,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:=jsonb_build_array(p_expected_revision); result jsonb; rev bigint; n int;
BEGIN
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'mark_all_present',args); IF result IS NOT NULL THEN RETURN result; END IF;
 PERFORM public.require_editable(p_lesson_id);
 SELECT register_revision INTO rev FROM public.lessons WHERE id=p_lesson_id;
 IF p_expected_revision IS DISTINCT FROM rev THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 INSERT INTO public.attendance_records(lesson_id,student_id,status,marked_by,marked_at,mutation_id)
 SELECT p_lesson_id,r.student_id,'present',auth.uid(),clock_timestamp(),p_mutation_id FROM public.lesson_roster r WHERE lesson_id=p_lesson_id ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n>0 THEN UPDATE public.lessons SET register_revision=register_revision+1,updated_at=clock_timestamp() WHERE id=p_lesson_id RETURNING register_revision INTO rev; END IF;
 RETURN public.mutation_finish(p_lesson_id,p_mutation_id,'mark_all_present',args,jsonb_build_object('lesson_id',p_lesson_id,'changed_count',n,'register_revision',rev::text));
END $$;
CREATE FUNCTION public.save_feedback(p_lesson_id uuid,p_body text,p_expected_feedback_revision bigint,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:=jsonb_build_array(p_body,p_expected_feedback_revision); result jsonb; rev bigint;
BEGIN
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'save_feedback',args); IF result IS NOT NULL THEN RETURN result; END IF;
 PERFORM public.require_editable(p_lesson_id);
 IF p_body IS NULL OR length(btrim(p_body))>1000 OR p_body ~* '[STFGM][0-9]{7}[A-Z]' THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 SELECT coalesce((SELECT revision FROM public.lesson_feedback WHERE lesson_id=p_lesson_id),0) INTO rev;
 IF p_expected_feedback_revision IS DISTINCT FROM rev THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 INSERT INTO public.lesson_feedback VALUES(p_lesson_id,btrim(p_body),auth.uid(),clock_timestamp(),rev+1)
 ON CONFLICT(lesson_id) DO UPDATE SET body=EXCLUDED.body,updated_by=EXCLUDED.updated_by,updated_at=EXCLUDED.updated_at,revision=EXCLUDED.revision;
 RETURN public.mutation_finish(p_lesson_id,p_mutation_id,'save_feedback',args,jsonb_build_object('lesson_id',p_lesson_id,'feedback_revision',(rev+1)::text));
END $$;
CREATE FUNCTION public.submit_lesson(p_lesson_id uuid,p_expected_revision bigint,p_expected_feedback_revision bigint,p_mutation_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE args jsonb:=jsonb_build_array(p_expected_revision,p_expected_feedback_revision); result jsonb; l public.lessons; s public.lesson_submissions; rev bigint;
BEGIN
 result:=public.mutation_begin(p_lesson_id,p_mutation_id,'submit_lesson',args); IF result IS NOT NULL THEN RETURN result; END IF;
 PERFORM public.require_editable(p_lesson_id);
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 SELECT coalesce((SELECT revision FROM public.lesson_feedback WHERE lesson_id=p_lesson_id),0) INTO rev;
 IF p_expected_revision IS DISTINCT FROM l.register_revision OR p_expected_feedback_revision IS DISTINCT FROM rev THEN RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001'; END IF;
 IF (NOT public.is_admin() AND NOT EXISTS(SELECT FROM public.lesson_roster WHERE lesson_id=l.id)) OR EXISTS(SELECT FROM public.lesson_roster r WHERE lesson_id=l.id AND NOT EXISTS(SELECT FROM public.attendance_records a WHERE a.lesson_id=r.lesson_id AND a.student_id=r.student_id)) THEN RAISE EXCEPTION 'TP_INCOMPLETE' USING ERRCODE='P0001'; END IF;
 INSERT INTO public.lesson_submissions(lesson_id,register_revision,feedback_revision,submitted_by,submitted_at,mutation_id) VALUES(l.id,l.register_revision,rev,auth.uid(),clock_timestamp(),p_mutation_id) RETURNING * INTO s;
 RETURN public.mutation_finish(l.id,p_mutation_id,'submit_lesson',args,jsonb_build_object('lesson_id',l.id,'submission_id',s.id,'submitted_at',s.submitted_at,'register_revision',l.register_revision::text));
END $$;
CREATE FUNCTION public.require_admin_lesson(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM id FROM public.lessons WHERE id=p_id FOR UPDATE;
 PERFORM public.require_review(p_id);
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=p_id) THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
END $$;
CREATE FUNCTION public.edit_lesson(p_lesson_id uuid,p_start_at timestamptz,p_end_at timestamptz) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons;
BEGIN
 PERFORM public.require_admin_lesson(p_lesson_id);
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 IF l.cancelled_at IS NOT NULL OR l.started_at IS NOT NULL OR l.scheduled_start_at<=clock_timestamp() OR public.lesson_has_work(l.id) THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
 IF p_start_at IS NULL OR p_end_at IS NULL OR p_start_at<=clock_timestamp() OR p_end_at<=p_start_at OR p_end_at>p_start_at+interval '4 hours' THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 UPDATE public.lessons SET scheduled_start_at=p_start_at,scheduled_end_at=p_end_at,schedule_overridden=true,plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=l.id;
 PERFORM public.refresh_roster(l.id,(p_start_at AT TIME ZONE 'Asia/Singapore')::date);
 INSERT INTO public.audit_events(actor_id,lesson_id,event_code) VALUES(auth.uid(),l.id,'rescheduled');
 RETURN public.lesson_summary(l.id);
END $$;
CREATE FUNCTION public.assign_lesson_teacher(p_lesson_id uuid,p_teacher_id uuid,p_keep_previous_as_assistant boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons;
BEGIN
 PERFORM public.require_admin_lesson(p_lesson_id);
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 IF l.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'TP_LOCKED' USING ERRCODE='P0001'; END IF;
 IF p_keep_previous_as_assistant IS NULL OR NOT EXISTS(SELECT FROM public.profiles WHERE id=p_teacher_id AND role='teacher' AND active) THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 IF p_teacher_id<>l.accountable_teacher_id THEN
  IF p_keep_previous_as_assistant THEN UPDATE public.lesson_staff SET assignment_kind='assistant' WHERE lesson_id=l.id AND teacher_id=l.accountable_teacher_id;
  ELSE DELETE FROM public.lesson_staff WHERE lesson_id=l.id AND teacher_id=l.accountable_teacher_id; END IF;
  INSERT INTO public.lesson_staff VALUES(l.id,p_teacher_id,'substitute') ON CONFLICT(lesson_id,teacher_id) DO UPDATE SET assignment_kind='substitute';
  UPDATE public.lessons SET accountable_teacher_id=p_teacher_id,staffing_overridden=true,plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=l.id;
  INSERT INTO public.audit_events(actor_id,lesson_id,event_code) VALUES(auth.uid(),l.id,'reassigned');
 END IF;
 RETURN public.lesson_summary(l.id);
END $$;
CREATE FUNCTION public.cancel_lesson(p_lesson_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM public.require_admin_lesson(p_lesson_id);
 UPDATE public.lessons SET cancelled_at=clock_timestamp(),cancellation_reason='manual',plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=p_lesson_id AND cancelled_at IS NULL;
 IF FOUND THEN INSERT INTO public.audit_events(actor_id,lesson_id,event_code) VALUES(auth.uid(),p_lesson_id,'cancelled'); END IF;
 RETURN public.lesson_summary(p_lesson_id);
END $$;
CREATE FUNCTION public.admin_missing_submissions(p_from date,p_until date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE rows jsonb;
BEGIN
 PERFORM public.require_enabled();
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 IF p_from IS NULL OR p_until IS NULL OR p_until<p_from OR p_until-p_from>91 THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(public.lesson_summary(l.id)||jsonb_build_object('delivery_state',CASE
  WHEN EXISTS(SELECT FROM public.notification_plans p JOIN public.notification_outbox o ON o.plan_id=p.id AND o.plan_revision=p.revision WHERE p.lesson_id=l.id AND o.status IN ('pending','claimed')) THEN 'pending'
  ELSE coalesce((SELECT CASE d.outcome WHEN 'accepted' THEN 'accepted' WHEN 'no_devices' THEN 'no_devices' ELSE 'failed' END FROM public.notification_deliveries d JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l.id ORDER BY d.attempted_at DESC,d.id DESC LIMIT 1),'not_attempted') END,
  'last_attempt_at',(SELECT max(d.attempted_at) FROM public.notification_deliveries d JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l.id)) ORDER BY l.scheduled_start_at,l.id),'[]') INTO rows
 FROM public.lessons l JOIN public.classes c ON c.id=l.class_id WHERE NOT c.is_study_space AND l.cancelled_at IS NULL AND l.scheduled_end_at<=now() AND (l.scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date BETWEEN p_from AND p_until AND NOT EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id);
 RETURN jsonb_build_object('server_now',now(),'from',p_from,'until',p_until,'lessons',rows);
END $$;
GRANT EXECUTE ON FUNCTION public.my_lessons_today(date),public.lesson_for_prompt(uuid),public.mark_attendance(uuid,uuid,text,boolean,timestamptz,bigint,uuid),public.mark_all_present(uuid,bigint,uuid),public.save_feedback(uuid,text,bigint,uuid),public.submit_lesson(uuid,bigint,bigint,uuid),public.admin_missing_submissions(date,date),public.edit_lesson(uuid,timestamptz,timestamptz),public.assign_lesson_teacher(uuid,uuid,boolean),public.cancel_lesson(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
