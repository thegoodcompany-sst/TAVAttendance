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
DECLARE anchor date; today date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date; days int; delta interval; l record;
BEGIN
 IF NOT EXISTS(SELECT FROM public.runtime_settings WHERE demo_enabled) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 SELECT anchor_date INTO STRICT anchor FROM public.demo_seed_state WHERE id FOR UPDATE;
 days:=today-anchor; delta:=days*interval '24 hours';
 IF days=0 THEN RETURN jsonb_build_object('anchor_date',today,'shift_days',0); END IF;
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
 UPDATE public.demo_seed_state SET anchor_date=today;
 SET CONSTRAINTS validate_lesson_overlap,validate_term IMMEDIATE;
 RETURN jsonb_build_object('anchor_date',today,'shift_days',days);
END $$;
REVOKE ALL ON FUNCTION public.demo_shift_to_today() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.demo_shift_to_today() TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
