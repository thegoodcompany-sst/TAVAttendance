-- Reverse 061: restores the previous nullable checks and aggregate gate.
-- This reintroduces the missing-profile bypass; use only for an intentional rollback.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT public.get_my_role() = 'admin'
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_tutor()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT public.get_my_role() = 'tutor'
$$;

REVOKE EXECUTE ON FUNCTION public.is_tutor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_tutor() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_parent()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT public.get_my_role() = 'parent'
$$;

REVOKE EXECUTE ON FUNCTION public.is_parent() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_parent() TO authenticated, service_role;

-- Migration 059 is held in production. Do not provision any NFC objects here.
-- Reapply 061 after a future 059 deployment, which defines the old predicate.
DO $migration$
BEGIN
    IF to_regprocedure('public.is_arrival_station()') IS NOT NULL THEN
        EXECUTE $definition$
CREATE OR REPLACE FUNCTION public.is_arrival_station()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT public.get_my_role() = 'arrival_station'
$$;

REVOKE EXECUTE ON FUNCTION public.is_arrival_station() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_arrival_station() TO authenticated, service_role;
        $definition$;
    END IF;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.class_punctuality(
    p_class_id UUID, p_from DATE, p_to DATE
)
RETURNS TABLE (
    present_count BIGINT, late_count BIGINT, absent_count BIGINT,
    total_count BIGINT, on_time_rate NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT (is_admin() OR tutor_owns_class(p_class_id))
       OR NOT EXISTS (
            SELECT 1 FROM classes c
            WHERE c.id = p_class_id AND c.is_study_space = FALSE
       ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT COUNT(*) FILTER (WHERE ar.status = 'present'),
           COUNT(*) FILTER (WHERE ar.status = 'late'),
           COUNT(*) FILTER (WHERE ar.status = 'absent'),
           COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN NULL
                ELSE ROUND(
                    COUNT(*) FILTER (WHERE ar.status = 'present')::NUMERIC
                    / COUNT(*),
                    4
                )
           END
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    WHERE s.class_id = p_class_id
      AND s.session_date BETWEEN p_from AND p_to;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.class_punctuality(UUID, DATE, DATE)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.class_punctuality(UUID, DATE, DATE)
    TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_app_events(p_events JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_event JSONB;
    v_properties JSONB;
    v_count INTEGER;
    v_recent BIGINT;
    v_role TEXT;
    v_platform TEXT;
    v_event_type TEXT;
    v_session_id TEXT;
    v_name TEXT;
    v_app_version TEXT;
    v_device TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF NOT is_feature_enabled('analytics') THEN
        RETURN 0;
    END IF;
    IF jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'analytics payload must be an array'
            USING ERRCODE = '22023';
    END IF;

    v_count := jsonb_array_length(p_events);
    IF v_count = 0 THEN RETURN 0; END IF;
    IF v_count > 100 OR octet_length(p_events::TEXT) > 131072 THEN
        RAISE EXCEPTION 'analytics batch is too large' USING ERRCODE = '22023';
    END IF;

    SELECT p.role INTO v_role FROM profiles p WHERE p.id = auth.uid();
    IF v_role NOT IN ('admin', 'tutor', 'parent') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 6));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'analytics_event'
      AND created_at < NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'analytics_event'
      AND created_at >= NOW() - INTERVAL '1 hour';
    IF v_recent + v_count > 1000 THEN
        RAISE EXCEPTION 'analytics rate limit reached' USING ERRCODE = '54000';
    END IF;

    FOR v_event IN SELECT value FROM jsonb_array_elements(p_events)
    LOOP
        IF jsonb_typeof(v_event) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'invalid analytics event' USING ERRCODE = '22023';
        END IF;

        v_platform := LOWER(BTRIM(COALESCE(v_event->>'platform', '')));
        v_event_type := LOWER(BTRIM(COALESCE(v_event->>'event_type', '')));
        v_session_id := BTRIM(COALESCE(v_event->>'session_id', ''));
        v_name := BTRIM(COALESCE(v_event->>'name', ''));
        v_app_version := NULLIF(BTRIM(v_event->>'app_version'), '');
        v_device := NULLIF(BTRIM(v_event->>'device'), '');
        v_properties := COALESCE(v_event->'properties', '{}'::JSONB);

        IF v_platform NOT IN ('ios', 'android', 'web')
           OR v_event_type NOT IN (
                'screen_view', 'tap', 'error', 'crash', 'ops', 'latency'
           )
           OR char_length(v_session_id) NOT BETWEEN 1 AND 128
           OR char_length(v_name) NOT BETWEEN 1 AND 200
           OR (v_app_version IS NOT NULL AND char_length(v_app_version) > 64)
           OR (v_device IS NOT NULL AND char_length(v_device) > 200)
           OR jsonb_typeof(v_properties) IS DISTINCT FROM 'object'
           OR octet_length(v_properties::TEXT) > 4096 THEN
            RAISE EXCEPTION 'invalid analytics event' USING ERRCODE = '22023';
        END IF;
        IF (v_name || ' ' || v_session_id || ' ' || v_properties::TEXT) ~*
               '\m[STFGM][0-9]{7}[A-Z]\M'
           OR (v_name || ' ' || v_session_id || ' ' || v_properties::TEXT) ~*
               '[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}' THEN
            RAISE EXCEPTION 'analytics event appears to contain personal data'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO app_events (
            occurred_at, user_id, role, platform, app_version, session_id,
            event_type, name, properties, device
        ) VALUES (
            clock_timestamp(), auth.uid(), v_role, v_platform, v_app_version,
            v_session_id, v_event_type, v_name, v_properties, v_device
        );
    END LOOP;

    INSERT INTO rate_limit_events (actor_id, action)
    SELECT auth.uid(), 'analytics_event'
    FROM generate_series(1, v_count);
    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_app_events(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_app_events(JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
