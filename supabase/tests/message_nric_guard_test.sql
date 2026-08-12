-- Behaviour checks for migration 057 (NRIC/FIN rejected in messages).
-- Plain SQL + ASSERT, one transaction, ROLLBACK at the end.
--
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/message_nric_guard_test.sql
BEGIN;

DO $$
DECLARE
    v_fn TEXT;
    v_ok BOOLEAN := FALSE;
BEGIN
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.messages'::REGCLASS
          AND tgname = 'trg_reject_nric_messages'
    ), 'trg_reject_nric_messages is missing';

    v_fn := LOWER(pg_get_functiondef(
        'public.send_parent_message(uuid,text,text)'::REGPROCEDURE
    ));
    ASSERT POSITION('nric/fin' IN v_fn) > 0,
           'send_parent_message does not mention NRIC/FIN';

    BEGIN
        INSERT INTO messages (sender_id, student_id, subject, body)
        VALUES (
            '00000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000001',
            'Update',
            'Please note S1234567A on file'
        );
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            v_ok := TRUE;
    END;
    ASSERT v_ok, 'message body with NRIC/FIN was accepted';

    v_ok := FALSE;
    BEGIN
        INSERT INTO messages (sender_id, student_id, subject, body)
        VALUES (
            '00000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000001',
            'Re S1234567A',
            'Can we talk after class?'
        );
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            v_ok := TRUE;
    END;
    ASSERT v_ok, 'message subject with NRIC/FIN was accepted';

    INSERT INTO messages (sender_id, student_id, subject, body)
    VALUES (
        '00000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001',
        'Pickup',
        'We will be 10 minutes late tonight.'
    );

    RAISE NOTICE 'message_nric_guard_test: all assertions passed';
END;
$$;

ROLLBACK;
