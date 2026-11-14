\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
UPDATE public.notification_plans SET status='cancelled';
DO $$ DECLARE r jsonb; d uuid; installation uuid:=gen_random_uuid(); old_seen timestamptz; i int; BEGIN
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 r:=public.register_device(installation,repeat('a1',32),'sandbox'); d:=(r->>'device_id')::uuid; old_seen:=(r->>'last_seen_at')::timestamptz;
 PERFORM pg_temp.ok(r->>'environment'='sandbox' AND NOT(r ? 'token'),'devices teacher registration response has no token');
 r:=public.register_device(installation,repeat('a2',32),'sandbox');
 PERFORM pg_temp.ok((r->>'device_id')::uuid=d AND (r->>'last_seen_at')::timestamptz>old_seen,'devices same installation rotation stable identity and version');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,''xyz'',''sandbox'')',gen_random_uuid()),'TP_INVALID_INPUT','devices hex shape validation');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',gen_random_uuid(),repeat('a',33)),'TP_INVALID_INPUT','devices token even length');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',gen_random_uuid(),repeat('a',514)),'TP_INVALID_INPUT','devices token maximum');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''other'')',gen_random_uuid(),repeat('a',64)),'TP_INVALID_INPUT','devices environment validation');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000012');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',gen_random_uuid(),repeat('a2',32)),'TP_NOT_AVAILABLE','devices foreign token takeover denied');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',installation,repeat('b1',32)),'TP_NOT_AVAILABLE','devices foreign installation takeover denied');
 PERFORM pg_temp.ok(public.revoke_device(d)->>'revoked'='false','devices revoke self only');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011');
 PERFORM pg_temp.ok(public.revoke_device(d)->>'revoked'='true' AND public.revoke_device(d)->>'revoked'='true','devices revoke idempotent');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000012');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',gen_random_uuid(),repeat('a2',32)),'TP_NOT_AVAILABLE','devices revoked token still cannot transfer');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011');
 FOR i IN 1..6 LOOP PERFORM public.register_device(gen_random_uuid(),repeat(lpad(to_hex(30+i),2,'0'),32),'sandbox'); END LOOP;
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT count(*)=5 FROM public.teacher_devices WHERE user_id='10000000-0000-4000-8000-000000000011' AND revoked_at IS NULL),'devices cap five active');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); SET LOCAL ROLE authenticated;
 PERFORM pg_temp.ok(public.register_device(gen_random_uuid(),repeat('f1',32),'sandbox')->>'device_id' IS NOT NULL,'devices admin registration');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000099');
 PERFORM pg_temp.throws(format('SELECT public.register_device(%L,%L,''sandbox'')',gen_random_uuid(),repeat('f2',32)),'TP_NOT_AVAILABLE','devices parent denied');
 RESET ROLE;
END $$;
DO $$ DECLARE l uuid; c record; n timestamptz:='2027-01-07 20:55+08'; inst uuid; token text; version timestamptz; BEGIN
 -- One deterministic fake device for token-version races.
 UPDATE public.teacher_devices SET revoked_at=n WHERE user_id='10000000-0000-4000-8000-000000000011';
 UPDATE public.teacher_devices SET revoked_at=NULL,last_seen_at=n-interval '1 hour' WHERE id='80000000-0000-4000-8000-000000000011';
 l:=pg_temp.fixture('Demo Device Version','2027-01-07 19:00+08','2027-01-07 21:00+08');
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n,50) WHERE lesson_id=l;
 PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n);
 SELECT installation_id,teacher_devices.token,last_seen_at INTO inst,token,version FROM public.teacher_devices WHERE id=c.device_id;
 RESET ROLE;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 PERFORM public.register_device(inst,repeat('e1',32),'sandbox');
 RESET ROLE; SET LOCAL ROLE service_role;
 PERFORM pg_temp.ok(public.mark_prompt_failed(c.outbox_id,c.lease_token,'unregistered',false,true,n+interval '1 second'),'devices invalid token response recorded');
 PERFORM pg_temp.ok((SELECT revoked_at IS NULL FROM public.teacher_devices WHERE id=c.device_id),'devices late 410 cannot revoke refreshed token');
 RESET ROLE;
 UPDATE public.teacher_devices SET last_seen_at=n-interval '1 minute' WHERE id=c.device_id;
 SET LOCAL ROLE service_role;
 SELECT * INTO c FROM public.scheduler_tick(n+interval '5 minutes',50) WHERE lesson_id=l;
 PERFORM public.prepare_prompt_delivery(c.outbox_id,c.lease_token,n+interval '5 minutes');
 PERFORM public.mark_prompt_failed(c.outbox_id,c.lease_token,'bad_device_token',false,true,n+interval '5 minutes 1 second');
 PERFORM pg_temp.ok((SELECT revoked_at IS NOT NULL FROM public.teacher_devices WHERE id=c.device_id),'devices matching token version revoked');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_deliveries WHERE error_code LIKE '%e1e1%'),'devices tokens absent from diagnostics');
 RESET ROLE;
 PERFORM public.cancel_prompt_work(l,'test');
END $$;
ROLLBACK;
