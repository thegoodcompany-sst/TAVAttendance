\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
-- Created AFTER the chain: both schema and global defaults must now be private.
CREATE FUNCTION public.acl_after_chain() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
DO $$ DECLARE r text; f regprocedure; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.ok(NOT has_function_privilege(r,'public.acl_after_chain()','EXECUTE'),'acl future functions private for '||r);
  IF to_regprocedure('public.hostile_acl_probe()') IS NOT NULL THEN
   PERFORM pg_temp.ok(NOT has_function_privilege(r,'public.hostile_acl_probe()','EXECUTE'),'acl preexisting functions revoked for '||r);
  END IF;
  FOREACH f IN ARRAY ARRAY['public.cancel_prompt_work(uuid,text)'::regprocedure,'public.mutation_finish(uuid,uuid,text,jsonb,jsonb)'::regprocedure,'public.supersede_prompt_stages(uuid,timestamptz)'::regprocedure] LOOP
   PERFORM pg_temp.ok(NOT has_function_privilege(r,f,'EXECUTE'),'acl internal helper private for '||r||' '||f::text);
  END LOOP;
 END LOOP;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND has_function_privilege('anon',p.oid,'EXECUTE')),'acl anon has no public function access');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND has_function_privilege('authenticated',p.oid,'EXECUTE') AND p.proname NOT IN
  ('is_admin','is_teacher','can_read_lesson','can_review_lesson','can_read_class','generate_lessons','lesson_state','my_lessons_today','lesson_for_prompt','mark_attendance','mark_all_present','save_feedback','submit_lesson','confirm_all_present_and_submit','admin_missing_submissions','edit_lesson','assign_lesson_teacher','cancel_lesson','snooze_prompt','register_device','revoke_device','unregister_device','simulate_prompt_now','plan_prompts')),'acl authenticated exact allowlist');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND has_function_privilege('service_role',p.oid,'EXECUTE') AND p.proname NOT IN
  ('generate_lessons','plan_prompts','scheduler_tick','prepare_prompt_delivery','mark_prompt_sent','mark_prompt_failed','refresh_prompt_schedule','defer_quiet','demo_shift_to_today')),'acl service exact allowlist');
END $$;
SET LOCAL ROLE anon;
SELECT pg_temp.throws($$SELECT public.cancel_prompt_work(gen_random_uuid(),'attack')$$,'42501','acl anonymous helper execution denied');
SELECT pg_temp.throws($$SELECT public.scheduler_tick(now(),1)$$,'42501','acl anonymous worker execution denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.throws($$SELECT public.cancel_prompt_work(gen_random_uuid(),'attack')$$,'42501','acl authenticated helper execution denied');
SELECT pg_temp.throws($$SELECT public.prepare_prompt_delivery(gen_random_uuid(),gen_random_uuid(),now())$$,'42501','acl authenticated worker execution denied');
RESET ROLE;
-- Deliberately leak worker grants inside this rollback-only test. Body checks still deny.
GRANT EXECUTE ON FUNCTION public.scheduler_tick(timestamptz,int),public.prepare_prompt_delivery(uuid,uuid,timestamptz),public.mark_prompt_sent(uuid,uuid,uuid,text,timestamptz),public.mark_prompt_failed(uuid,uuid,text,boolean,boolean,timestamptz),public.refresh_prompt_schedule() TO anon,authenticated;
DO $$ DECLARE r text; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  EXECUTE format('SET LOCAL ROLE %I',r);
  PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001'); -- even admin + spoofed service JWT
  PERFORM pg_temp.throws('SELECT public.scheduler_tick(now(),1)','TP_NOT_AVAILABLE','acl worker body tick denies '||r);
  PERFORM pg_temp.throws('SELECT public.prepare_prompt_delivery(gen_random_uuid(),gen_random_uuid(),now())','TP_NOT_AVAILABLE','acl worker body prepare denies '||r);
  PERFORM pg_temp.throws('SELECT public.mark_prompt_sent(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),''dry_run'',now())','TP_NOT_AVAILABLE','acl worker body sent denies '||r);
  PERFORM pg_temp.throws('SELECT public.mark_prompt_failed(gen_random_uuid(),gen_random_uuid(),''timeout'',true,false,now())','TP_NOT_AVAILABLE','acl worker body failed denies '||r);
  PERFORM pg_temp.throws('SELECT public.refresh_prompt_schedule()','TP_NOT_AVAILABLE','acl worker body refresh denies '||r);
  RESET ROLE;
 END LOOP;
END $$;
ROLLBACK;
