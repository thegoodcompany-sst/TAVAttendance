\set ON_ERROR_STOP on

-- Read-only production invariants that complement structural drift checking.
-- In particular, these cover grants and Storage policies, which the hosted-vs-
-- local schema diff deliberately filters because hosted default grants vary.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '30s';
SET LOCAL plpgsql.check_asserts = on;

DO $$
DECLARE
    v_attendance_integrity TEXT;
    v_sync_attendance TEXT;
    v_substitute_scope TEXT;
    v_get_my_classes TEXT;
    v_get_today_session TEXT;
    v_session_lifecycle TEXT;
    v_session_lifecycle_guard TEXT;
    v_session_change_guard TEXT;
    v_update_session_note TEXT;
    v_session_notes_guard TEXT;
    v_get_roster TEXT;
    v_finalize_upload TEXT;
    v_review_correction TEXT;
    v_record_consent TEXT;
    v_consume_invite TEXT;
    v_submit_events TEXT;
    v_register_token TEXT;
    v_notify_attendance TEXT;
    v_notify_dismissal TEXT;
    v_cleanup_invoker TEXT;
BEGIN
    ASSERT to_regprocedure(
        'public.enforce_attendance_write_integrity()'
    ) IS NOT NULL, '038 attendance integrity function is missing';
    ASSERT to_regprocedure(
        'public.substitute_covers_session(uuid)'
    ) IS NOT NULL, '038 bounded substitute authorization is missing';
    ASSERT to_regprocedure(
        'public.get_my_classes()'
    ) IS NOT NULL, '038 staff class projection is missing';
    ASSERT to_regprocedure(
        'public.get_or_create_today_session(uuid)'
    ) IS NOT NULL, '038 today-session RPC is missing';
    ASSERT to_regprocedure(
        'public.set_session_lifecycle(uuid,text)'
    ) IS NOT NULL, '038 session lifecycle RPC is missing';
    ASSERT to_regprocedure(
        'public.update_session_note(uuid,text)'
    ) IS NOT NULL, '038 session-note RPC is missing';
    ASSERT to_regprocedure(
        'public.finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)'
    ) IS NOT NULL, '038 atomic result-slip finalizer is missing';
    ASSERT to_regprocedure(
        'public.review_correction_request(uuid,text,text)'
    ) IS NOT NULL, '038 atomic correction-review RPC is missing';
    ASSERT to_regprocedure(
        'public.record_admin_consent(uuid,text,text,text)'
    ) IS NOT NULL, '038 trusted consent-recording RPC is missing';
    ASSERT to_regprocedure(
        'public.consume_invite_rate_limit(uuid)'
    ) IS NOT NULL, '038 atomic invite quota RPC is missing';
    ASSERT to_regprocedure(
        'public.submit_app_events(jsonb)'
    ) IS NOT NULL, '038 shaped analytics ingestion RPC is missing';
    ASSERT to_regprocedure(
        'public.register_device_token(text,text)'
    ) IS NOT NULL, '038 bounded device-token RPC is missing';
    ASSERT to_regprocedure(
        'public.invoke_student_storage_cleanup()'
    ) IS NOT NULL, '038 Storage cleanup invoker is missing';

    v_attendance_integrity := LOWER(pg_get_functiondef(
        'public.enforce_attendance_write_integrity()'::REGPROCEDURE
    ));
    v_sync_attendance := LOWER(pg_get_functiondef(
        'public.sync_attendance(jsonb)'::REGPROCEDURE
    ));
    v_substitute_scope := LOWER(pg_get_functiondef(
        'public.substitute_covers_session(uuid)'::REGPROCEDURE
    ));
    v_get_my_classes := LOWER(pg_get_functiondef(
        'public.get_my_classes()'::REGPROCEDURE
    ));
    v_get_today_session := LOWER(pg_get_functiondef(
        'public.get_or_create_today_session(uuid)'::REGPROCEDURE
    ));
    v_session_lifecycle := LOWER(pg_get_functiondef(
        'public.set_session_lifecycle(uuid,text)'::REGPROCEDURE
    ));
    v_session_lifecycle_guard := LOWER(pg_get_functiondef(
        'public.enforce_session_lifecycle_boundary()'::REGPROCEDURE
    ));
    v_session_change_guard := LOWER(pg_get_functiondef(
        'public.check_retrospective_session_changes()'::REGPROCEDURE
    ));
    v_update_session_note := LOWER(pg_get_functiondef(
        'public.update_session_note(uuid,text)'::REGPROCEDURE
    ));
    v_session_notes_guard := LOWER(pg_get_functiondef(
        'public.enforce_session_notes_feature_flag()'::REGPROCEDURE
    ));
    v_get_roster := LOWER(pg_get_functiondef(
        'public.get_session_roster(uuid)'::REGPROCEDURE
    ));
    v_finalize_upload := LOWER(pg_get_functiondef(
        'public.finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)'
            ::REGPROCEDURE
    ));
    v_review_correction := LOWER(pg_get_functiondef(
        'public.review_correction_request(uuid,text,text)'::REGPROCEDURE
    ));
    v_record_consent := LOWER(pg_get_functiondef(
        'public.record_admin_consent(uuid,text,text,text)'::REGPROCEDURE
    ));
    v_consume_invite := LOWER(pg_get_functiondef(
        'public.consume_invite_rate_limit(uuid)'::REGPROCEDURE
    ));
    v_submit_events := LOWER(pg_get_functiondef(
        'public.submit_app_events(jsonb)'::REGPROCEDURE
    ));
    v_register_token := LOWER(pg_get_functiondef(
        'public.register_device_token(text,text)'::REGPROCEDURE
    ));
    v_notify_attendance := LOWER(pg_get_functiondef(
        'public.notify_parent_on_attendance()'::REGPROCEDURE
    ));
    v_notify_dismissal := LOWER(pg_get_functiondef(
        'public.notify_parent_on_dismissal()'::REGPROCEDURE
    ));
    v_cleanup_invoker := LOWER(pg_get_functiondef(
        'public.invoke_student_storage_cleanup()'::REGPROCEDURE
    ));

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.attendance_records'::REGCLASS
          AND tgname = 'enforce_attendance_write_integrity'
          AND NOT tgisinternal
    ), 'attendance integrity trigger is missing';
    ASSERT POSITION('new.marked_by := auth.uid()' IN v_attendance_integrity) > 0
       AND POSITION('new.marked_at := clock_timestamp()' IN v_attendance_integrity) > 0
       AND POSITION('student was not enrolled for this session' IN v_attendance_integrity) > 0,
        'attendance actor/time/enrollment enforcement drifted';
    ASSERT (
        SELECT COUNT(*) = 3 FROM pg_constraint
        WHERE conrelid = 'public.attendance_records'::REGCLASS
          AND conname IN (
              'attendance_records_notes_length_check',
              'attendance_records_late_reason_check',
              'attendance_records_mutation_id_check'
          )
    ), 'attendance content constraints are incomplete';
    ASSERT (
        SELECT rowsecurity FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'attendance_mutation_receipts'
    ), 'attendance mutation receipts are missing or lack RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'public.attendance_mutation_receipts', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.attendance_mutation_receipts', 'INSERT'
    ), 'attendance mutation receipts are exposed to authenticated clients';
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.attendance_records'::REGCLASS
          AND tgname = 'archive_attendance_mutation_receipt'
          AND NOT tgisinternal
    ), 'replaced attendance mutation IDs are not archived';
    ASSERT POSITION('attendance_mutation_is_replay' IN v_sync_attendance) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_sync_attendance) > 0
       AND POSITION('clock_timestamp()' IN v_sync_attendance) > 0,
        'offline attendance replay/idempotency enforcement drifted';
    ASSERT POSITION(
        'v_session_date < v_today - 7' IN LOWER(pg_get_functiondef(
            'public.check_session_not_ended()'::REGPROCEDURE
        ))
    ) > 0, 'offline sync can rewrite arbitrarily old open sessions';
    ASSERT POSITION('sub_tutor_id = auth.uid()' IN v_substitute_scope) > 0
       AND POSITION('asia/singapore' IN v_substitute_scope) > 0
       AND POSITION('::date - 7' IN v_substitute_scope) > 0,
        'substitute authorization is not actor/time bounded';
    ASSERT (
        SELECT LOWER(qual) LIKE '%substitute_covers_session%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'sessions'
          AND policyname = 'substitute_can_read_session'
    ), 'substitute session reads are not time bounded';
    ASSERT (
        SELECT LOWER(qual) LIKE '%substitute_covers_session%'
           AND LOWER(with_check) LIKE '%substitute_covers_session%'
           AND LOWER(with_check) LIKE '%student_is_enrolled_for_session%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'attendance_records'
          AND policyname = 'substitute_can_mark_attendance'
    ), 'substitute attendance access is unbounded or not class-enrollment bound';
    ASSERT POSITION('substitute_covers_session' IN v_get_my_classes) > 0
       AND POSITION('tutor_owns_class' IN v_get_my_classes) > 0
       AND POSITION('not c.is_study_space' IN v_get_my_classes) > 0
       AND POSITION('current_session.session_date = v_today' IN v_get_my_classes) > 0
       AND POSITION('can_operate_today_session' IN v_get_my_classes) > 0,
        'staff class projection lacks bounded scope or explicit capabilities';
    ASSERT POSITION('substitute_covers_session' IN v_get_roster) > 0
       AND POSITION('tutor_owns_class' IN v_get_roster) > 0
       AND POSITION('e.enrolled_at' IN v_get_roster) > 0
       AND POSITION('e.unenrolled_at' IN v_get_roster) > 0,
        'session roster lacks caller or historical-enrollment enforcement';
    ASSERT has_function_privilege(
        'authenticated', 'public.get_my_classes()', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.get_my_classes()', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'public.get_session_roster(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.get_session_roster(uuid)', 'EXECUTE'
    ), 'staff class/roster projection privileges drifted';
    ASSERT POSITION('clock_timestamp()' IN v_get_today_session) > 0
       AND POSITION('on conflict (class_id, session_date) do nothing' IN v_get_today_session) > 0
       AND POSITION('substitute_covers_session' IN v_get_today_session) > 0,
        'today-session discovery/creation lost server time or substitute scope';
    ASSERT POSITION('clock_timestamp()' IN v_session_lifecycle) > 0
       AND POSITION('ended sessions cannot be reopened' IN v_session_lifecycle) > 0
       AND POSITION('substitute_covers_session' IN v_session_lifecycle) > 0
       AND POSITION('app.session_lifecycle_write' IN v_session_lifecycle) > 0,
        'session lifecycle is not server-timed, immutable, or substitute scoped';
    ASSERT POSITION('app.session_lifecycle_write' IN v_session_lifecycle_guard) > 0
       AND POSITION('app.session_create_write' IN v_session_lifecycle_guard) > 0
       AND POSITION('app.retrospective_session_create' IN v_session_lifecycle_guard) > 0
       AND POSITION('session creation requires the dedicated workflow' IN v_session_lifecycle_guard) > 0
       AND EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgrelid = 'public.sessions'::REGCLASS
              AND tgname = 'enforce_session_lifecycle_boundary'
              AND NOT tgisinternal
       ), 'direct session lifecycle timestamp writes are not blocked';
    ASSERT POSITION('session identity fields are immutable' IN v_session_change_guard) > 0
       AND POSITION('new.created_at' IN v_session_change_guard) > 0
       AND POSITION('sessions cannot be deleted directly' IN v_session_change_guard) > 0,
        'direct session identity mutation or deletion is not blocked';
    ASSERT POSITION('session_notes' IN v_update_session_note) > 0
       AND POSITION('substitute_covers_session' IN v_update_session_note) > 0
       AND POSITION('[stfgm]' IN v_update_session_note) > 0
       AND POSITION('app.session_note_write' IN v_update_session_note) > 0,
        'session-note RPC lost feature, substitute, or identifier controls';
    ASSERT has_function_privilege(
        'authenticated', 'public.get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'public.set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'public.update_session_note(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.update_session_note(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.update_session_note(uuid,text)', 'EXECUTE'
    ), 'session lifecycle/note RPC privileges drifted';
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.sessions'::REGCLASS
          AND tgname = 'enforce_session_notes_feature_flag'
          AND NOT tgisinternal
    ) AND POSITION('char_length(new.notes) > 4000' IN v_session_notes_guard) > 0
      AND POSITION('app.session_note_write' IN v_session_notes_guard) > 0
      AND POSITION('[stfgm]' IN v_session_notes_guard) > 0,
        'session notes lack universal bounds or shaped-write enforcement';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.sessions'::REGCLASS
          AND conname = 'sessions_notes_length_check'
    ), 'legacy session notes could block unrelated session updates';

    ASSERT has_function_privilege(
        'authenticated',
        'public.review_correction_request(uuid,text,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon',
        'public.review_correction_request(uuid,text,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role',
        'public.review_correction_request(uuid,text,text)',
        'EXECUTE'
    ), 'correction-review RPC privileges drifted';
    ASSERT has_table_privilege(
        'authenticated', 'public.correction_requests', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'DELETE'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'TRUNCATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'REFERENCES'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.correction_requests', 'TRIGGER'
    ), 'authenticated clients can bypass atomic correction review';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: admin read'
          AND cmd = 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: admin full'
    ), 'correction queue policies permit a direct review bypass';
    ASSERT POSITION('for update' IN v_review_correction) > 0
       AND POSITION('is_admin() is distinct from true' IN v_review_correction) > 0
       AND POSITION('case v_request.field_name' IN v_review_correction) > 0
       AND POSITION('from students' IN v_review_correction) > 0
       AND POSITION('v_request.current_value' IN v_review_correction) > 0
       AND POSITION('correction request is stale' IN v_review_correction) > 0
       AND POSITION('reviewed_by = auth.uid()' IN v_review_correction) > 0
       AND POSITION('insert into data_disclosures' IN v_review_correction) > 0
       AND POSITION('''applied_value''' IN v_review_correction) = 0
       AND POSITION('''new_value''' IN v_review_correction) = 0
       AND POSITION('''field''' IN v_review_correction) = 0,
        'correction review permits stale writes or duplicates corrected personal data';

    ASSERT has_function_privilege(
        'authenticated',
        'public.record_admin_consent(uuid,text,text,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon',
        'public.record_admin_consent(uuid,text,text,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role',
        'public.record_admin_consent(uuid,text,text,text)',
        'EXECUTE'
    ), 'consent-recording RPC privileges drifted';
    ASSERT POSITION('is_admin() is distinct from true' IN v_record_consent) > 0
       AND POSITION('''admin_attestation''' IN v_record_consent) > 0
       AND POSITION('granted_by' IN v_record_consent) > 0
       AND POSITION('auth.uid()' IN v_record_consent) > 0
       AND POSITION('data_protection_notice' IN v_record_consent) > 0,
        'consent provenance is no longer derived server-side';
    ASSERT has_table_privilege(
        'authenticated', 'public.consent_records', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.consent_records', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.consent_records', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.consent_records', 'DELETE'
    ), 'authenticated clients can forge or mutate consent evidence';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'consent_records'
          AND policyname = 'consent_records: admin read'
          AND cmd = 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'consent_records'
          AND policyname = 'consent_records: admin full'
    ), 'consent-record policies permit a provenance bypass';

    ASSERT has_table_privilege(
        'authenticated', 'public.data_disclosures', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.data_disclosures', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.data_disclosures', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.data_disclosures', 'DELETE'
    ), 'authenticated clients can forge or mutate disclosure evidence';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'data_disclosures'
          AND policyname = 'data_disclosures: admin read'
          AND cmd = 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'data_disclosures'
          AND policyname IN (
              'data_disclosures: admin insert',
              'data_disclosures: admin only'
          )
    ), 'disclosure policies permit direct evidence forgery';

    ASSERT has_function_privilege(
        'service_role', 'public.consume_invite_rate_limit(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'authenticated', 'public.consume_invite_rate_limit(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.consume_invite_rate_limit(uuid)', 'EXECUTE'
    ), 'invite quota RPC privileges drifted';
    ASSERT POSITION('pg_advisory_xact_lock' IN v_consume_invite) > 0
       AND POSITION('role = ''admin''' IN v_consume_invite) > 0
       AND POSITION('count(*)' IN v_consume_invite) > 0
       AND POSITION('insert into rate_limit_events' IN v_consume_invite) > 0,
        'invite quota consumption is not atomic or actor-bound';

    ASSERT has_function_privilege(
        'authenticated', 'public.submit_app_events(jsonb)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.submit_app_events(jsonb)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.submit_app_events(jsonb)', 'EXECUTE'
    ), 'analytics ingestion RPC privileges drifted';
    ASSERT POSITION('is_feature_enabled(''analytics'')' IN v_submit_events) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_submit_events) > 0
       AND POSITION('clock_timestamp()' IN v_submit_events) > 0
       AND POSITION('auth.uid()' IN v_submit_events) > 0
       AND POSITION('octet_length(v_properties::text) > 4096' IN v_submit_events) > 0,
        'analytics ingestion lost feature, provenance, size, or quota controls';
    ASSERT NOT has_table_privilege(
        'authenticated', 'public.app_events', 'INSERT'
    ) AND has_table_privilege(
        'authenticated', 'public.app_events', 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'app_events'
          AND policyname = 'app_events: authenticated insert own'
    ), 'authenticated clients can bypass shaped analytics ingestion';

    ASSERT has_function_privilege(
        'authenticated', 'public.register_device_token(text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'public.register_device_token(text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.register_device_token(text,text)', 'EXECUTE'
    ), 'device-token registration RPC privileges drifted';
    ASSERT POSITION('is_parent()' IN v_register_token) > 0
       AND POSITION('push_notifications' IN v_register_token) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_register_token) > 0
       AND POSITION('offset 5' IN v_register_token) > 0,
        'device-token registration lost role, feature, or count limits';
    ASSERT NOT has_table_privilege(
        'authenticated', 'public.device_tokens', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.device_tokens', 'INSERT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'device_tokens'
          AND policyname = 'device_tokens: owner manages own'
    ), 'authenticated clients can directly amplify push fan-out';

    ASSERT (
        SELECT rowsecurity FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'result_slip_upload_intents'
    ), 'result-slip upload intents lack RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'public.result_slip_upload_intents', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.result_slip_upload_intents', 'INSERT'
    ), 'authenticated clients can access result-slip upload intents';
    ASSERT NOT has_function_privilege(
        'authenticated',
        'public.reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'authenticated',
        'public.finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    ), 'authenticated clients can mint or finalize signed uploads';
    ASSERT has_function_privilege(
        'service_role',
        'public.reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    ) AND has_function_privilege(
        'service_role',
        'public.finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    ), 'service-role result-slip workflow is unavailable';
    ASSERT POSITION('for update' IN v_finalize_upload) > 0
       AND POSITION('cleanup_claimed_at is null' IN v_finalize_upload) > 0
       AND POSITION('update result_slip_upload_intents' IN v_finalize_upload) > 0
       AND POSITION('finalized_result_id' IN v_finalize_upload) > 0
       AND POSITION('finalized_at' IN v_finalize_upload) > 0,
        'result-slip token tombstone is not retained atomically';
    ASSERT (
        SELECT COUNT(*) = 3
        FROM pg_constraint
        WHERE conrelid = 'public.result_slip_upload_intents'::REGCLASS
          AND contype = 'f'
          AND LOWER(pg_get_constraintdef(oid)) LIKE '%on delete set null%'
    ), 'identity/result deletion can discard a live signed-upload cleanup tombstone';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: parent upload own child'
    ), 'direct parent Storage uploads are enabled';

    ASSERT (
        SELECT public = FALSE
           AND file_size_limit = 10485760
           AND allowed_mime_types @> ARRAY[
               'application/pdf', 'image/jpeg', 'image/png'
           ]::TEXT[]
           AND allowed_mime_types <@ ARRAY[
               'application/pdf', 'image/jpeg', 'image/png'
           ]::TEXT[]
        FROM storage.buckets WHERE id = 'result-slips'
    ), 'result-slips bucket is public or has unsafe type/size limits';
    ASSERT (
        SELECT public = FALSE
           AND file_size_limit = 5242880
           AND allowed_mime_types @> ARRAY['image/jpeg', 'image/png']::TEXT[]
           AND allowed_mime_types <@ ARRAY['image/jpeg', 'image/png']::TEXT[]
        FROM storage.buckets WHERE id = 'student-photos'
    ), 'student-photos bucket is public or has unsafe type/size limits';
    ASSERT (
        SELECT LOWER(with_check) LIKE '%student_photos%'
           AND LOWER(with_check) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: admin all'
    ), 'admin student-photo writes ignore flag or canonical paths';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: parent read'
    ), 'parent clients can enumerate student-photo Storage metadata';
    ASSERT (
        SELECT LOWER(qual) LIKE '%tutor_owns_class%'
           AND LOWER(qual) LIKE '%substitute_covers_session%'
           AND LOWER(qual) LIKE '%e.enrolled_at%'
           AND LOWER(qual) LIKE '%e.unenrolled_at%'
           AND LOWER(qual) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: tutor read'
    ), 'tutor student-photo reads ignore assignment/substitute/path boundaries';
    ASSERT (
        SELECT LOWER(with_check) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: admin all'
    ), 'admin result-slip writes ignore canonical paths';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: parent read'
    ), 'parent clients can enumerate result-slip Storage metadata';

    ASSERT (
        SELECT rowsecurity FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'student_storage_cleanup_queue'
    ), 'student Storage cleanup queue lacks RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'public.student_storage_cleanup_queue', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.student_storage_cleanup_queue', 'INSERT'
    ), 'authenticated clients can access the Storage cleanup queue';
    ASSERT NOT has_function_privilege(
        'authenticated', 'public.invoke_student_storage_cleanup()', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'public.invoke_student_storage_cleanup()', 'EXECUTE'
    ), 'cleanup invoker is exposed through the Data API';
    ASSERT POSITION('storage_cleanup_invoke_secret' IN v_cleanup_invoker) > 0
       AND POSITION('missing or invalid' IN v_cleanup_invoker) > 0
       AND POSITION('timeout_milliseconds := 120000' IN v_cleanup_invoker) > 0,
        'cleanup invocation secret/timeout drifted';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'students'
          AND policyname = 'students: direct delete denied'
          AND permissive = 'RESTRICTIVE'
          AND cmd = 'DELETE'
          AND LOWER(qual) LIKE '%false%'
    ), 'authenticated admins can bypass Storage-aware student erasure';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'result_slips'
          AND policyname = 'result_slips: direct delete denied'
          AND permissive = 'RESTRICTIVE'
          AND cmd = 'DELETE'
          AND LOWER(qual) LIKE '%false%'
    ), 'authenticated admins can orphan result-slip Storage objects';

    ASSERT POSITION('notify_parent_invoke_secret' IN v_notify_attendance) > 0
       AND POSITION('authorization' IN v_notify_attendance) = 0
       AND POSITION('old.status is not distinct from new.status' IN v_notify_attendance) > 0
       AND POSITION('new.status not in (''late'', ''absent'')' IN v_notify_attendance) > 0
       AND POSITION('timeout_milliseconds := 30000' IN v_notify_attendance) > 0,
        'attendance notification credential, dedupe, status gate, or timeout drifted';
    ASSERT POSITION('notify_parent_invoke_secret' IN v_notify_dismissal) > 0
       AND POSITION('authorization' IN v_notify_dismissal) = 0
       AND POSITION('timeout_milliseconds := 30000' IN v_notify_dismissal) > 0,
        'dismissal notification transmits broad credentials or has an unsafe timeout';

    ASSERT NOT has_table_privilege(
        'authenticated', 'public.security_principals', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'public.security_principals', 'UPDATE'
    ), 'security-principal mapping is exposed';
    ASSERT (
        SELECT COUNT(*) = 1
        FROM public.security_principals sp
        JOIN public.profiles p ON p.id = sp.user_id
        WHERE sp.capability = 'superadmin' AND p.role = 'admin'
    ), 'production has no valid DB-bound superadmin principal';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'feature_flags'
          AND policyname = 'feature_flags: superadmin writes'
          AND LOWER(qual) LIKE '%is_superadmin%'
          AND LOWER(with_check) LIKE '%is_superadmin%'
    ), 'ordinary admins can mutate security feature flags';
    ASSERT has_table_privilege(
        'authenticated', 'public.feature_flags', 'UPDATE'
    ), 'authenticated lacks feature_flags UPDATE privilege required by superadmin UI';
    ASSERT has_table_privilege(
        'authenticated', 'public.enrollments', 'SELECT'
    ) AND has_table_privilege(
        'authenticated', 'public.class_tutor_assignments', 'SELECT'
    ), 'tutor RLS policy dependencies lack authenticated SELECT privileges';
    ASSERT has_table_privilege(
        'authenticated', 'public.students', 'SELECT'
    ), 'students RLS boundary lacks authenticated SELECT privilege';
    ASSERT has_table_privilege(
        'authenticated', 'public.sessions', 'SELECT'
    ) AND has_table_privilege(
        'authenticated', 'public.sessions', 'UPDATE'
    ), 'session RLS boundary lacks authenticated SELECT/UPDATE privileges';

    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND (
              (tablename = 'students'
               AND policyname = 'students: parent can read own children')
              OR (tablename = 'classes'
                  AND policyname = 'classes: parent reads children''s classes')
              OR (tablename = 'enrollments'
                  AND policyname = 'enrollments: parent reads own children')
              OR (tablename = 'sessions'
                  AND policyname = 'sessions: parent reads children''s sessions')
              OR (tablename = 'attendance_records'
                  AND policyname = 'attendance_records: parent reads own children')
              OR (tablename = 'result_slips'
                  AND policyname IN (
                      'result_slips: parent reads own child',
                      'result_slips: parent uploads own child'
                  ))
              OR (tablename = 'messages'
                  AND policyname IN (
                      'messages: participant reads own',
                      'messages: parent sends about own child'
                  ))
              OR (tablename = 'dismissals'
                  AND policyname = 'dismissals: parent reads own child')
              OR (tablename = 'consent_records'
                  AND policyname = 'consent_records: parent reads own child')
              OR (tablename = 'correction_requests'
                  AND policyname IN (
                      'correction_requests: parent reads own child',
                      'correction_requests: parent creates own child'
                  ))
              OR (tablename = 'awards'
                  AND policyname = 'awards: parent reads own child')
          )
    ), 'parent base-table policies expose staff/compliance fields';
    ASSERT (
        SELECT COUNT(*) = 8
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'get_parent_children',
              'get_parent_attendance_history',
              'get_parent_attendance_summary',
              'get_parent_result_slips',
              'get_parent_messages',
              'get_parent_dismissals',
              'submit_parent_result_slip',
              'send_parent_message'
          )
          AND p.prosecdef
    ), 'parent-safe projection RPCs are missing';

    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        ASSERT EXISTS (
            SELECT 1 FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
              AND schedule = '*/15 * * * *'
              AND active
        ), 'student Storage cleanup cron is missing or inactive';
    END IF;
END;
$$;

ROLLBACK;
