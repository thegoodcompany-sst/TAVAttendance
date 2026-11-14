-- Fresh-chain core. Apply only to an empty database after real Auth (or local shim).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE public.profiles (
 id uuid PRIMARY KEY REFERENCES auth.users(id), display_name text NOT NULL CHECK (display_name=btrim(display_name) AND length(display_name) BETWEEN 1 AND 80),
 role text NOT NULL CHECK(role IN ('admin','teacher','parent')), active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.students (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), display_name text NOT NULL CHECK(display_name=btrim(display_name) AND length(display_name) BETWEEN 1 AND 80), active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.classes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), short_label text NOT NULL UNIQUE CHECK(short_label=btrim(short_label) AND length(short_label) BETWEEN 1 AND 80),
 subject text NOT NULL CHECK(subject=btrim(subject) AND length(subject) BETWEEN 1 AND 80), is_study_space boolean NOT NULL DEFAULT false, active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.terms (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), label text NOT NULL CHECK(label=btrim(label) AND length(label) BETWEEN 1 AND 80), starts_on date NOT NULL, ends_on date NOT NULL CHECK(ends_on>=starts_on)
);
CREATE TABLE public.calendar_exceptions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), class_id uuid REFERENCES public.classes(id), starts_on date NOT NULL, ends_on date NOT NULL CHECK(ends_on>=starts_on),
 kind text NOT NULL CHECK(kind IN ('holiday','closure')), reason_code text NOT NULL CHECK(reason_code IN ('public_holiday','centre_closed'))
);
CREATE TABLE public.timetable_rules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), class_id uuid NOT NULL REFERENCES public.classes(id), term_id uuid NOT NULL REFERENCES public.terms(id),
 iso_weekday smallint NOT NULL CHECK(iso_weekday BETWEEN 1 AND 7), local_start time NOT NULL, duration_minutes int NOT NULL CHECK(duration_minutes BETWEEN 15 AND 240),
 effective_from date NOT NULL, effective_until date NOT NULL CHECK(effective_until>=effective_from), default_teacher_id uuid NOT NULL REFERENCES public.profiles(id), active boolean NOT NULL DEFAULT true, revision bigint NOT NULL DEFAULT 1 CHECK(revision>=1)
);
CREATE TABLE public.enrollments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), student_id uuid NOT NULL REFERENCES public.students(id), class_id uuid NOT NULL REFERENCES public.classes(id),
 starts_on date NOT NULL, ends_on date CHECK(ends_on>=starts_on), UNIQUE(student_id,class_id,starts_on)
);
CREATE TABLE public.feature_flags (
 key text PRIMARY KEY CHECK(key IN ('teacher_prompts','teacher_prompt_push')), enabled boolean NOT NULL DEFAULT false, updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.feature_flags(key) VALUES ('teacher_prompts'),('teacher_prompt_push');
CREATE TABLE public.runtime_settings (id boolean PRIMARY KEY DEFAULT true CHECK(id), demo_enabled boolean NOT NULL DEFAULT false);
INSERT INTO public.runtime_settings DEFAULT VALUES;
CREATE TABLE public.lessons (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), class_id uuid NOT NULL REFERENCES public.classes(id), timetable_rule_id uuid REFERENCES public.timetable_rules(id), occurrence_date date NOT NULL,
 scheduled_start_at timestamptz NOT NULL, scheduled_end_at timestamptz NOT NULL, source_rule_revision bigint,
 schedule_overridden boolean NOT NULL DEFAULT false, staffing_overridden boolean NOT NULL DEFAULT false, accountable_teacher_id uuid NOT NULL REFERENCES public.profiles(id),
 started_at timestamptz, ended_at timestamptz, cancelled_at timestamptz, cancellation_reason text CHECK(cancellation_reason IN ('public_holiday','centre_closed','manual','rule_removed')),
 snoozed_until timestamptz, snooze_count int NOT NULL DEFAULT 0 CHECK(snooze_count BETWEEN 0 AND 3), register_revision bigint NOT NULL DEFAULT 0 CHECK(register_revision>=0), plan_revision bigint NOT NULL DEFAULT 1 CHECK(plan_revision>=1),
 overdue_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(timetable_rule_id,occurrence_date), CHECK(scheduled_end_at>scheduled_start_at AND scheduled_end_at<=scheduled_start_at+interval '4 hours'),
 CHECK(ended_at IS NULL OR (started_at IS NOT NULL AND ended_at>=started_at)), CHECK((cancelled_at IS NULL)=(cancellation_reason IS NULL))
);
CREATE TABLE public.lesson_staff (
 lesson_id uuid NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE, teacher_id uuid NOT NULL REFERENCES public.profiles(id), assignment_kind text NOT NULL CHECK(assignment_kind IN ('regular','assistant','substitute')), PRIMARY KEY(lesson_id,teacher_id)
);
CREATE TABLE public.lesson_roster (
 lesson_id uuid NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE, student_id uuid NOT NULL REFERENCES public.students(id), enrollment_id uuid REFERENCES public.enrollments(id), created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(lesson_id,student_id)
);
CREATE TABLE public.attendance_records (
 lesson_id uuid NOT NULL, student_id uuid NOT NULL, status text NOT NULL CHECK(status IN ('present','late','absent')), absence_informed boolean,
 marked_by uuid NOT NULL REFERENCES public.profiles(id), marked_at timestamptz NOT NULL, mutation_id uuid NOT NULL, PRIMARY KEY(lesson_id,student_id),
 FOREIGN KEY(lesson_id,student_id) REFERENCES public.lesson_roster(lesson_id,student_id) ON DELETE CASCADE, CHECK(status='absent' OR absence_informed IS NULL)
);
CREATE TABLE public.lesson_feedback (
 lesson_id uuid PRIMARY KEY REFERENCES public.lessons(id), body text NOT NULL CHECK(length(body)<=1000 AND body=btrim(body) AND body !~* '[STFGM][0-9]{7}[A-Z]'),
 updated_by uuid NOT NULL REFERENCES public.profiles(id), updated_at timestamptz NOT NULL, revision bigint NOT NULL DEFAULT 1 CHECK(revision>=1)
);
CREATE TABLE public.lesson_submissions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lesson_id uuid NOT NULL UNIQUE REFERENCES public.lessons(id), register_revision bigint NOT NULL, feedback_revision bigint NOT NULL,
 submitted_by uuid NOT NULL REFERENCES public.profiles(id), submitted_at timestamptz NOT NULL, mutation_id uuid NOT NULL, UNIQUE(submitted_by,mutation_id)
);
CREATE TABLE public.mutation_receipts (
 actor_id uuid NOT NULL REFERENCES public.profiles(id), mutation_id uuid NOT NULL, operation text NOT NULL, lesson_id uuid NOT NULL REFERENCES public.lessons(id), request_hash text NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id)
);
CREATE TABLE public.audit_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid REFERENCES public.profiles(id), lesson_id uuid REFERENCES public.lessons(id), event_code text NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(), details jsonb NOT NULL DEFAULT '{}',
 CHECK(jsonb_typeof(details)='object' AND details - ARRAY['revision','counts','reason_code','kind']::text[] = '{}'::jsonb)
);
CREATE TABLE public.prompt_policy (
 id boolean PRIMARY KEY DEFAULT true CHECK(id), heads_up_minutes int NOT NULL DEFAULT -5, attendance_minutes int NOT NULL DEFAULT 0, follow_up_minutes int NOT NULL DEFAULT 15, final_minutes int NOT NULL DEFAULT 60,
 quiet_start time NOT NULL DEFAULT '22:00', quiet_end time NOT NULL DEFAULT '07:00', quiet_resume time NOT NULL DEFAULT '09:00', overdue_grace_minutes int NOT NULL DEFAULT 15, max_snoozes int NOT NULL DEFAULT 3, updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(heads_up_minutes>=-30 AND heads_up_minutes<attendance_minutes AND attendance_minutes<follow_up_minutes AND follow_up_minutes<final_minutes AND final_minutes<=180),
 CHECK(quiet_start>quiet_end AND quiet_resume>=quiet_end AND quiet_resume<quiet_start), CHECK(overdue_grace_minutes BETWEEN 1 AND 60), CHECK(max_snoozes BETWEEN 0 AND 3)
);
INSERT INTO public.prompt_policy DEFAULT VALUES;
CREATE TABLE public.teacher_devices (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.profiles(id), installation_id uuid NOT NULL,
 token text NOT NULL CHECK(token ~ '^[0-9a-f]+$' AND length(token) BETWEEN 32 AND 512 AND length(token)%2=0), environment text NOT NULL CHECK(environment IN ('sandbox','production')),
 last_seen_at timestamptz NOT NULL, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(environment,token), UNIQUE(user_id,installation_id,environment)
);
CREATE TABLE public.notification_plans (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lesson_id uuid NOT NULL REFERENCES public.lessons(id), kind text NOT NULL CHECK(kind IN ('heads_up','attendance','follow_up','final','simulation')),
 revision bigint NOT NULL, recipient_id uuid NOT NULL REFERENCES public.profiles(id), due_at timestamptz NOT NULL, status text NOT NULL CHECK(status IN ('pending','completed','cancelled')), cancel_reason text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(lesson_id,kind)
);
CREATE TABLE public.notification_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), plan_id uuid NOT NULL REFERENCES public.notification_plans(id), plan_revision bigint NOT NULL, device_id uuid REFERENCES public.teacher_devices(id), recipient_id uuid NOT NULL REFERENCES public.profiles(id),
 status text NOT NULL CHECK(status IN ('pending','claimed','sent','failed','cancelled')), available_at timestamptz NOT NULL, attempt_count int NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 3),
 lease_token uuid, lease_until timestamptz, accepted_at timestamptz, last_error_code text, device_seen_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE NULLS NOT DISTINCT(plan_id,plan_revision,device_id), CHECK(status<>'claimed' OR (lease_token IS NOT NULL AND lease_until IS NOT NULL))
);
CREATE TABLE public.notification_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), outbox_id uuid NOT NULL REFERENCES public.notification_outbox(id), attempt_no int NOT NULL CHECK(attempt_no BETWEEN 1 AND 3), lease_token uuid NOT NULL,
 transport text NOT NULL CHECK(transport IN ('apns','dry_run','none')), outcome text NOT NULL CHECK(outcome IN ('accepted','retry','permanent_failure','no_devices','suppressed','unknown')),
 error_code text, provider_id uuid, attempted_at timestamptz NOT NULL, UNIQUE(outbox_id,attempt_no)
);
CREATE INDEX ON public.calendar_exceptions(starts_on,ends_on);
CREATE INDEX ON public.calendar_exceptions(class_id);
CREATE INDEX ON public.timetable_rules(class_id);
CREATE INDEX ON public.timetable_rules(term_id);
CREATE INDEX ON public.timetable_rules(default_teacher_id);
CREATE INDEX ON public.enrollments(class_id,starts_on,ends_on);
CREATE INDEX ON public.lessons(accountable_teacher_id,scheduled_start_at);
CREATE INDEX ON public.lessons(class_id);
CREATE INDEX ON public.lessons(scheduled_start_at);
CREATE INDEX ON public.lessons(overdue_at) WHERE cancelled_at IS NULL;
CREATE INDEX ON public.lesson_staff(teacher_id,lesson_id);
CREATE INDEX ON public.lesson_roster(student_id,lesson_id);
CREATE INDEX ON public.lesson_roster(enrollment_id);
CREATE INDEX ON public.attendance_records(student_id);
CREATE INDEX ON public.attendance_records(marked_by);
CREATE INDEX ON public.lesson_feedback(updated_by);
CREATE INDEX ON public.mutation_receipts(lesson_id);
CREATE INDEX ON public.mutation_receipts(created_at);
CREATE INDEX ON public.audit_events(actor_id);
CREATE INDEX ON public.audit_events(lesson_id,occurred_at);
CREATE INDEX ON public.audit_events(occurred_at);
CREATE INDEX ON public.teacher_devices(user_id,last_seen_at DESC) WHERE revoked_at IS NULL;
CREATE INDEX ON public.notification_plans(recipient_id);
CREATE INDEX ON public.notification_plans(due_at) WHERE status='pending';
CREATE INDEX ON public.notification_outbox(device_id);
CREATE INDEX ON public.notification_outbox(recipient_id);
CREATE INDEX ON public.notification_outbox(available_at,id) WHERE status IN ('pending','claimed');
CREATE INDEX ON public.notification_deliveries(attempted_at);

CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT FROM public.profiles WHERE id=auth.uid() AND active AND role='admin')
$$;
CREATE FUNCTION public.is_teacher() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT FROM public.profiles WHERE id=auth.uid() AND active AND role='teacher')
$$;
CREATE FUNCTION public.can_read_lesson(p_lesson_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.is_admin() OR (public.is_teacher() AND EXISTS(SELECT FROM public.lesson_staff WHERE lesson_id=p_lesson_id AND teacher_id=auth.uid()))
$$;
CREATE FUNCTION public.can_review_lesson(p_lesson_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.is_admin() OR (public.is_teacher() AND EXISTS(SELECT FROM public.lessons WHERE id=p_lesson_id AND accountable_teacher_id=auth.uid()))
$$;
CREATE FUNCTION public.can_read_class(p_class_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.is_admin() OR (public.is_teacher() AND EXISTS(SELECT FROM public.lessons l JOIN public.lesson_staff s ON s.lesson_id=l.id WHERE l.class_id=p_class_id AND s.teacher_id=auth.uid()))
$$;
CREATE FUNCTION public.require_enabled() RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NOT (public.is_admin() OR public.is_teacher()) THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT FROM public.feature_flags WHERE key='teacher_prompts' AND enabled) THEN RAISE EXCEPTION 'TP_DISABLED' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.require_service_or_admin() RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF current_setting('role',true) NOT IN ('service_role','none') AND NOT public.is_admin() THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
 IF current_setting('role',true)='none' AND session_user <> current_user AND NOT public.is_admin() THEN RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.require_review(p_lesson_id uuid) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM public.require_enabled();
 IF NOT public.can_review_lesson(p_lesson_id) OR NOT EXISTS(SELECT FROM public.lessons l JOIN public.classes c ON c.id=l.class_id WHERE l.id=p_lesson_id AND NOT c.is_study_space) THEN
  RAISE EXCEPTION 'TP_NOT_AVAILABLE' USING ERRCODE='42501';
 END IF;
END $$;
CREATE FUNCTION public.check_accountable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 -- Serialize deferred validation with concurrent activation/role changes.
 IF TG_TABLE_NAME='lessons' THEN
  PERFORM id FROM public.profiles WHERE id=NEW.accountable_teacher_id FOR SHARE;
 ELSIF TG_TABLE_NAME='lesson_staff' THEN
  PERFORM p.id FROM public.profiles p JOIN public.lessons l ON l.accountable_teacher_id=p.id WHERE l.id=coalesce(NEW.lesson_id,OLD.lesson_id) FOR SHARE OF p;
 END IF;
 IF EXISTS(SELECT FROM public.lessons l JOIN public.profiles p ON p.id=l.accountable_teacher_id
   WHERE (p.role<>'teacher' OR (NOT p.active AND l.cancelled_at IS NULL AND NOT EXISTS(SELECT FROM public.lesson_submissions s WHERE s.lesson_id=l.id)))
      OR NOT EXISTS(SELECT FROM public.lesson_staff s WHERE s.lesson_id=l.id AND s.teacher_id=l.accountable_teacher_id)) THEN
  RAISE EXCEPTION 'TP_INVALID_INPUT' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER lesson_accountable AFTER INSERT OR UPDATE ON public.lessons DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_accountable();
CREATE CONSTRAINT TRIGGER staff_accountable AFTER INSERT OR UPDATE OR DELETE ON public.lesson_staff DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_accountable();
CREATE CONSTRAINT TRIGGER profile_accountable AFTER UPDATE OR DELETE ON public.profiles DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_accountable();
-- Even trusted provisioning takes the same parent lock as application RPCs.
CREATE FUNCTION public.lock_lesson_child() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.lesson_id<>OLD.lesson_id THEN
  PERFORM id FROM public.lessons WHERE id IN (NEW.lesson_id,OLD.lesson_id) ORDER BY id FOR UPDATE;
 ELSE
  PERFORM id FROM public.lessons WHERE id=coalesce(NEW.lesson_id,OLD.lesson_id) FOR UPDATE;
 END IF;
 RETURN coalesce(NEW,OLD);
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['lesson_staff','lesson_roster','attendance_records','lesson_feedback','lesson_submissions'] LOOP
  EXECUTE format('CREATE TRIGGER lock_lesson_child BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.lock_lesson_child()',t);
 END LOOP;
END $$;
-- No client DML grants, including administrators. Provisioning uses a trusted owner.
DO $$ DECLARE t text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT ALL ON public.%I TO service_role',t);
 END LOOP;
END $$;
GRANT SELECT ON public.profiles,public.students,public.classes,public.terms,public.timetable_rules,public.calendar_exceptions,public.enrollments,public.lessons,public.lesson_staff,public.lesson_roster,public.attendance_records,public.lesson_feedback,public.lesson_submissions,public.feature_flags,public.prompt_policy,public.audit_events TO authenticated;
CREATE POLICY read_profiles ON public.profiles FOR SELECT TO authenticated USING(public.is_admin() OR (public.is_teacher() AND id=auth.uid()));
CREATE POLICY read_students ON public.students FOR SELECT TO authenticated USING(public.is_admin() OR EXISTS(SELECT FROM public.lesson_roster r WHERE r.student_id=students.id AND public.can_read_lesson(r.lesson_id)));
CREATE POLICY read_classes ON public.classes FOR SELECT TO authenticated USING(public.can_read_class(id));
CREATE POLICY read_rules ON public.timetable_rules FOR SELECT TO authenticated USING(public.can_read_class(class_id));
CREATE POLICY read_terms ON public.terms FOR SELECT TO authenticated USING(public.is_admin() OR EXISTS(SELECT FROM public.timetable_rules r WHERE r.term_id=terms.id AND public.can_read_class(r.class_id)));
CREATE POLICY read_exceptions ON public.calendar_exceptions FOR SELECT TO authenticated USING(public.is_admin() OR (public.is_teacher() AND ((class_id IS NULL AND EXISTS(SELECT FROM public.lessons l WHERE public.can_read_lesson(l.id))) OR public.can_read_class(class_id))));
CREATE POLICY read_enrollments ON public.enrollments FOR SELECT TO authenticated USING(public.is_admin() OR EXISTS(SELECT FROM public.lesson_roster r WHERE r.enrollment_id=enrollments.id AND public.can_read_lesson(r.lesson_id)));
CREATE POLICY read_lessons ON public.lessons FOR SELECT TO authenticated USING(public.can_read_lesson(id));
CREATE POLICY read_staff ON public.lesson_staff FOR SELECT TO authenticated USING(public.can_read_lesson(lesson_id));
CREATE POLICY read_roster ON public.lesson_roster FOR SELECT TO authenticated USING(public.can_read_lesson(lesson_id));
CREATE POLICY read_attendance ON public.attendance_records FOR SELECT TO authenticated USING(public.can_read_lesson(lesson_id));
CREATE POLICY read_feedback ON public.lesson_feedback FOR SELECT TO authenticated USING(public.can_read_lesson(lesson_id));
CREATE POLICY read_submissions ON public.lesson_submissions FOR SELECT TO authenticated USING(public.can_read_lesson(lesson_id));
CREATE POLICY read_flags ON public.feature_flags FOR SELECT TO authenticated USING(public.is_admin() OR public.is_teacher());
CREATE POLICY read_policy ON public.prompt_policy FOR SELECT TO authenticated USING(public.is_admin());
CREATE POLICY read_audit ON public.audit_events FOR SELECT TO authenticated USING(public.is_admin());
GRANT EXECUTE ON FUNCTION public.is_admin(),public.is_teacher(),public.can_read_lesson(uuid),public.can_review_lesson(uuid),public.can_read_class(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
