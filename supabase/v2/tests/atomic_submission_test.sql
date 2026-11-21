\set ON_ERROR_STOP on
BEGIN;
\ir helpers.sql
DO $$ DECLARE l uuid; zero uuid; future uuid; old uuid; cancelled uuid; m uuid:=gen_random_uuid(); r jsonb; before_count int; BEGIN
 l:=pg_temp.fixture('Demo Atomic Submit',now()-interval '1 hour',now()+interval '1 hour',members=>4);
 zero:=pg_temp.fixture('Demo Atomic Zero',now()-interval '1 hour',now()+interval '1 hour',members=>0);
 future:=pg_temp.fixture('Demo Atomic Future',now()+interval '1 hour',now()+interval '2 hours');
 old:=pg_temp.fixture('Demo Atomic Old',now()-interval '10 days',now()-interval '10 days'+interval '1 hour');
 cancelled:=pg_temp.fixture('Demo Atomic Cancelled',now()-interval '1 hour',now()+interval '1 hour');
 UPDATE public.lessons SET cancelled_at=now(),cancellation_reason='manual',plan_revision=plan_revision+1 WHERE id=cancelled;
 INSERT INTO public.attendance_records VALUES
 (l,'20000000-0000-4000-8000-000000000001','late',NULL,'10000000-0000-4000-8000-000000000011',now(),gen_random_uuid()),
 (l,'20000000-0000-4000-8000-000000000002','absent',true,'10000000-0000-4000-8000-000000000011',now(),gen_random_uuid());
 UPDATE public.lessons SET register_revision=2 WHERE id=l;
 INSERT INTO public.lesson_staff VALUES(l,'10000000-0000-4000-8000-000000000012','assistant');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000012'); SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,0,%L)',l,m),'TP_NOT_AVAILABLE','atomic submit assistant denied');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000013');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,0,%L)',l,m),'TP_NOT_AVAILABLE','atomic submit unrelated teacher denied');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000099');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,0,%L)',l,m),'TP_NOT_AVAILABLE','atomic submit parent denied');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,0,0,%L)',future,m),'TP_TOO_EARLY','atomic submit future denied');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,0,0,%L)',old,m),'TP_TOO_OLD','atomic submit outside teacher window denied');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,0,0,%L)',cancelled,m),'TP_LOCKED','atomic submit cancelled denied');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,0,0,%L)',zero,m),'TP_INCOMPLETE','atomic submit teacher zero roster denied');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,1,0,%L)',l,m),'TP_CONFLICT','atomic submit register CAS');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,1,%L)',l,m),'TP_CONFLICT','atomic submit feedback CAS');
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT count(*)=2 FROM public.attendance_records WHERE lesson_id=l) AND NOT EXISTS(SELECT FROM public.mutation_receipts WHERE mutation_id=m),'atomic submit failed checks leave marks and receipts unchanged');
 SET LOCAL ROLE authenticated;
 r:=public.confirm_all_present_and_submit(l,2,0,m);
 PERFORM pg_temp.ok(r->>'register_revision'='3' AND r->>'submission_id' IS NOT NULL AND r->>'replayed'='false' AND r - ARRAY['lesson_id','submission_id','submitted_at','register_revision','replayed']='{}'::jsonb,'atomic submit same response shape and single revision bump');
 PERFORM pg_temp.ok(public.confirm_all_present_and_submit(l,2,0,m)=r||'{"replayed":true}'::jsonb,'atomic submit exact replay after submission');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,3,0,%L)',l,m),'TP_MUTATION_REUSED','atomic submit changed argument replay rejected');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,0,0,%L)',zero,m),'TP_MUTATION_REUSED','atomic submit different lesson replay rejected');
 PERFORM pg_temp.throws(format('SELECT public.submit_lesson(%L,2,0,%L)',l,m),'TP_MUTATION_REUSED','atomic submit different operation replay rejected');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,3,0,%L)',l,gen_random_uuid()),'TP_LOCKED','atomic submit distinct retry cannot write submitted lesson');
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000001');
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,0,%L)',l,m),'TP_LOCKED','atomic submit another actor cannot reuse receipt');
 PERFORM pg_temp.ok(public.confirm_all_present_and_submit(zero,0,0,gen_random_uuid())->>'register_revision'='0','atomic submit admin empty roster no revision bump');
 PERFORM pg_temp.ok(public.confirm_all_present_and_submit(old,0,0,gen_random_uuid())->>'submission_id' IS NOT NULL,'atomic submit admin can complete older work');
 RESET ROLE;
 PERFORM pg_temp.ok((SELECT count(*)=4 AND count(*) FILTER(WHERE status='present')=2 AND count(*) FILTER(WHERE status='late')=1 AND count(*) FILTER(WHERE status='absent' AND absence_informed)=1 FROM public.attendance_records WHERE lesson_id=l),'atomic submit fills only unmarked and retains late/informed absence');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.lesson_submissions WHERE lesson_id=l) AND (SELECT count(*)=1 FROM public.mutation_receipts WHERE lesson_id=l AND mutation_id=m),'atomic submit one submission and receipt');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT FROM public.notification_plans WHERE lesson_id=l AND status='pending') AND NOT EXISTS(SELECT FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id=l AND o.status IN ('pending','claimed')),'atomic submit suppresses every prompt atomically');
 -- Authority must precede receipt replay (administrator can remove a historical assignment).
 UPDATE public.lesson_staff SET teacher_id='10000000-0000-4000-8000-000000000014' WHERE lesson_id=l AND teacher_id='10000000-0000-4000-8000-000000000011';
 UPDATE public.lessons SET accountable_teacher_id='10000000-0000-4000-8000-000000000014' WHERE id=l;
 PERFORM pg_temp.claims('10000000-0000-4000-8000-000000000011'); SET LOCAL ROLE authenticated;
 PERFORM pg_temp.throws(format('SELECT public.confirm_all_present_and_submit(%L,2,0,%L)',l,m),'TP_NOT_AVAILABLE','atomic submit lost authority cannot replay receipt');
 RESET ROLE;
END $$;
ROLLBACK;
