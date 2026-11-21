\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
DO $$ DECLARE d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+10; t uuid; c uuid; r uuid; l uuid; st timestamptz; BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Makeup Regression','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Makeup Term',d,d+14) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'19:00',60,d,d+14,'10000000-0000-4000-8000-000000000011') RETURNING id INTO r;
 PERFORM public.generate_lessons(d,d);
 SELECT id,scheduled_start_at INTO l,st FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=d;
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,d,d,'closure','centre_closed');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM public.edit_lesson(l,st+interval '1 day',st+interval '2 hours 1 day');
 RESET ROLE;
 PERFORM public.generate_lessons(d,d+1);
 PERFORM pg_temp.ok((SELECT occurrence_date=d AND scheduled_start_at=st+interval '1 day' AND cancelled_at IS NULL FROM public.lessons WHERE id=l),'calendar makeup survives closed original date regeneration');
 PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.notification_plans WHERE lesson_id=l AND status='pending'),'calendar makeup keeps prompts');
 SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.edit_lesson(%L,%L,%L)',l,st,st+interval '1 hour'),'TP_INVALID_INPUT','calendar moving onto closed date rejected');
 RESET ROLE;
 PERFORM public.generate_lessons(d,d+1);
 PERFORM pg_temp.ok((SELECT scheduled_start_at=st+interval '1 day' AND cancelled_at IS NULL FROM public.lessons WHERE id=l),'calendar rejected move then regeneration preserves makeup');
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,d+1,d+1,'closure','centre_closed');
 PERFORM public.generate_lessons(d,d+1);
 PERFORM pg_temp.ok((SELECT cancellation_reason='centre_closed' FROM public.lessons WHERE id=l),'calendar closure on actual date cancels makeup');
END $$;
-- Moving-window regression: original date is excluded; actual SGT date must be visited.
DO $$ DECLARE d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+10; t uuid; c uuid; r uuid; l uuid; st timestamptz; rev bigint; result jsonb; BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Moving Window','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Moving Term',d,d+70) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'19:00',60,d,d+70,'10000000-0000-4000-8000-000000000011') RETURNING id INTO r;
 PERFORM public.generate_lessons(d,d);
 SELECT id INTO l FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=d;
 st:=(d+1+time '00:30') AT TIME ZONE 'Asia/Singapore';
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM public.edit_lesson(l,st,st+interval '1 hour');
 RESET ROLE;
 INSERT INTO public.enrollments(student_id,class_id,starts_on) SELECT id,c,d+1 FROM public.students ORDER BY id LIMIT 1;
 PERFORM public.generate_lessons(d+1,d+1);
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.lesson_roster WHERE lesson_id=l),'moving window refreshes roster on actual Singapore date');
 PERFORM pg_temp.ok((SELECT occurrence_date=d AND scheduled_start_at=st AND schedule_overridden AND cancelled_at IS NULL FROM public.lessons WHERE id=l),'moving window preserves natural identity and override');
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,d+1,d+1,'closure','centre_closed');
 result:=public.generate_lessons(d+1,d+42);
 PERFORM pg_temp.ok(result->>'cancelled'='1' AND (SELECT cancellation_reason='centre_closed' FROM public.lessons WHERE id=l),'moving window cancels closed destination without original date');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=l AND status='pending'),'moving window cancellation suppresses prompts');
 SELECT plan_revision INTO rev FROM public.lessons WHERE id=l;
 DELETE FROM public.calendar_exceptions WHERE class_id=c;
 PERFORM public.generate_lessons(d+1,d+42);
 PERFORM pg_temp.ok((SELECT cancelled_at IS NOT NULL AND plan_revision=rev FROM public.lessons WHERE id=l),'moving window never resurrects cancelled override');
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.scheduler_tick(st+interval '55 minutes',100) WHERE lesson_id=l),'moving window closed lesson never dispatches');
 RESET ROLE;
END $$;
-- Real refresh entry point: original identity outside today..today+42.
DO $$ DECLARE today date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date; d date:=today+50; t uuid; c uuid; r uuid; l uuid; st timestamptz; BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Refresh Moved','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Refresh Term',today-7,today+70) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'19:00',60,today-7,today+70,'10000000-0000-4000-8000-000000000011') RETURNING id INTO r;
 PERFORM public.generate_lessons(d,d);
 SELECT id INTO l FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=d;
 st:=(today+1+time '00:30') AT TIME ZONE 'Asia/Singapore';
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM public.edit_lesson(l,st,st+interval '1 hour');
 RESET ROLE;
 -- Model time passing after an authorized move; preserve ISO recurrence identity.
 UPDATE public.lessons SET occurrence_date=d-56 WHERE id=l;
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,today+1,today+1,'closure','centre_closed');
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT occurrence_date<today AND cancellation_reason='centre_closed' FROM public.lessons WHERE id=l),'refresh cancels moved lesson whose original date has passed');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=l AND status='pending'),'refresh cannot replan cancelled makeup');
 DELETE FROM public.calendar_exceptions WHERE class_id=c;
 PERFORM public.generate_lessons(d,d);
 SELECT id INTO l FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=d;
 SET LOCAL ROLE authenticated;
 PERFORM public.edit_lesson(l,st+interval '2 hours',st+interval '3 hours');
 RESET ROLE;
 UPDATE public.lessons SET started_at=clock_timestamp() WHERE id=l;
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,today+1,today+1,'closure','centre_closed');
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT cancelled_at IS NULL AND started_at IS NOT NULL FROM public.lessons WHERE id=l),'refresh preserves started moved lesson');
 PERFORM pg_temp.ok(EXISTS(SELECT FROM public.audit_events WHERE lesson_id=l AND event_code='calendar_conflict'),'refresh audits moved work conflict');
 UPDATE public.lessons SET started_at=NULL WHERE id=l;
 UPDATE public.timetable_rules SET active=false WHERE id=r;
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT cancellation_reason='rule_removed' FROM public.lessons WHERE id=l),'refresh retires moved override when its rule is removed');
END $$;
DO $$ DECLARE d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+12; t uuid; c uuid; a uuid; b uuid; BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Batch Regression','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Batch Term',d,d+14) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'19:00',60,d,d+14,'10000000-0000-4000-8000-000000000011') RETURNING id INTO a;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'20:00',60,d,d+14,'10000000-0000-4000-8000-000000000011') RETURNING id INTO b;
 PERFORM public.generate_lessons(d,d);
 UPDATE public.timetable_rules SET local_start=local_start+interval '30 minutes' WHERE id IN (a,b);
 PERFORM public.generate_lessons(d,d);
 PERFORM pg_temp.ok((SELECT array_agg((scheduled_start_at AT TIME ZONE 'Asia/Singapore')::time ORDER BY scheduled_start_at)=ARRAY['19:30','20:30']::time[] FROM public.lessons WHERE class_id=c),'calendar batch final valid shift succeeds');
 UPDATE public.timetable_rules SET local_start='19:45' WHERE id=b;
 PERFORM pg_temp.throws(format('SELECT public.generate_lessons(%L,%L)',d,d),'TP_CONFLICT','calendar genuinely overlapping final batch rejected');
 PERFORM pg_temp.ok((SELECT array_agg((scheduled_start_at AT TIME ZONE 'Asia/Singapore')::time ORDER BY scheduled_start_at)=ARRAY['19:30','20:30']::time[] FROM public.lessons WHERE class_id=c),'calendar rejected batch rolls back all lesson and hook changes');
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok(EXISTS(SELECT FROM public.audit_events WHERE event_code='calendar_generation_failed' AND details='{"reason_code":"generation_failed"}'::jsonb),'calendar failed refresh audited without SQL details');
 -- Existing independent work still dispatches after the bad calendar refresh.
 UPDATE public.notification_plans SET status='cancelled';
 a:=pg_temp.fixture('Demo Dispatch Despite Calendar','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.scheduler_tick('2027-01-07 21:05+08',50) WHERE lesson_id=a),'calendar failure does not block unrelated scheduler tick');
 RESET ROLE;
END $$;
DO $$ DECLARE d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+15; teacher uuid:=gen_random_uuid(); c uuid; t uuid; r uuid; lesson uuid; result jsonb; BEGIN
 INSERT INTO auth.users(id) VALUES(teacher);
 INSERT INTO public.profiles(id,display_name,role) VALUES(teacher,'Demo Lifecycle Teacher','teacher');
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Staffing Regression','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Staffing Term',d,d+14) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id)
 VALUES(c,t,extract(isodow FROM d),'19:00',60,d,d+14,teacher) RETURNING id INTO r;
 UPDATE public.timetable_rules SET active=false WHERE class_id=(SELECT id FROM public.classes WHERE short_label='Demo Batch Regression');
 PERFORM public.generate_lessons(d,d);
 SELECT id INTO lesson FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=d;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM public.assign_lesson_teacher(lesson,'10000000-0000-4000-8000-000000000012',false);
 RESET ROLE;
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons WHERE accountable_teacher_id=teacher),'calendar existing lessons reassigned before default deactivation');
 PERFORM pg_temp.throws(format('UPDATE public.profiles SET active=false WHERE id=%L',teacher),'23514','calendar active default prevents deactivation without retirement');
 PERFORM pg_temp.throws(format('UPDATE public.profiles SET role=''parent'' WHERE id=%L',teacher),'23514','calendar active default prevents role change');
 SET CONSTRAINTS ALL DEFERRED;
 UPDATE public.profiles SET active=false WHERE id=teacher;
 UPDATE public.timetable_rules SET active=false WHERE id=r;
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM pg_temp.ok((SELECT NOT active FROM public.profiles WHERE id=teacher),'calendar atomic deactivation and rule retirement accepted');
 -- Model legacy stale provisioning with only the relevant lifecycle trigger disabled.
 UPDATE public.profiles SET active=true WHERE id=teacher;
 UPDATE public.timetable_rules SET active=true WHERE id=r;
 ALTER TABLE public.profiles DISABLE TRIGGER profile_accountable;
 UPDATE public.profiles SET active=false WHERE id=teacher;
 ALTER TABLE public.profiles ENABLE TRIGGER profile_accountable;
 SET CONSTRAINTS ALL DEFERRED;
 -- Retire the intentionally invalid overlap fixture from the preceding test.
 UPDATE public.timetable_rules SET active=false WHERE class_id=(SELECT id FROM public.classes WHERE short_label='Demo Batch Regression');
 result:=public.generate_lessons(d,d+7);
 PERFORM pg_temp.ok(result->>'staffing_skipped'='1' AND (SELECT count(*)=1 FROM public.lessons WHERE timetable_rule_id=r),'calendar stale inactive rule skipped before insertion');
 PERFORM pg_temp.ok(EXISTS(SELECT FROM public.audit_events WHERE event_code='calendar_staffing_unresolved'),'calendar unresolved staffing flagged for admin');
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons WHERE accountable_teacher_id=teacher),'calendar refresh never inserts inactive lead');
 UPDATE public.timetable_rules SET active=false WHERE id=r;
 SET CONSTRAINTS ALL IMMEDIATE;
END $$;
ROLLBACK;
