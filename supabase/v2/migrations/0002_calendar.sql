BEGIN;
CREATE FUNCTION public.validate_rule() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NOT EXISTS(SELECT FROM public.terms WHERE id=NEW.term_id AND NEW.effective_from>=starts_on AND NEW.effective_until<=ends_on)
 OR NOT EXISTS(SELECT FROM public.profiles WHERE id=NEW.default_teacher_id AND role='teacher' AND active) THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='23514'; END IF;
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'revision') IS DISTINCT FROM (to_jsonb(OLD)-'revision') THEN NEW.revision:=OLD.revision+1; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_rule BEFORE INSERT OR UPDATE ON public.timetable_rules FOR EACH ROW EXECUTE FUNCTION public.validate_rule();
CREATE FUNCTION public.validate_term() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF EXISTS(SELECT FROM public.timetable_rules WHERE term_id=NEW.id AND (effective_from<NEW.starts_on OR effective_until>NEW.ends_on)) THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER validate_term AFTER UPDATE ON public.terms DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_term();
CREATE FUNCTION public.validate_enrollment() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.student_id::text||NEW.class_id::text,2));
 IF EXISTS(SELECT FROM public.enrollments e WHERE e.student_id=NEW.student_id AND e.class_id=NEW.class_id AND e.id<>NEW.id AND daterange(e.starts_on,e.ends_on,'[]') && daterange(NEW.starts_on,NEW.ends_on,'[]')) THEN
  RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_enrollment BEFORE INSERT OR UPDATE ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.validate_enrollment();
CREATE FUNCTION public.validate_lesson_overlap() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.class_id::text,3));
 IF NEW.cancelled_at IS NULL AND EXISTS(SELECT FROM public.lessons l WHERE l.class_id=NEW.class_id AND l.id<>NEW.id AND l.cancelled_at IS NULL AND tstzrange(l.scheduled_start_at,l.scheduled_end_at,'[)') && tstzrange(NEW.scheduled_start_at,NEW.scheduled_end_at,'[)')) THEN
  RAISE EXCEPTION 'TP_CONFLICT' USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER validate_lesson_overlap AFTER INSERT OR UPDATE ON public.lessons DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION public.validate_lesson_overlap();
CREATE FUNCTION public.lesson_has_work(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT FROM public.attendance_records WHERE lesson_id=p_id) OR EXISTS(SELECT FROM public.lesson_feedback WHERE lesson_id=p_id) OR EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=p_id)
$$;
CREATE FUNCTION public.refresh_roster(p_id uuid,p_date date) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons; n int; m int;
BEGIN
 SELECT * INTO STRICT l FROM public.lessons WHERE id=p_id FOR UPDATE;
 IF public.lesson_has_work(p_id) THEN RETURN; END IF;
 DELETE FROM public.lesson_roster r WHERE lesson_id=p_id AND NOT EXISTS(SELECT FROM public.enrollments e JOIN public.students s ON s.id=e.student_id WHERE e.id=r.enrollment_id AND s.active AND e.class_id=l.class_id AND e.starts_on<=p_date AND (e.ends_on IS NULL OR e.ends_on>=p_date));
 GET DIAGNOSTICS n=ROW_COUNT;
 INSERT INTO public.lesson_roster(lesson_id,student_id,enrollment_id)
 SELECT p_id,e.student_id,e.id FROM public.enrollments e JOIN public.students s ON s.id=e.student_id WHERE s.active AND e.class_id=l.class_id AND e.starts_on<=p_date AND (e.ends_on IS NULL OR e.ends_on>=p_date) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS m=ROW_COUNT;
 IF n+m>0 THEN UPDATE public.lessons SET register_revision=register_revision+1,updated_at=clock_timestamp() WHERE id=p_id; END IF;
END $$;
CREATE FUNCTION public.generate_lessons(p_from date,p_until date) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r record; d date; l public.lessons; reason text; st timestamptz; en timestamptz; c int:=0; u int:=0; x int:=0; z int:=0; oldrev bigint;
BEGIN
 PERFORM public.require_service_or_admin();
 IF p_from IS NULL OR p_until IS NULL OR p_until<p_from OR p_until-p_from>91 THEN RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='22023'; END IF;
 -- Lock existing lessons in UUID order before touching their plans.
 PERFORM id FROM public.lessons WHERE occurrence_date BETWEEN p_from AND p_until ORDER BY id FOR UPDATE;
 FOR r IN SELECT tr.* FROM public.timetable_rules tr JOIN public.classes cl ON cl.id=tr.class_id JOIN public.terms t ON t.id=tr.term_id WHERE tr.active AND cl.active ORDER BY tr.id LOOP
  FOR d IN SELECT g::date FROM generate_series(greatest(p_from,r.effective_from)::timestamp,least(p_until,r.effective_until)::timestamp,interval '1 day') g WHERE extract(isodow FROM g)=r.iso_weekday LOOP
   st:=(d+r.local_start) AT TIME ZONE 'Asia/Singapore'; en:=st+make_interval(mins=>r.duration_minutes);
   SELECT reason_code INTO reason FROM public.calendar_exceptions WHERE (class_id IS NULL OR class_id=r.class_id) AND d BETWEEN starts_on AND ends_on ORDER BY (reason_code='public_holiday') DESC LIMIT 1;
   SELECT * INTO l FROM public.lessons WHERE timetable_rule_id=r.id AND occurrence_date=d FOR UPDATE;
   IF NOT FOUND THEN
    INSERT INTO public.lessons(class_id,timetable_rule_id,occurrence_date,scheduled_start_at,scheduled_end_at,source_rule_revision,accountable_teacher_id,cancelled_at,cancellation_reason,overdue_at)
    VALUES(r.class_id,r.id,d,st,en,r.revision,r.default_teacher_id,CASE WHEN reason IS NOT NULL THEN clock_timestamp() END,reason,en+interval '75 minutes') RETURNING * INTO l;
    INSERT INTO public.lesson_staff VALUES(l.id,r.default_teacher_id,'regular');
    PERFORM public.refresh_roster(l.id,d); c:=c+1;
   ELSIF l.cancelled_at IS NOT NULL OR l.scheduled_start_at<=clock_timestamp() OR l.started_at IS NOT NULL OR public.lesson_has_work(l.id) THEN
    z:=z+1;
    IF l.source_rule_revision<>r.revision OR (reason IS NOT NULL AND l.cancelled_at IS NULL) THEN INSERT INTO public.audit_events(lesson_id,event_code,details) VALUES(l.id,'calendar_conflict',jsonb_build_object('reason_code','worked_or_historical')); END IF;
   ELSE
    oldrev:=l.register_revision;
    PERFORM public.refresh_roster(l.id,(CASE WHEN l.schedule_overridden THEN l.scheduled_start_at ELSE st END AT TIME ZONE 'Asia/Singapore')::date);
    IF reason IS NOT NULL THEN
     UPDATE public.lessons SET cancelled_at=clock_timestamp(),cancellation_reason=reason,plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=l.id; x:=x+1;
    ELSE
     IF NOT l.staffing_overridden AND l.accountable_teacher_id<>r.default_teacher_id THEN
      DELETE FROM public.lesson_staff WHERE lesson_id=l.id AND teacher_id=l.accountable_teacher_id;
      INSERT INTO public.lesson_staff VALUES(l.id,r.default_teacher_id,'regular') ON CONFLICT(lesson_id,teacher_id) DO UPDATE SET assignment_kind='regular';
     END IF;
     UPDATE public.lessons SET scheduled_start_at=CASE WHEN schedule_overridden THEN scheduled_start_at ELSE st END,scheduled_end_at=CASE WHEN schedule_overridden THEN scheduled_end_at ELSE en END,
       accountable_teacher_id=CASE WHEN staffing_overridden THEN accountable_teacher_id ELSE r.default_teacher_id END,source_rule_revision=r.revision,
       plan_revision=plan_revision+CASE WHEN (NOT schedule_overridden AND (scheduled_start_at<>st OR scheduled_end_at<>en)) OR (NOT staffing_overridden AND accountable_teacher_id<>r.default_teacher_id) THEN 1 ELSE 0 END,updated_at=clock_timestamp()
     WHERE id=l.id AND (source_rule_revision IS DISTINCT FROM r.revision OR register_revision<>oldrev);
     IF FOUND THEN u:=u+1; ELSE z:=z+1; END IF;
    END IF;
   END IF;
  END LOOP;
 END LOOP;
 FOR l IN SELECT a.* FROM public.lessons a JOIN public.timetable_rules tr ON tr.id=a.timetable_rule_id JOIN public.classes cl ON cl.id=a.class_id
   WHERE a.occurrence_date BETWEEN p_from AND p_until AND a.cancelled_at IS NULL AND (NOT tr.active OR NOT cl.active OR a.occurrence_date NOT BETWEEN tr.effective_from AND tr.effective_until OR extract(isodow FROM a.occurrence_date)<>tr.iso_weekday) ORDER BY a.id FOR UPDATE OF a LOOP
  IF l.scheduled_start_at>clock_timestamp() AND l.started_at IS NULL AND NOT public.lesson_has_work(l.id) THEN
   UPDATE public.lessons SET cancelled_at=clock_timestamp(),cancellation_reason='rule_removed',plan_revision=plan_revision+1,updated_at=clock_timestamp() WHERE id=l.id; x:=x+1;
  ELSE INSERT INTO public.audit_events(lesson_id,event_code,details) VALUES(l.id,'calendar_conflict','{"reason_code":"worked_or_historical"}'); END IF;
 END LOOP;
 RETURN jsonb_build_object('created',c,'updated',u,'cancelled',x,'unchanged',z);
END $$;
CREATE FUNCTION public.lesson_state(p_lesson_id uuid,p_now timestamptz) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE l public.lessons;
BEGIN
 PERFORM public.require_enabled();
 IF NOT public.can_read_lesson(p_lesson_id) OR NOT EXISTS(SELECT FROM public.lessons a JOIN public.classes c ON c.id=a.class_id WHERE a.id=p_lesson_id AND NOT c.is_study_space) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id;
 RETURN CASE WHEN l.cancelled_at IS NOT NULL THEN 'cancelled' WHEN EXISTS(SELECT FROM public.lesson_submissions WHERE lesson_id=l.id) THEN 'submitted'
 WHEN p_now>=l.overdue_at THEN 'overdue' WHEN p_now>=l.scheduled_end_at OR l.ended_at IS NOT NULL THEN 'awaiting_attendance'
 WHEN p_now>=l.scheduled_start_at OR l.started_at IS NOT NULL THEN 'in_progress' ELSE 'scheduled' END;
END $$;
GRANT EXECUTE ON FUNCTION public.generate_lessons(date,date) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lesson_state(uuid,timestamptz) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
