\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
SELECT pg_temp.ok((SELECT count(*)=2 AND bool_and(NOT enabled) FROM public.feature_flags),'schema flags ship OFF');
SELECT pg_temp.ok(NOT (SELECT demo_enabled FROM public.runtime_settings),'schema demo ships OFF');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity),'schema every table has RLS');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef AND NOT ('search_path=pg_catalog, public'=ANY(p.proconfig))),'schema privileged search paths pinned');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','public.scheduler_tick(timestamptz,integer)','EXECUTE') AND has_function_privilege('service_role','public.scheduler_tick(timestamptz,integer)','EXECUTE'),'schema scheduler service only');
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.mark_all_present(uuid,bigint,uuid)','EXECUTE') AND NOT has_function_privilege('service_role','public.mark_all_present(uuid,bigint,uuid)','EXECUTE'),'schema UI execute restricted');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','public.mutation_finish(uuid,uuid,text,jsonb,jsonb)','EXECUTE'),'schema internal mutation helper private');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_tables WHERE schemaname='public' AND has_table_privilege('authenticated',quote_ident(schemaname)||'.'||quote_ident(tablename),'INSERT,UPDATE,DELETE')),'schema direct client writes denied');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_constraint c WHERE c.contype='f' AND c.connamespace='public'::regnamespace AND NOT EXISTS(SELECT FROM pg_index i WHERE i.indrelid=c.conrelid AND i.indisvalid AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1] @> c.conkey)),'schema FK lookup indexes');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM pg_extension WHERE extname IN ('pg_cron','pgtap')),'schema no cron or pgTAP dependency');
SELECT pg_temp.throws($$INSERT INTO public.prompt_policy VALUES(false)$$,'23514','schema singleton policy constraint');
SELECT pg_temp.throws($$UPDATE public.prompt_policy SET final_minutes=181$$,'23514','schema bounded offsets');
SELECT pg_temp.throws($$UPDATE public.prompt_policy SET quiet_resume='23:00'$$,'23514','schema valid quiet window');
SET LOCAL ROLE authenticated;
SELECT pg_temp.claims('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.ok(NOT public.is_admin() AND NOT public.is_teacher(),'schema missing profile fail closed despite metadata');
SELECT pg_temp.throws($$SELECT public.my_lessons_today()$$,'TP_NOT_AVAILABLE','schema missing profile RPC denied');
RESET ROLE;
INSERT INTO auth.users(id) VALUES('aaaaaaaa-0000-4000-8000-000000000001');
INSERT INTO public.profiles VALUES('aaaaaaaa-0000-4000-8000-000000000001','Demo Lead','teacher',true,now());
INSERT INTO public.classes(id,short_label,subject) VALUES('aaaaaaaa-0000-4000-8000-000000000002','Demo Class','Demo');
SELECT pg_temp.throws($q$DO $$ BEGIN INSERT INTO public.lessons(class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at) VALUES('aaaaaaaa-0000-4000-8000-000000000002',current_date,now(),now()+interval '1 hour','aaaaaaaa-0000-4000-8000-000000000001',now()+interval '2 hours'); SET CONSTRAINTS ALL IMMEDIATE; END $$ $q$,'23514','schema missing staff lead rejected at commit');
ROLLBACK;
