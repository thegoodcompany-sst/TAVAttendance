\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
SELECT pg_temp.ok((SELECT count(*)=30 AND bool_and(display_name ~ '^Demo Student [0-9]{2}$') FROM public.students),'demo thirty fake students');
SELECT pg_temp.ok((SELECT count(*)=4 FROM public.classes),'demo four classes');
SELECT pg_temp.ok((SELECT bool_and(NOT enabled) FROM public.feature_flags WHERE key='teacher_prompt_push'),'demo real push remains OFF');
SELECT pg_temp.ok((SELECT cancelled_at IS NOT NULL FROM public.lessons WHERE occurrence_date='2027-01-01'),'demo canonical holiday');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.lesson_submissions),'demo canonical submitted science');
SELECT pg_temp.ok((SELECT accountable_teacher_id='10000000-0000-4000-8000-000000000014' AND snooze_count=1 AND snoozed_until='2027-01-07 21:10+08' FROM public.lessons WHERE occurrence_date='2027-01-07'),'demo canonical substitute and overrun');
SET LOCAL ROLE authenticated;
SELECT pg_temp.claims('10000000-0000-4000-8000-000000000001');
SELECT pg_temp.ok(public.lesson_state((SELECT id FROM public.lessons WHERE occurrence_date='2027-01-04'),'2027-01-07 21:05+08')='overdue','demo canonical English overdue');
SELECT pg_temp.throws($$SELECT public.demo_shift_to_today()$$,'42501','demo shift never client callable');
RESET ROLE;
SAVEPOINT canonical_demo;
DO $$ DECLARE before_count int; r jsonb; n date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date; lid uuid; m uuid:=gen_random_uuid(); snapshot jsonb; BEGIN
 SELECT count(*) INTO before_count FROM public.lessons;
 SET LOCAL TIME ZONE 'America/Los_Angeles';
 r:=public.demo_shift_to_today();
 PERFORM pg_temp.ok(r->>'anchor_date'=n::text AND (r->>'shift_days')::int=n-date '2027-01-07','demo shift uses Singapore date');
 SELECT jsonb_agg(to_jsonb(l) ORDER BY id) INTO snapshot FROM public.lessons l;
 r:=public.demo_shift_to_today();
 PERFORM pg_temp.ok(r->>'shift_days'='0' AND snapshot=(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.lessons l),'demo shift same-day exact no-op');
 PERFORM pg_temp.ok((SELECT count(*)=before_count+11 FROM public.lessons),'demo shift retains lessons and adds eleven examples');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons WHERE occurrence_date<>(scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date),'demo shifted occurrence dates align');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons l JOIN public.timetable_rules r ON r.id=l.timetable_rule_id WHERE extract(isodow FROM l.occurrence_date)<>r.iso_weekday),'demo shifted rules weekday matches');
 PERFORM pg_temp.ok((SELECT starts_on=n-6 FROM public.calendar_exceptions),'demo shifted closure is relative fixture');
 PERFORM pg_temp.ok((SELECT (submitted_at AT TIME ZONE 'Asia/Singapore')::date=n-5 FROM public.lesson_submissions WHERE lesson_id NOT IN (SELECT id FROM public.lessons WHERE id::text LIKE 'a0000000-%')),'demo shifted submission timestamp');
 SELECT id INTO lid FROM public.lessons WHERE occurrence_date=n AND class_id='30000000-0000-4000-8000-000000000002';
 PERFORM pg_temp.ok(lid IS NOT NULL,'demo today Math exists');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001');
 PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.profiles p WHERE p.role='teacher' AND
  EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=n
   AND public.lesson_state(l.id,clock_timestamp())='in_progress') AND
  EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=n
   AND public.lesson_state(l.id,clock_timestamp())='awaiting_attendance') AND
  EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=n
   AND public.lesson_state(l.id,clock_timestamp())='submitted')),'demo every teacher has current pending and submitted lessons');
 PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.lessons WHERE occurrence_date=n AND
  scheduled_end_at>clock_timestamp() AND scheduled_end_at<=clock_timestamp()+interval '5 minutes'
  AND scheduled_start_at<=clock_timestamp()),'demo four lessons end within five minutes');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons a JOIN public.lessons b ON a.class_id=b.class_id AND a.id<b.id
  WHERE a.cancelled_at IS NULL AND b.cancelled_at IS NULL AND
  tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)') && tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')),'demo no class overlaps');

 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000014'); SET LOCAL ROLE authenticated;
 r:=public.simulate_prompt_now(lid,m);
 PERFORM pg_temp.ok(r->>'transport'='dry_run' AND r->>'path'='/t/lesson/'||lid AND r->>'kind'='attendance','demo simulation safe route response');
 PERFORM pg_temp.ok((public.simulate_prompt_now(lid,m)->>'replayed')::boolean,'demo simulation idempotent');
 PERFORM pg_temp.throws(format('SELECT public.simulate_prompt_now(%L,%L)',lid,gen_random_uuid()),'TP_CONFLICT','demo simulation rate limit');
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.notification_deliveries WHERE transport='dry_run' AND outcome='accepted'),'demo simulation dry-run delivery log');
 PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.notification_plans WHERE lesson_id=lid AND kind<>'simulation' AND status='pending'),'demo simulation leaves normal plan untouched');
 SET LOCAL ROLE service_role;
 PERFORM public.refresh_prompt_schedule();
 RESET ROLE;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_outbox WHERE status='claimed'),'demo refresh plans without claiming deliveries');
 PERFORM pg_temp.ok((SELECT count(*)>before_count FROM public.lessons),'demo refresh generates full rolling horizon');
 UPDATE public.runtime_settings SET demo_enabled=false;
 SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.simulate_prompt_now(%L,%L)',lid,gen_random_uuid()),'TP_NOT_AVAILABLE','demo simulation disabled outside demo');
 RESET ROLE;
 PERFORM pg_temp.throws($q$SELECT public.demo_shift_to_today()$q$,'TP_NOT_AVAILABLE','demo shifting disabled outside demo');
END $$;
ROLLBACK TO canonical_demo;
-- Exercise the real demo function at boundary clocks, inside rolled-back owner
-- fixtures. No application RPC gains a caller-supplied clock.
DO $$
DECLARE fake_now timestamptz; original text:=pg_get_functiondef('public.demo_shift_to_today()'::regprocedure); today date;
BEGIN
 FOR fake_now IN SELECT unnest(ARRAY[timestamptz '2027-01-07 00:00:01+08',
  timestamptz '2026-11-15 00:04:59+08',timestamptz '2026-11-15 13:22:00+08',
  timestamptz '2026-11-15 23:59:59+08']) LOOP
  BEGIN
   today:=(fake_now AT TIME ZONE 'Asia/Singapore')::date;
   EXECUTE replace(original,'demo_now timestamptz:=clock_timestamp()',
    'demo_now timestamptz:='||quote_literal(fake_now)||'::timestamptz');
   PERFORM public.demo_shift_to_today();
   PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001');
   PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.profiles p WHERE p.role='teacher' AND
    EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=today AND public.lesson_state(l.id,fake_now)='in_progress') AND
    EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=today AND public.lesson_state(l.id,fake_now)='awaiting_attendance') AND
    EXISTS(SELECT FROM public.lessons l WHERE l.accountable_teacher_id=p.id AND l.occurrence_date=today AND public.lesson_state(l.id,fake_now)='submitted')),
    'demo boundary clock gives each teacher three states');
   PERFORM pg_temp.ok((SELECT count(*)=4 FROM public.lessons WHERE occurrence_date=today
    AND scheduled_start_at<=fake_now AND scheduled_end_at>fake_now AND scheduled_end_at<=fake_now+interval '5 minutes'
    AND (scheduled_end_at AT TIME ZONE 'Asia/Singapore')::date=today),
    'demo boundary current lessons stay today and end within five minutes');
   PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.lessons WHERE occurrence_date<>(scheduled_start_at AT TIME ZONE 'Asia/Singapore')::date
    OR scheduled_end_at<=scheduled_start_at),'demo boundary dates and positive durations');
   PERFORM pg_temp.ok((fake_now AT TIME ZONE 'Asia/Singapore')::time<time '03:00' OR (SELECT count(*)=4 FROM public.lessons WHERE occurrence_date=today
    AND scheduled_start_at<=fake_now AND scheduled_end_at>fake_now
    AND fake_now-scheduled_start_at BETWEEN interval '115 minutes' AND interval '120 minutes'),
    'demo ordinary hours began about one hour fifty-five minutes ago');
   RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='rollback demo clock fixture';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
  END;
 END LOOP;
END $$;
ROLLBACK;
