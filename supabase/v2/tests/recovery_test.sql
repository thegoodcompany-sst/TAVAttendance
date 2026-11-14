\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
UPDATE public.notification_plans SET status='cancelled';
DO $$ DECLARE l uuid; c record; deadline timestamptz; BEGIN
 l:=pg_temp.fixture('Demo Recovery History','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SELECT overdue_at INTO deadline FROM public.lessons WHERE id=l;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick('2027-01-07 20:59+08',50) WHERE lesson_id=l;
 PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,'2027-01-07 20:59+08');
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,'2027-01-07 21:00+08') IS NULL,'recovery prepare never sends heads-up at lesson end');
 PERFORM pg_temp.ok((SELECT status='superseded' AND lease_token IS NULL FROM public.notification_outbox WHERE id=c.outbox_id),'recovery superseded claimed outbox retained');
 PERFORM pg_temp.ok((SELECT outcome='unknown' FROM public.notification_deliveries WHERE outbox_id=c.outbox_id),'recovery in-flight uncertainty retained');
 PERFORM pg_temp.ok(NOT public.mark_prompt_sent(c.outbox_id,c.lease_token,c.outbox_id,'dry_run','2027-01-07 21:00+08'),'recovery superseded lease cannot acknowledge');
 SELECT * INTO c FROM public.scheduler_tick('2027-01-08 10:00+08',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c.kind='final' AND c.attempt_no=1,'recovery next day selects only final');
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM public.notification_plans WHERE lesson_id=l AND status='superseded'),'recovery retains three superseded stages');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick('2027-01-08 10:00+08',50)),'recovery repeated tick cannot burst');
 PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,'2027-01-08 10:00+08');
 PERFORM public.mark_prompt_sent(c.outbox_id,c.lease_token,c.outbox_id,'dry_run','2027-01-08 10:00+08');
 RESET ROLE;
 UPDATE public.lessons SET plan_revision=plan_revision+1 WHERE id=l;
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM public.notification_plans WHERE lesson_id=l AND status='superseded'),'recovery replan never resurrects superseded stages');
 PERFORM pg_temp.ok((SELECT overdue_at=deadline FROM public.lessons WHERE id=l),'recovery preserves admin deadline');
END $$;
DO $$ DECLARE l uuid; boundary uuid; future uuid; n timestamptz:='2027-01-15 12:00+08'; c record; BEGIN
 l:=pg_temp.fixture('Demo Recovery Old','2027-01-05 10:00+08','2027-01-05 12:00+08');
 boundary:=pg_temp.fixture('Demo Recovery Seven Dates','2027-01-08 10:00+08','2027-01-08 12:00+08');
 future:=pg_temp.fixture('Demo Recovery Before Start','2027-01-15 13:00+08','2027-01-15 14:00+08');
 UPDATE public.notification_plans SET due_at=n WHERE lesson_id=future;
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n,50) WHERE lesson_id IN (l,future)),'recovery no claims before start or after teacher window');
 PERFORM pg_temp.ok((SELECT o.status='claimed' FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=boundary),'recovery exactly seven Singapore dates still eligible');
 SELECT o.id AS outbox_id,o.lease_token INTO c FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=boundary;
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n) IS NOT NULL,'recovery seven-date claim prepares');
 PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.notification_plans WHERE lesson_id=future AND status='pending'),'recovery before-start plans retained for later teacher window');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.scheduler_tick('2027-01-15 13:00+08',50) WHERE lesson_id=future),'recovery retained future work dispatches after start');
 RESET ROLE; PERFORM public.cancel_prompt_work(boundary,'test');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l),'recovery old lesson never materializes push');
 l:=pg_temp.fixture('Demo Admin Only Old',clock_timestamp()-interval '10 days',clock_timestamp()-interval '10 days'+interval '1 hour');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM pg_temp.ok(public.admin_missing_submissions((clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date-11,(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date)->'lessons' @> jsonb_build_array(jsonb_build_object('lesson_id',l)),'recovery old work stays in admin follow-up');
 RESET ROLE;
END $$;
-- Eligibility changes at Singapore midnight, even with an unexpired lease.
DO $$ DECLARE l uuid; c record; BEGIN
 l:=pg_temp.fixture('Demo Recovery Midnight','2027-01-01 19:00+08','2027-01-01 21:00+08');
 -- Test just the window recheck outside quiet hours using a shorter test quiet interval.
 UPDATE public.prompt_policy SET quiet_start='23:59:59',quiet_end='00:00',quiet_resume='09:00';
 UPDATE public.notification_plans SET status='cancelled' WHERE lesson_id<>l;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick('2027-01-08 23:59:30+08',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c.outbox_id IS NOT NULL,'recovery last eligible date can claim');
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,'2027-01-09 00:00:01+08') IS NULL,'recovery prepare rejects next Singapore date beyond window');
 RESET ROLE;
END $$;
ROLLBACK;
