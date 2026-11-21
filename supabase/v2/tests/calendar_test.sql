\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
SELECT pg_temp.ok((SELECT count(*)=25 FROM public.lessons),'calendar six weeks plus final Friday generated');
SELECT pg_temp.ok((SELECT cancelled_at IS NOT NULL AND cancellation_reason='public_holiday' FROM public.lessons WHERE occurrence_date='2027-01-01'),'calendar public holiday explanatory occurrence');
SELECT pg_temp.ok((public.generate_lessons('2027-01-01','2027-02-12')->>'created')::int=0,'calendar double generation no duplicates');
SELECT pg_temp.throws($$SELECT public.generate_lessons('2027-01-01','2027-04-04')$$,'TP_INVALID_INPUT','calendar bounded range');
SELECT pg_temp.throws($$UPDATE public.timetable_rules SET effective_from='2026-12-31'$$,'23514','calendar rule within term');
SELECT pg_temp.throws($$INSERT INTO public.enrollments(student_id,class_id,starts_on) VALUES('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','2027-01-02')$$,'23514','calendar inclusive enrollment overlap');
DO $$ DECLARE lid uuid; l public.lessons; r jsonb; cid uuid; rule uuid; dt date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+20; BEGIN
 lid:=pg_temp.fixture('Demo Calendar', (dt+time '10:00') AT TIME ZONE 'Asia/Singapore',(dt+time '12:00') AT TIME ZONE 'Asia/Singapore');
 SELECT * INTO l FROM public.lessons WHERE id=lid;
 PERFORM pg_temp.throws(format('INSERT INTO public.lessons(class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at) VALUES(%L,%L,%L,%L,%L,%L)',l.class_id,dt,l.scheduled_start_at+interval '1 hour',l.scheduled_end_at+interval '1 hour',l.accountable_teacher_id,l.overdue_at),'TP_CONFLICT','calendar same class overlap rejected');
 INSERT INTO public.lessons(class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at) VALUES(l.class_id,dt,l.scheduled_end_at,l.scheduled_end_at+interval '1 hour',l.accountable_teacher_id,l.overdue_at) RETURNING id INTO cid;
 INSERT INTO public.lesson_staff VALUES(cid,l.accountable_teacher_id,'regular');
 PERFORM pg_temp.ok((SELECT count(*)=2 FROM public.lessons WHERE class_id=l.class_id),'calendar two nonoverlapping same day lessons');
 -- Enrollment begins on the NEW date, not original occurrence.
 INSERT INTO public.enrollments(student_id,class_id,starts_on) VALUES('20000000-0000-4000-8000-000000000003',l.class_id,dt+1);
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 r:=public.edit_lesson(lid,l.scheduled_start_at+interval '1 day',l.scheduled_end_at+interval '1 day');
 PERFORM pg_temp.ok((r->>'lesson_id')::uuid=lid AND (r->>'roster_count')::int=1 AND (r->>'register_revision')::int=1,'calendar reschedule preserves UUID refreshes roster');
 r:=public.assign_lesson_teacher(lid,'10000000-0000-4000-8000-000000000014',false);
 PERFORM pg_temp.ok(r->>'accountable_teacher_id'='10000000-0000-4000-8000-000000000014','calendar substitute replaces accountable');
 r:=public.cancel_lesson(lid); PERFORM pg_temp.ok(r->>'state'='cancelled','calendar admin cancellation');
 PERFORM pg_temp.ok(public.cancel_lesson(lid)->>'state'='cancelled','calendar repeated cancel idempotent');
 PERFORM pg_temp.throws(format('SELECT public.edit_lesson(%L,now()+interval ''1 day'',now()+interval ''2 days'')',lid),'TP_LOCKED','calendar cancelled edits locked');
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT occurrence_date=dt AND schedule_overridden AND staffing_overridden FROM public.lessons WHERE id=lid),'calendar original identity and overrides retained');
END $$;
-- Future generated lessons: changed rules, closures, removed rules, and manual overrides.
DO $$ DECLARE dt date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date+30; t uuid; c uuid; r uuid; l uuid; old_start timestamptz; BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES('Demo Rule Tests','Demo') RETURNING id INTO c;
 INSERT INTO public.terms(label,starts_on,ends_on) VALUES('Demo Future',dt,dt+30) RETURNING id INTO t;
 INSERT INTO public.timetable_rules(class_id,term_id,iso_weekday,local_start,duration_minutes,effective_from,effective_until,default_teacher_id) VALUES(c,t,extract(isodow FROM dt),'10:00',60,dt,dt+14,'10000000-0000-4000-8000-000000000011') RETURNING id INTO r;
 PERFORM public.generate_lessons(dt,dt+30);
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM public.lessons WHERE class_id=c),'calendar effective inclusive boundaries');
 SELECT id,scheduled_start_at INTO l,old_start FROM public.lessons WHERE timetable_rule_id=r AND occurrence_date=dt;
 UPDATE public.lessons SET schedule_overridden=true,scheduled_start_at=scheduled_start_at+interval '2 hours',scheduled_end_at=scheduled_end_at+interval '2 hours',plan_revision=plan_revision+1 WHERE id=l;
 UPDATE public.timetable_rules SET local_start='09:00' WHERE id=r;
 PERFORM public.generate_lessons(dt,dt+30);
 PERFORM pg_temp.ok((SELECT scheduled_start_at=old_start+interval '2 hours' FROM public.lessons WHERE id=l),'calendar regeneration preserves explicit override');
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES(c,dt,dt,'closure','centre_closed');
 PERFORM public.generate_lessons(dt,dt+30);
 PERFORM pg_temp.ok((SELECT cancellation_reason='centre_closed' FROM public.lessons WHERE id=l),'calendar new closure cancels future');
 DELETE FROM public.calendar_exceptions WHERE class_id=c;
 PERFORM public.generate_lessons(dt,dt+30);
 PERFORM pg_temp.ok((SELECT cancelled_at IS NOT NULL FROM public.lessons WHERE id=l),'calendar removed closure never resurrects');
 UPDATE public.timetable_rules SET active=false WHERE id=r;
 PERFORM public.generate_lessons(dt,dt+30);
 PERFORM pg_temp.ok((SELECT bool_and(cancelled_at IS NOT NULL) FROM public.lessons WHERE class_id=c),'calendar removed rule cancels future');
END $$;
DO $$ DECLARE l uuid; rev bigint; scheduled timestamptz; lead uuid; r jsonb; BEGIN
 SELECT id,register_revision,scheduled_start_at,accountable_teacher_id INTO l,rev,scheduled,lead FROM public.lessons WHERE occurrence_date='2027-01-07';
 UPDATE public.timetable_rules SET local_start='18:00',default_teacher_id='10000000-0000-4000-8000-000000000013' WHERE id='50000000-0000-4000-8000-000000000002';
 INSERT INTO public.calendar_exceptions(class_id,starts_on,ends_on,kind,reason_code) VALUES('30000000-0000-4000-8000-000000000002','2027-01-07','2027-01-07','closure','centre_closed');
 PERFORM public.generate_lessons('2027-01-07','2027-01-07');
 PERFORM pg_temp.ok((SELECT register_revision=rev AND scheduled_start_at=scheduled AND accountable_teacher_id=lead AND cancelled_at IS NULL FROM public.lessons WHERE id=l),'calendar worked lesson never silently rewritten or cancelled');
 PERFORM pg_temp.ok(EXISTS(SELECT FROM public.audit_events WHERE lesson_id=l AND event_code='calendar_conflict'),'calendar worked conflict audited');
 PERFORM pg_temp.ok((SELECT count(*)=6 FROM public.attendance_records WHERE lesson_id=l) AND EXISTS(SELECT FROM public.lesson_feedback WHERE lesson_id=l),'calendar regeneration retains attendance and feedback');
END $$;
ROLLBACK;
