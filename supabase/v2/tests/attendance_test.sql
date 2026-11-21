\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
DO $$ DECLARE lid uuid; future uuid; old uuid; cancelled uuid; s1 uuid:='20000000-0000-4000-8000-000000000001'; s2 uuid:='20000000-0000-4000-8000-000000000002'; m uuid:=gen_random_uuid(); result jsonb; ts timestamptz; rev bigint; BEGIN
 lid:=pg_temp.fixture('Demo Attendance',now()-interval '1 hour',now()+interval '1 hour',members=>3);
 future:=pg_temp.fixture('Demo Future Attendance',now()+interval '1 day',now()+interval '1 day 1 hour');
 old:=pg_temp.fixture('Demo Old Attendance',now()-interval '9 days',now()-interval '9 days'+interval '1 hour');
 cancelled:=pg_temp.fixture('Demo Cancel Attendance',now()-interval '1 hour',now()+interval '1 hour');
 UPDATE public.lessons SET cancelled_at=now(),cancellation_reason='manual',plan_revision=plan_revision+1 WHERE id=cancelled;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 result:=public.mark_attendance(lid,s1,'late',NULL,NULL,0,m); ts:=(result->>'marked_at')::timestamptz;
 PERFORM pg_temp.ok(result->>'status'='late' AND result->>'register_revision'='1','attendance late and revision');
 PERFORM pg_temp.ok((public.mark_attendance(lid,s1,'late',NULL,NULL,0,m)->>'replayed')::boolean,'attendance exact replay bypasses stale revision');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''present'',NULL,NULL,0,%L)',lid,s1,m),'TP_MUTATION_REUSED','attendance reused mutation argument denied');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''late'',NULL,NULL,0,%L)',future,s1,m),'TP_MUTATION_REUSED','attendance reused mutation lesson denied');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''present'',NULL,NULL,1,%L)',lid,s1,gen_random_uuid()),'TP_CONFLICT','attendance observed-empty race rejected');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,NULL,NULL,%L,0,%L)',lid,s1,ts,gen_random_uuid()),'TP_CONFLICT','attendance stale clear revision rejected');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''not_here_yet'',NULL,NULL,1,%L)',lid,s2,gen_random_uuid()),'TP_INVALID_INPUT','attendance fourth status rejected');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''present'',true,NULL,1,%L)',lid,s2,gen_random_uuid()),'TP_INVALID_INPUT','attendance companion absent only');
 result:=public.mark_attendance(lid,s2,'absent',true,NULL,1,gen_random_uuid());
 PERFORM pg_temp.ok(result->>'absence_informed'='true' AND result->>'status'='absent','attendance informed absence');
 result:=public.mark_all_present(lid,2,gen_random_uuid());
 PERFORM pg_temp.ok(result->>'changed_count'='1' AND result->>'register_revision'='3','attendance mark all fills only unmarked');
 PERFORM pg_temp.ok((SELECT status='late' FROM public.attendance_records WHERE lesson_id=lid AND student_id=s1) AND (SELECT status='absent' FROM public.attendance_records WHERE lesson_id=lid AND student_id=s2),'attendance mark all preserves explicit marks');
 result:=public.mark_attendance(lid,s1,'present',NULL,ts,3,gen_random_uuid());
 PERFORM pg_temp.ok((result->>'marked_at')::timestamptz>ts,'attendance timestamp strictly increases');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,NULL,NULL,%L,4,%L)',lid,s1,ts,gen_random_uuid()),'TP_CONFLICT','attendance stale observed timestamp rejected');
 result:=public.mark_attendance(lid,s1,NULL,NULL,(result->>'marked_at')::timestamptz,4,gen_random_uuid());
 PERFORM pg_temp.ok(result->'status'='null'::jsonb AND NOT EXISTS(SELECT FROM public.attendance_records WHERE lesson_id=lid AND student_id=s1),'attendance clear removes row');
 PERFORM pg_temp.ok(public.mark_attendance(lid,s1,NULL,NULL,NULL,5,gen_random_uuid())->>'register_revision'='5','attendance empty clear no revision bump');
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,0,%L)',future,gen_random_uuid()),'TP_TOO_EARLY','attendance future blocked');
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,0,%L)',old,gen_random_uuid()),'TP_TOO_OLD','attendance old teacher work blocked');
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,0,%L)',cancelled,gen_random_uuid()),'TP_LOCKED','attendance cancelled blocked');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000012');
 PERFORM pg_temp.throws(format('SELECT public.mark_attendance(%L,%L,''late'',NULL,NULL,0,%L)',lid,s1,m),'TP_NOT_AVAILABLE','attendance foreign actor cannot replay receipt');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001');
 PERFORM pg_temp.ok(public.mark_all_present(old,0,gen_random_uuid())->>'changed_count'='2','attendance admin can complete older work');
 RESET ROLE;
 UPDATE public.feature_flags SET enabled=false WHERE key='teacher_prompts';
 SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,5,%L)',lid,gen_random_uuid()),'TP_DISABLED','attendance flag gate');
 RESET ROLE;
END $$;
UPDATE public.feature_flags SET enabled=true WHERE key='teacher_prompts';
-- Timestamp arguments must hash the same instant across connection time zones.
DO $$ DECLARE l uuid; r jsonb; m uuid:=gen_random_uuid(); ts timestamptz; BEGIN
 l:=pg_temp.fixture('Demo Timestamp Replay',now()-interval '1 hour',now()+interval '1 hour');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 r:=public.mark_attendance(l,'20000000-0000-4000-8000-000000000001','present',NULL,NULL,0,gen_random_uuid()); ts:=(r->>'marked_at')::timestamptz;
 SET LOCAL TIME ZONE 'UTC';
 PERFORM public.mark_attendance(l,'20000000-0000-4000-8000-000000000001','late',NULL,ts,1,m);
 SET LOCAL TIME ZONE 'America/Los_Angeles';
 PERFORM pg_temp.ok((public.mark_attendance(l,'20000000-0000-4000-8000-000000000001','late',NULL,ts,1,m)->>'replayed')::boolean,'attendance replay hash independent of session timezone');
 RESET ROLE;
END $$;
ROLLBACK;
