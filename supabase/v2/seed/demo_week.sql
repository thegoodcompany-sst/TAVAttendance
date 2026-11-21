-- Fake local fixtures only. Repeat seeding preserves an existing demo's work.
BEGIN;
DO $$ BEGIN
 IF inet_server_port() IS DISTINCT FROM 55432 OR inet_server_addr() NOT IN ('127.0.0.1'::inet,'::1'::inet) THEN RAISE EXCEPTION 'Demo seed requires local throwaway server'; END IF;
 IF EXISTS(SELECT FROM public.profiles WHERE id NOT IN ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011','10000000-0000-4000-8000-000000000012','10000000-0000-4000-8000-000000000013','10000000-0000-4000-8000-000000000014','10000000-0000-4000-8000-000000000099') OR display_name NOT LIKE 'Demo %') OR EXISTS(SELECT FROM public.students WHERE id::text NOT LIKE '20000000-0000-4000-8000-%' OR display_name !~ '^Demo Student [0-9]{2}$') THEN RAISE EXCEPTION 'Demo seed refuses non-demo data'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.demo_seed_state(id boolean PRIMARY KEY DEFAULT true CHECK(id),anchor_date date NOT NULL);
ALTER TABLE public.demo_seed_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.demo_seed_state FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.demo_seed_state TO service_role;
DO $$
DECLARE i int; uid uuid; cid uuid; rule_id uuid; lesson uuid; sci uuid; math uuid; eng uuid;
BEGIN
 IF EXISTS(SELECT FROM public.demo_seed_state) THEN RETURN; END IF;
 INSERT INTO auth.users(id,email) SELECT ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'demo'||n||'@example.invalid' FROM unnest(ARRAY[1,11,12,13,14,99]) n ON CONFLICT DO NOTHING;
 INSERT INTO public.profiles(id,display_name,role) SELECT id,CASE WHEN right(id::text,2)='01' THEN 'Demo Admin' WHEN right(id::text,2)='99' THEN 'Demo Parent' ELSE 'Demo Teacher '||chr(65+right(id::text,2)::int-11) END,CASE WHEN right(id::text,2)='01' THEN 'admin' WHEN right(id::text,2)='99' THEN 'parent' ELSE 'teacher' END FROM auth.users ON CONFLICT DO NOTHING;
 FOR i IN 1..30 LOOP INSERT INTO public.students(id,display_name) VALUES(('20000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Demo Student '||lpad(i::text,2,'0')) ON CONFLICT DO NOTHING; END LOOP;
 INSERT INTO public.classes(id,short_label,subject) VALUES
 ('30000000-0000-4000-8000-000000000001','English','English'),('30000000-0000-4000-8000-000000000002','Mathematics','Mathematics'),('30000000-0000-4000-8000-000000000003','Reading','Reading'),('30000000-0000-4000-8000-000000000004','Science','Science') ON CONFLICT DO NOTHING;
 INSERT INTO public.terms VALUES('40000000-0000-4000-8000-000000000001','Demo Term','2027-01-01','2027-03-31');
 FOR i IN 1..4 LOOP
  cid:=('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid; rule_id:=('50000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid;
  uid:=('10000000-0000-4000-8000-'||lpad((10+least(i,3))::text,12,'0'))::uuid;
  INSERT INTO public.timetable_rules(id,class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
  VALUES(rule_id,cid,'40000000-0000-4000-8000-000000000001',(ARRAY[1,4,5,6])[i],CASE WHEN i=4 THEN '10:00'::time ELSE '19:00'::time END,CASE WHEN i=3 THEN 90 ELSE 120 END,'2027-01-01','2027-03-31',uid);
 END LOOP;
 FOR i IN 1..30 LOOP
  cid:=('30000000-0000-4000-8000-'||lpad((CASE WHEN i<=10 THEN 1 WHEN i<=20 THEN 2 WHEN i<=25 THEN 3 ELSE 4 END)::text,12,'0'))::uuid;
  INSERT INTO public.enrollments(id,student_id,class_id,starts_on) VALUES(('60000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('20000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,cid,'2027-01-01');
 END LOOP;
 INSERT INTO public.calendar_exceptions(id,starts_on,ends_on,kind,reason_code) VALUES('70000000-0000-4000-8000-000000000001','2027-01-01','2027-01-01','holiday','public_holiday');
 UPDATE public.runtime_settings SET demo_enabled=true;
 UPDATE public.feature_flags SET enabled=true WHERE key='teacher_prompts';
 PERFORM public.generate_lessons('2027-01-01','2027-02-12');
 SELECT id INTO eng FROM public.lessons WHERE class_id='30000000-0000-4000-8000-000000000001' AND occurrence_date='2027-01-04';
 SELECT id INTO math FROM public.lessons WHERE class_id='30000000-0000-4000-8000-000000000002' AND occurrence_date='2027-01-07';
 SELECT id INTO sci FROM public.lessons WHERE class_id='30000000-0000-4000-8000-000000000004' AND occurrence_date='2027-01-02';
 INSERT INTO public.lesson_staff VALUES(eng,'10000000-0000-4000-8000-000000000012','assistant');
 DELETE FROM public.lesson_staff WHERE lesson_id=math;
 INSERT INTO public.lesson_staff VALUES(math,'10000000-0000-4000-8000-000000000014','substitute');
 UPDATE public.lessons SET accountable_teacher_id='10000000-0000-4000-8000-000000000014',staffing_overridden=true,started_at='2027-01-07 19:00+08',snoozed_until='2027-01-07 21:10+08',snooze_count=1,plan_revision=plan_revision+1 WHERE id=math;
 INSERT INTO public.attendance_records(lesson_id,student_id,status,absence_informed,marked_by,marked_at,mutation_id)
 SELECT math,student_id,CASE right(student_id::text,2)::int WHEN 12 THEN 'late' WHEN 13 THEN 'absent' ELSE 'present' END,CASE WHEN right(student_id::text,2)::int=13 THEN true END,'10000000-0000-4000-8000-000000000014','2027-01-07 20:55+08',gen_random_uuid() FROM public.lesson_roster WHERE lesson_id=math AND right(student_id::text,2)::int<=16;
 INSERT INTO public.lesson_feedback VALUES(math,'Demo lesson notes.','10000000-0000-4000-8000-000000000014','2027-01-07 20:55+08',1);
 UPDATE public.lessons SET register_revision=register_revision+1 WHERE id=math;
 INSERT INTO public.attendance_records(lesson_id,student_id,status,absence_informed,marked_by,marked_at,mutation_id)
 SELECT sci,student_id,CASE WHEN right(student_id::text,2)='30' THEN 'absent' ELSE 'present' END,CASE WHEN right(student_id::text,2)='30' THEN true END,'10000000-0000-4000-8000-000000000013','2027-01-02 12:00+08',gen_random_uuid() FROM public.lesson_roster WHERE lesson_id=sci;
 UPDATE public.lessons SET started_at='2027-01-02 10:00+08',ended_at='2027-01-02 12:00+08',register_revision=register_revision+1 WHERE id=sci;
 INSERT INTO public.lesson_submissions(lesson_id,register_revision,feedback_revision,submitted_by,submitted_at,mutation_id) SELECT sci,register_revision,0,'10000000-0000-4000-8000-000000000013','2027-01-02 12:05+08',gen_random_uuid() FROM public.lessons WHERE id=sci;
 FOR i IN 11..14 LOOP
  INSERT INTO public.teacher_devices(id,user_id,installation_id,token,environment,last_seen_at) VALUES(('80000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,('90000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,repeat(lpad(to_hex(i),2,'0'),32),'sandbox','2027-01-01 09:00+08');
 END LOOP;
 INSERT INTO public.demo_seed_state VALUES(true,'2027-01-07');
END $$;
CREATE OR REPLACE FUNCTION public.demo_shift_to_today() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE anchor date; demo_now timestamptz:=clock_timestamp(); today date:=(demo_now AT TIME ZONE 'Asia/Singapore')::date;
 days int; delta interval; l record; teacher_no int; scenario int; teacher_id uuid; demo_class_id uuid; demo_lesson_id uuid;
 midnight timestamptz:=today::timestamp AT TIME ZONE 'Asia/Singapore';
 rounded_now timestamptz:=date_bin(interval '5 minutes',demo_now,timestamptz '2000-01-01 00:00+08');
 current_start timestamptz; current_end timestamptz; earlier_span interval; slot int; slot_start timestamptz; slot_end timestamptz;
BEGIN
 IF NOT EXISTS(SELECT FROM public.runtime_settings WHERE demo_enabled) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 SELECT anchor_date INTO STRICT anchor FROM public.demo_seed_state WHERE id FOR UPDATE;
 days:=today-anchor; delta:=days*interval '24 hours';
 IF days=0 AND EXISTS(SELECT FROM public.lessons WHERE id='a0000000-0000-4000-8000-000000000111') THEN
  RETURN jsonb_build_object('anchor_date',today,'shift_days',0);
 END IF;
 PERFORM id FROM public.lessons ORDER BY id FOR UPDATE;
 SET CONSTRAINTS validate_lesson_overlap,validate_term DEFERRED;
 -- Expand term first so immediate rule-boundary validation stays meaningful.
 UPDATE public.terms SET starts_on=least(starts_on,starts_on+days),ends_on=greatest(ends_on,ends_on+days);
 UPDATE public.timetable_rules SET effective_from=effective_from+days,effective_until=effective_until+days,iso_weekday=(((iso_weekday-1+days)%7+7)%7+1)::smallint;
 UPDATE public.terms SET starts_on=CASE WHEN days<0 THEN starts_on ELSE starts_on+days END,ends_on=CASE WHEN days>0 THEN ends_on ELSE ends_on+days END;
 UPDATE public.enrollments SET starts_on=starts_on+days,ends_on=ends_on+days;
 UPDATE public.calendar_exceptions SET starts_on=starts_on+days,ends_on=ends_on+days;
 UPDATE public.lessons SET occurrence_date=occurrence_date+days,scheduled_start_at=scheduled_start_at+delta,scheduled_end_at=scheduled_end_at+delta,started_at=started_at+delta,ended_at=ended_at+delta,cancelled_at=cancelled_at+delta,snoozed_until=snoozed_until+delta,overdue_at=overdue_at+delta,updated_at=clock_timestamp();
 UPDATE public.attendance_records SET marked_at=marked_at+delta;
 UPDATE public.lesson_feedback SET updated_at=updated_at+delta;
 UPDATE public.lesson_submissions SET submitted_at=submitted_at+delta;
 UPDATE public.teacher_devices SET last_seen_at=last_seen_at+delta;
 -- Preserve accepted delivery history; invalidate leases before recomputing only pending work.
 UPDATE public.notification_outbox SET status='cancelled',lease_token=NULL,lease_until=NULL,last_error_code='superseded' WHERE status IN ('pending','claimed');
 UPDATE public.notification_plans SET due_at=due_at+delta WHERE status<>'pending';
 FOR l IN SELECT id FROM public.lessons ORDER BY id LOOP UPDATE public.lessons SET plan_revision=plan_revision+1 WHERE id=l.id; END LOOP;

 -- Demo-only, now-relative examples. Keep the canonical substitute Mathematics
 -- UUID as the only Mathematics occurrence today (also used by browser fixtures).
 -- Other examples are ad hoc, so calendar refresh cannot rewrite their timing.
 -- Near midnight compress the earlier slots into the first half of elapsed time;
 -- positive sub-second slots are valid and never invent work on yesterday's date.
 earlier_span:=least(interval '1 hour',(demo_now-midnight)/2);
 IF earlier_span<=interval '0 seconds' THEN earlier_span:=interval '1 microsecond'; END IF;
 current_start:=greatest(midnight+earlier_span,rounded_now-interval '115 minutes');
 current_end:=least(rounded_now+interval '5 minutes',midnight+interval '1 day'-interval '1 microsecond');
 FOR teacher_no IN 11..14 LOOP
  teacher_id:=('10000000-0000-4000-8000-'||lpad(teacher_no::text,12,'0'))::uuid;
  -- A: English, B: Science, C: Reading, D: existing substituted Mathematics.
  demo_class_id:=('30000000-0000-4000-8000-'||lpad((CASE teacher_no WHEN 11 THEN 1 WHEN 12 THEN 4 WHEN 13 THEN 3 ELSE 2 END)::text,12,'0'))::uuid;
  FOR scenario IN 1..3 LOOP
   IF teacher_no=14 AND scenario=1 THEN
    SELECT id INTO STRICT demo_lesson_id FROM public.lessons
     WHERE timetable_rule_id='50000000-0000-4000-8000-000000000002' AND occurrence_date=today;
    UPDATE public.lessons SET scheduled_start_at=current_start,scheduled_end_at=current_end,
     started_at=current_start,ended_at=NULL,schedule_overridden=true,snoozed_until=NULL,snooze_count=0,
     plan_revision=plan_revision+1 WHERE id=demo_lesson_id;
    UPDATE public.attendance_records SET marked_at=least(demo_now,current_end) WHERE public.attendance_records.lesson_id=demo_lesson_id;
    UPDATE public.lesson_feedback SET updated_at=demo_now WHERE public.lesson_feedback.lesson_id=demo_lesson_id;
    CONTINUE;
   END IF;
   demo_lesson_id:=('a0000000-0000-4000-8000-'||lpad((teacher_no*10+scenario)::text,12,'0'))::uuid;
   IF scenario=1 THEN
    slot_start:=current_start; slot_end:=current_end;
   ELSE
    -- D's earlier examples use Science, leaving Mathematics unique today.
    -- Science has four disjoint earlier slots; the other classes need only two.
    slot:=(CASE WHEN teacher_no=14 THEN 2 ELSE 0 END)+(CASE WHEN scenario=3 THEN 0 ELSE 1 END);
    slot_start:=current_start-earlier_span+earlier_span*slot/4;
    slot_end:=current_start-earlier_span+earlier_span*(slot+1)/4;
   END IF;
   INSERT INTO public.lessons(id,class_id,occurrence_date,scheduled_start_at,scheduled_end_at,
    accountable_teacher_id,schedule_overridden,staffing_overridden,started_at,ended_at,overdue_at)
   VALUES(demo_lesson_id,CASE WHEN teacher_no=14 THEN '30000000-0000-4000-8000-000000000004'::uuid ELSE demo_class_id END,
    today,slot_start,slot_end,teacher_id,true,true,slot_start,CASE WHEN scenario<>1 THEN slot_end END,current_end+interval '75 minutes')
   ON CONFLICT(id) DO UPDATE SET occurrence_date=today,scheduled_start_at=EXCLUDED.scheduled_start_at,
    scheduled_end_at=EXCLUDED.scheduled_end_at,started_at=EXCLUDED.started_at,ended_at=EXCLUDED.ended_at,
    plan_revision=public.lessons.plan_revision+1;
   INSERT INTO public.lesson_staff VALUES(demo_lesson_id,teacher_id,'regular') ON CONFLICT DO NOTHING;
   INSERT INTO public.lesson_roster(lesson_id,student_id,enrollment_id)
    SELECT demo_lesson_id,e.student_id,e.id FROM public.enrollments e
    WHERE e.class_id=CASE WHEN teacher_no=14 THEN '30000000-0000-4000-8000-000000000004'::uuid ELSE demo_class_id END
     AND e.starts_on<=today AND (e.ends_on IS NULL OR e.ends_on>=today)
    ON CONFLICT DO NOTHING;
   IF scenario=2 THEN
    -- A synthetic pending review with a future deadline, even when today's
    -- compressed earlier lesson would normally already be overdue. No policy change.
    UPDATE public.lessons SET overdue_at=greatest(overdue_at,current_end+interval '75 minutes') WHERE id=demo_lesson_id;
   ELSIF scenario=3 THEN
    INSERT INTO public.attendance_records(lesson_id,student_id,status,marked_by,marked_at,mutation_id)
     SELECT demo_lesson_id,r.student_id,'present',teacher_id,slot_end,gen_random_uuid()
     FROM public.lesson_roster r WHERE r.lesson_id=demo_lesson_id ON CONFLICT DO NOTHING;
    IF NOT EXISTS(SELECT FROM public.lesson_submissions sub WHERE sub.lesson_id=demo_lesson_id) THEN
     UPDATE public.lessons SET register_revision=register_revision+1 WHERE id=demo_lesson_id;
     INSERT INTO public.lesson_submissions(lesson_id,register_revision,feedback_revision,submitted_by,submitted_at,mutation_id)
      SELECT demo_lesson_id,register_revision,0,teacher_id,slot_end,gen_random_uuid() FROM public.lessons WHERE id=demo_lesson_id;
    ELSE
     UPDATE public.lesson_submissions SET submitted_at=slot_end WHERE public.lesson_submissions.lesson_id=demo_lesson_id;
     UPDATE public.attendance_records SET marked_at=slot_end WHERE public.attendance_records.lesson_id=demo_lesson_id;
    END IF;
   END IF;
  END LOOP;
 END LOOP;
 UPDATE public.demo_seed_state SET anchor_date=today;
 SET CONSTRAINTS validate_lesson_overlap,validate_term IMMEDIATE;
 RETURN jsonb_build_object('anchor_date',today,'shift_days',days);
END $$;
REVOKE ALL ON FUNCTION public.demo_shift_to_today() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.demo_shift_to_today() TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
