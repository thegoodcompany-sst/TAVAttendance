\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
DO $$ DECLARE lid uuid; zero uuid; m uuid:=gen_random_uuid(); r jsonb; s uuid:='20000000-0000-4000-8000-000000000001'; BEGIN
 lid:=pg_temp.fixture('Demo Submit',now()-interval '1 hour',now()+interval '1 hour');
 zero:=pg_temp.fixture('Demo Zero',now()-interval '1 hour',now()+interval '1 hour',members=>0);
 UPDATE public.lessons SET started_at=now()-interval '1 hour',ended_at=now()-interval '1 minute' WHERE id=lid;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 PERFORM pg_temp.ok(public.lesson_for_prompt(lid)->'submission'='null'::jsonb,'submission actual ending is not submission');
 PERFORM pg_temp.ok(public.lesson_for_prompt(lid)->'feedback'='{"body":"","revision":"0"}'::jsonb,'submission absent feedback shaped');
 PERFORM pg_temp.throws(format('SELECT public.submit_lesson(%L,0,0,%L)',lid,gen_random_uuid()),'TP_INCOMPLETE','submission incomplete blocked');
 PERFORM pg_temp.throws(format('SELECT public.submit_lesson(%L,0,0,%L)',zero,gen_random_uuid()),'TP_INCOMPLETE','submission zero roster teacher blocked');
 PERFORM pg_temp.throws(format('SELECT public.save_feedback(%L,%L,0,%L)',lid,repeat('x',1001),gen_random_uuid()),'TP_INVALID_INPUT','submission feedback length');
 PERFORM pg_temp.throws(format('SELECT public.save_feedback(%L,''demo s1234567a'',0,%L)',lid,gen_random_uuid()),'TP_INVALID_INPUT','submission NRIC-like feedback blocked');
 r:=public.save_feedback(lid,'  Demo notes  ',0,gen_random_uuid());
 PERFORM pg_temp.ok(r->>'feedback_revision'='1' AND public.lesson_for_prompt(lid)->'feedback'->>'body'='Demo notes','submission feedback trim and revision');
 PERFORM pg_temp.throws(format('SELECT public.save_feedback(%L,''changed'',0,%L)',lid,gen_random_uuid()),'TP_CONFLICT','submission independent feedback CAS');
 PERFORM pg_temp.ok(public.lesson_for_prompt(lid)->'lesson'->>'register_revision'='0','submission feedback does not change register');
 PERFORM public.mark_all_present(lid,0,gen_random_uuid());
 PERFORM pg_temp.throws(format('SELECT public.submit_lesson(%L,1,0,%L)',lid,gen_random_uuid()),'TP_CONFLICT','submission checks feedback revision');
 r:=public.submit_lesson(lid,1,1,m);
 PERFORM pg_temp.ok(r->>'submission_id' IS NOT NULL,'submission explicit success before scheduled end');
 PERFORM pg_temp.ok((public.submit_lesson(lid,1,1,m)->>'replayed')::boolean,'submission replay after locked state');
 PERFORM pg_temp.ok(public.lesson_for_prompt(lid)->'lesson'->>'state'='submitted','submission derived state');
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,1,%L)',lid,gen_random_uuid()),'TP_LOCKED','submission attendance immutable');
 PERFORM pg_temp.throws(format('SELECT public.save_feedback(%L,''changed'',1,%L)',lid,gen_random_uuid()),'TP_LOCKED','submission feedback immutable');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001');
 PERFORM pg_temp.throws(format('SELECT public.mark_all_present(%L,1,%L)',lid,gen_random_uuid()),'TP_LOCKED','submission admin cannot silently correct');
 PERFORM pg_temp.throws(format('SELECT public.cancel_lesson(%L)',lid),'TP_LOCKED','submission admin cancellation blocked');
 PERFORM pg_temp.ok(public.submit_lesson(zero,0,0,gen_random_uuid())->>'submission_id' IS NOT NULL,'submission admin zero roster optional feedback');
 RESET ROLE;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=lid AND status='pending'),'submission plans atomically stopped');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.audit_events WHERE details::text LIKE '%Demo notes%') AND NOT EXISTS(SELECT FROM public.mutation_receipts WHERE result::text LIKE '%Demo notes%'),'submission no notes in receipts or audit');
END $$;
ROLLBACK;
