\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
UPDATE public.notification_plans SET status='cancelled';
DO $$ DECLARE tz text; v record; BEGIN
 FOREACH tz IN ARRAY ARRAY['Asia/Singapore','UTC','America/Los_Angeles'] LOOP
  PERFORM set_config('TimeZone',tz,true);
  FOR v IN SELECT * FROM (VALUES
   ('2027-01-07 06:59+08'::timestamptz,'2027-01-07 09:00+08'::timestamptz),
   ('2027-01-07 07:00+08'::timestamptz,'2027-01-07 07:00+08'::timestamptz),
   ('2027-01-07 21:59+08'::timestamptz,'2027-01-07 21:59+08'::timestamptz),
   ('2027-01-07 22:00+08'::timestamptz,'2027-01-08 09:00+08'::timestamptz),
   ('2027-01-07 23:59+08'::timestamptz,'2027-01-08 09:00+08'::timestamptz),
   ('2027-01-07 16:01Z'::timestamptz,'2027-01-08 09:00+08'::timestamptz)) x(at,expected) LOOP
   PERFORM pg_temp.ok(public.defer_quiet(v.at)=v.expected,'scheduler quiet boundary '||tz||' '||v.at::text);
  END LOOP;
 END LOOP;
END $$;
DO $$ DECLARE a uuid; b uuid; rev bigint; times timestamptz[]; BEGIN
 a:=pg_temp.fixture('Demo Scheduler Defaults','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SELECT array_agg(due_at ORDER BY due_at) INTO times FROM public.notification_plans WHERE lesson_id=a;
 PERFORM pg_temp.ok(times=ARRAY['2027-01-07 20:55+08','2027-01-07 21:00+08','2027-01-07 21:15+08','2027-01-08 09:00+08']::timestamptz[],'scheduler all defaults and deferred final');
 PERFORM pg_temp.ok((SELECT overdue_at='2027-01-08 09:15+08' FROM public.lessons WHERE id=a),'scheduler overdue follows effective final');
 PERFORM pg_temp.ok(public.plan_prompts(a)->>'planned'='0' AND (SELECT array_agg(due_at ORDER BY due_at)=times FROM public.notification_plans WHERE lesson_id=a),'scheduler unchanged plan strict no-op');
 b:=pg_temp.fixture('Demo Scheduler Quiet Stages','2027-01-07 22:00+08','2027-01-07 23:00+08');
 PERFORM pg_temp.ok((SELECT array_agg(due_at ORDER BY due_at)=ARRAY['2027-01-08 09:00+08','2027-01-08 09:05+08','2027-01-08 09:10+08','2027-01-08 09:15+08']::timestamptz[] FROM public.notification_plans WHERE lesson_id=b),'scheduler all deferred stages spaced');
 UPDATE public.prompt_policy SET final_minutes=90;
 PERFORM pg_temp.ok((SELECT plan_revision=2 FROM public.lessons WHERE id=a),'scheduler policy replan atomic revision');
 UPDATE public.prompt_policy SET final_minutes=60;
 PERFORM public.cancel_prompt_work(a,'test'); PERFORM public.cancel_prompt_work(b,'test');
END $$;
-- Cancel seed plans that policy updates intentionally replanned.
UPDATE public.notification_plans SET status='cancelled';
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 21:00+08'; c record; c2 record; delivery jsonb; deadline timestamptz; total int; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Leases','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SELECT overdue_at INTO deadline FROM public.lessons WHERE id=l;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c.attempt_no=1 AND c.kind='attendance' AND c.lease_until=n+interval '120 seconds','scheduler first claim shape');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n,50)),'scheduler double tick does not duplicate');
 delivery:=public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n);
 PERFORM pg_temp.ok(delivery->>'mode'='dry_run' AND delivery->>'collapse_id'='tp:'||l AND (delivery->>'expires_at')::timestamptz='2027-01-07 21:15+08','scheduler prepared bounded dry-run input');
 PERFORM pg_temp.ok(public.mark_prompt_failed(c.outbox_id,c.lease_token,'timeout',true,false,n),'scheduler retry first attempt');
 PERFORM pg_temp.ok((SELECT available_at=n+interval '1 minute' AND status='pending' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler first retry one minute');
 SELECT * INTO c2 FROM public.scheduler_tick(n+interval '1 minute',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c2.outbox_id=c.outbox_id AND c2.attempt_no=2 AND c2.lease_token<>c.lease_token,'scheduler stable outbox fresh retry lease');
 PERFORM pg_temp.ok(NOT public.mark_prompt_sent(c.outbox_id,c.lease_token,c.outbox_id,'dry_run',n+interval '1 minute'),'scheduler stale acknowledgement false');
 PERFORM public.prepare_prompt_delivery(c2.outbox_id,c2.lease_token,n+interval '1 minute');
 PERFORM public.mark_prompt_failed(c2.outbox_id,c2.lease_token,'server_error',true,false,n+interval '1 minute');
 PERFORM pg_temp.ok((SELECT available_at=n+interval '6 minutes' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler second retry five minutes');
 SELECT * INTO c2 FROM public.scheduler_tick(n+interval '6 minutes',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c2.attempt_no=3,'scheduler third bounded attempt');
 PERFORM public.prepare_prompt_delivery(c2.outbox_id,c2.lease_token,n+interval '6 minutes');
 PERFORM public.mark_prompt_failed(c2.outbox_id,c2.lease_token,'secret-response-must-not-log',true,false,n+interval '6 minutes');
 PERFORM pg_temp.ok((SELECT status='failed' AND last_error_code='provider_error' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler third failure terminal sanitized');
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM public.notification_deliveries WHERE outbox_id=c.outbox_id),'scheduler exactly three attempt logs');
 PERFORM pg_temp.ok((SELECT overdue_at=deadline FROM public.lessons WHERE id=l),'scheduler retry never moves overdue');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 20:55+08'; c record; c2 record; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Expiry','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 SELECT * INTO c2 FROM public.scheduler_tick(n+interval '121 seconds',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c2.attempt_no=2 AND c2.lease_token<>c.lease_token,'scheduler expired lease reclaimed');
 PERFORM pg_temp.ok((SELECT outcome='unknown' FROM public.notification_deliveries WHERE outbox_id=c.outbox_id AND attempt_no=1),'scheduler expired outcome unknown');
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n+interval '121 seconds') IS NULL,'scheduler stale prepare suppressed');
 PERFORM public.prepare_prompt_delivery(c2.outbox_id,c2.lease_token,n+interval '121 seconds');
 PERFORM pg_temp.ok(public.mark_prompt_sent(c2.outbox_id,c2.lease_token,c2.outbox_id,'dry_run',n+interval '122 seconds'),'scheduler accepted current lease');
 PERFORM pg_temp.ok((SELECT status='completed' FROM public.notification_plans WHERE id=c.plan_id),'scheduler terminal stage completed');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n+interval '123 seconds',50)),'scheduler accepted row never retried');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 21:59:30+08'; c record; c2 record; deadline timestamptz; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Quiet Prepare','2027-01-07 20:00+08','2027-01-07 21:50+08');
 SELECT overdue_at INTO deadline FROM public.lessons WHERE id=l;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c.outbox_id IS NOT NULL,'scheduler before quiet claim');
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,'2027-01-07 22:00+08') IS NULL,'scheduler quiet starts between claim and prepare');
 PERFORM pg_temp.ok((SELECT status='pending' AND attempt_count=0 AND lease_token IS NULL AND available_at='2027-01-08 09:00+08' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler unused attempt refunded and deferred');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_deliveries WHERE outbox_id=c.outbox_id),'scheduler unused attempt not logged');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick('2027-01-07 22:01+08',50)),'scheduler quiet retry never claims');
 SELECT * INTO c2 FROM public.scheduler_tick('2027-01-08 09:00+08',50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c2.kind='follow_up' AND c2.attempt_no=1 AND (SELECT status='superseded' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler quiet recovery coalesces to meaningful stage');
 PERFORM pg_temp.ok((SELECT overdue_at=deadline FROM public.lessons WHERE id=l),'scheduler quiet worker delay keeps deadline');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-08 10:00+08'; c record; deadline timestamptz; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Delayed','2027-01-07 18:00+08','2027-01-07 20:00+08');
 SELECT overdue_at INTO deadline FROM public.lessons WHERE id=l;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.notification_outbox WHERE plan_id IN (SELECT id FROM public.notification_plans WHERE lesson_id=l)),'scheduler delayed tick materializes only one stage');
 PERFORM pg_temp.ok(c.kind='final' AND (SELECT count(*)=3 FROM public.notification_plans WHERE lesson_id=l AND status='superseded'),'scheduler delayed stages superseded without burst');
 PERFORM pg_temp.ok((SELECT overdue_at=deadline FROM public.lessons WHERE id=l),'scheduler delayed stages do not extend overdue');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 20:55+08'; total int; BEGIN
 l:=pg_temp.fixture('Demo Scheduler No Devices','2027-01-07 19:00+08','2027-01-07 21:00+08');
 UPDATE public.teacher_devices SET revoked_at=n WHERE user_id='10000000-0000-4000-8000-000000000011';
 SET LOCAL ROLE service_role;
 PERFORM public.scheduler_tick(n,50);
 PERFORM public.scheduler_tick(n,50);
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l AND o.device_id IS NULL AND o.status='failed'),'scheduler no devices single terminal row');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.notification_deliveries d JOIN public.notification_outbox o ON o.id=d.outbox_id JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l AND d.outcome='no_devices' AND d.transport='none'),'scheduler no devices once-only evidence');
 RESET ROLE;
 UPDATE public.teacher_devices SET revoked_at=NULL WHERE user_id='10000000-0000-4000-8000-000000000011';
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.scheduler_tick(n+interval '5 minutes',50) WHERE lesson_id=l AND kind='attendance'),'scheduler next stage uses newly available device');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 20:55+08'; c record; c2 record; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Reassign','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 RESET ROLE;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM public.assign_lesson_teacher(l,'10000000-0000-4000-8000-000000000014',false);
 RESET ROLE; SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n) IS NULL,'scheduler substitute suppresses stale claim');
 SELECT * INTO c2 FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c2.recipient_id='10000000-0000-4000-8000-000000000014' AND c2.plan_revision<>c.plan_revision,'scheduler pending stage follows new substitute');
 RESET ROLE; SET LOCAL ROLE authenticated;
 PERFORM public.cancel_lesson(l);
 RESET ROLE; SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c2.outbox_id,c2.lease_token,n) IS NULL,'scheduler cancellation suppresses stale claim');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l AND o.status IN ('pending','claimed')),'scheduler cancellation clears every device lease');
 RESET ROLE;
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 20:55+08'; c record; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Flags','2027-01-07 19:00+08','2027-01-07 21:00+08');
 UPDATE public.feature_flags SET enabled=false WHERE key='teacher_prompts';
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n,50)),'scheduler main flag OFF');
 RESET ROLE;
 UPDATE public.feature_flags SET enabled=true WHERE key='teacher_prompts';
 UPDATE public.runtime_settings SET demo_enabled=false;
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n,50)),'scheduler non-demo push flag OFF');
 RESET ROLE;
 UPDATE public.runtime_settings SET demo_enabled=true;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM pg_temp.ok(c.outbox_id IS NOT NULL,'scheduler demo dry-run with push flag OFF');
 RESET ROLE;
 UPDATE public.feature_flags SET enabled=false WHERE key='teacher_prompts';
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok(public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n) IS NULL,'scheduler prepare rechecks flag');
 RESET ROLE;
 UPDATE public.feature_flags SET enabled=true WHERE key='teacher_prompts';
 PERFORM public.cancel_prompt_work(l,'test');
END $$;
-- User snooze uses the server clock, never a supplied client clock.
DO $$ DECLARE l uuid; m uuid:=gen_random_uuid(); r jsonb; snoozed timestamptz; start_at timestamptz; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Snooze',clock_timestamp()-interval '2 hours',clock_timestamp());
 SELECT scheduled_start_at INTO start_at FROM public.lessons WHERE id=l;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 r:=public.snooze_prompt(l,10,m); snoozed:=(r->>'snoozed_until')::timestamptz;
 PERFORM pg_temp.ok(snoozed BETWEEN clock_timestamp()+interval '9 minutes 59 seconds' AND clock_timestamp()+interval '10 minutes 1 second','scheduler snooze ten minutes');
 PERFORM pg_temp.ok((public.snooze_prompt(l,10,m)->>'replayed')::boolean,'scheduler snooze exact replay');
 PERFORM pg_temp.throws(format('SELECT public.snooze_prompt(%L,20,%L)',l,gen_random_uuid()),'TP_INVALID_INPUT','scheduler only ten minute snooze');
 PERFORM public.snooze_prompt(l,10,gen_random_uuid()); PERFORM public.snooze_prompt(l,10,gen_random_uuid());
 PERFORM pg_temp.throws(format('SELECT public.snooze_prompt(%L,10,%L)',l,gen_random_uuid()),'TP_SNOOZE_LIMIT','scheduler at most three snoozes');
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT snooze_count=3 AND scheduled_start_at=start_at FROM public.lessons WHERE id=l) AND NOT EXISTS(SELECT FROM public.attendance_records WHERE lesson_id=l),'scheduler snooze preserves attendance and schedule');
 PERFORM pg_temp.ok((SELECT count(*)=4 AND min(due_at)>=snoozed FROM public.notification_plans WHERE lesson_id=l),'scheduler snooze only four stages');
 PERFORM public.cancel_prompt_work(l,'test');
 SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.snooze_prompt(%L,10,%L)',l,gen_random_uuid()),'TP_NO_PENDING_PROMPT','scheduler no pending snooze');
 RESET ROLE;
END $$;
-- A partial multi-device acceptance must not resend that device after replan.
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 20:55+08'; c record; accepted_device uuid; pending_id uuid; new_device uuid; total int; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Partial','2027-01-07 19:00+08','2027-01-07 21:00+08');
 INSERT INTO public.teacher_devices(user_id,installation_id,token,environment,last_seen_at) VALUES('10000000-0000-4000-8000-000000000011',gen_random_uuid(),repeat('c1',32),'sandbox',n) RETURNING id INTO new_device;
 SET LOCAL ROLE service_role;
 total:=0;
 FOR c IN SELECT * FROM public.scheduler_tick(n,50) WHERE lesson_id=l LOOP
  total:=total+1;
  IF total=1 THEN
   accepted_device:=c.device_id;
   PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n);
   PERFORM public.mark_prompt_sent(c.outbox_id,c.lease_token,c.outbox_id,'dry_run',n);
  ELSE pending_id:=c.outbox_id; END IF;
 END LOOP;
 PERFORM pg_temp.ok(total=2,'scheduler snapshots two devices');
 RESET ROLE;
 -- Third registration after snapshot must wait for a new stage/revision.
 INSERT INTO public.teacher_devices(user_id,installation_id,token,environment,last_seen_at) VALUES('10000000-0000-4000-8000-000000000011',gen_random_uuid(),repeat('c2',32),'sandbox',n);
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.scheduler_tick(n,50)),'scheduler device snapshot fixed for revision');
 RESET ROLE;
 UPDATE public.lessons SET plan_revision=plan_revision+1 WHERE id=l;
 SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok((SELECT status='cancelled' AND lease_token IS NULL FROM public.notification_outbox WHERE id=pending_id),'scheduler replan cancels pending old revision');
 total:=0;
 FOR c IN SELECT * FROM public.scheduler_tick(n,50) WHERE lesson_id=l LOOP
  total:=total+1;
  PERFORM pg_temp.ok(c.device_id<>accepted_device,'scheduler accepted device not rematerialized across revisions');
  PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n);
  PERFORM public.mark_prompt_sent(c.outbox_id,c.lease_token,c.outbox_id,'dry_run',n);
 END LOOP;
 PERFORM pg_temp.ok(total=2,'scheduler replan includes unaccepted and new device');
 RESET ROLE;
 UPDATE public.lessons SET plan_revision=plan_revision+1 WHERE id=l;
 PERFORM pg_temp.ok((SELECT status='completed' FROM public.notification_plans WHERE lesson_id=l AND kind='heads_up'),'scheduler completed logical stage never reopened');
 PERFORM public.cancel_prompt_work(l,'test');
 UPDATE public.teacher_devices SET revoked_at=n WHERE token IN (repeat('c1',32),repeat('c2',32));
END $$;
DO $$ DECLARE l uuid; c record; n timestamptz:='2027-01-07 21:59:30+08'; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Quiet Retry','2027-01-07 20:00+08','2027-01-07 22:00+08');
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n);
 PERFORM public.mark_prompt_failed(c.outbox_id,c.lease_token,'timeout',true,false,n);
 PERFORM pg_temp.ok((SELECT available_at='2027-01-08 09:00+08' FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler retry crossing quiet hours deferred');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; n timestamptz:='2027-01-07 21:00+08'; c record; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Expired Exhaustion','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM public.scheduler_tick(n+interval '121 seconds',50);
 PERFORM public.scheduler_tick(n+interval '242 seconds',50);
 PERFORM public.scheduler_tick(n+interval '363 seconds',50);
 PERFORM pg_temp.ok((SELECT status='failed' AND attempt_count=3 AND lease_token IS NULL FROM public.notification_outbox WHERE id=c.outbox_id),'scheduler third lease expiry terminal');
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM public.notification_deliveries WHERE outbox_id=c.outbox_id AND outcome='unknown'),'scheduler all expired attempts logged once');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
DO $$ DECLARE l uuid; m uuid:=gen_random_uuid(); r jsonb; BEGIN
 l:=pg_temp.fixture('Demo Scheduler Overrun Cap',clock_timestamp()-interval '3 hours',clock_timestamp()-interval '55 minutes');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 r:=public.snooze_prompt(l,10,m);
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT snoozed_until=scheduled_end_at+interval '60 minutes' FROM public.lessons WHERE id=l),'scheduler overrun snooze capped at E plus sixty');
 SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.snooze_prompt(%L,10,%L)',l,gen_random_uuid()),'TP_SNOOZE_LIMIT','scheduler cap cannot advance twice');
 RESET ROLE; PERFORM public.cancel_prompt_work(l,'test');
END $$;
-- Read dates must follow Singapore even when the connection date is yesterday.
DO $$ DECLARE l uuid; tz text; d date:=(clock_timestamp() AT TIME ZONE 'Asia/Singapore')::date; BEGIN
 l:=pg_temp.fixture('Demo Date Boundary',(d+time '00:30') AT TIME ZONE 'Asia/Singapore',(d+time '01:30') AT TIME ZONE 'Asia/Singapore');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 FOREACH tz IN ARRAY ARRAY['UTC','America/Los_Angeles'] LOOP
  PERFORM set_config('TimeZone',tz,true);
  PERFORM pg_temp.ok(public.my_lessons_today()->>'date'=d::text AND public.my_lessons_today()->'lessons' @> jsonb_build_array(jsonb_build_object('lesson_id',l)),'scheduler list Singapore date boundary '||tz);
 END LOOP;
 RESET ROLE;
END $$;
ROLLBACK;
