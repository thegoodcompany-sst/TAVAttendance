-- Included inside each test transaction; never installed in application migrations.
CREATE FUNCTION pg_temp.ok(value boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %',label; END IF; RAISE NOTICE 'PASS %',label; END $$;
CREATE FUNCTION pg_temp.throws(statement text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE caught boolean:=false; msg text;
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN caught:=true; GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
 IF msg<>expected AND SQLSTATE<>expected THEN RAISE EXCEPTION 'FAIL %: expected %, got % (%)',label,expected,msg,SQLSTATE; END IF;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'FAIL %: no exception',label; END IF;
 RAISE NOTICE 'PASS %',label;
END $$;
CREATE FUNCTION pg_temp.claims(uid text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','service_role','user_metadata',jsonb_build_object('role','admin'))::text,true)::text IS NOT NULL; $$;
CREATE FUNCTION pg_temp.fixture(label text,st timestamptz,en timestamptz,teacher uuid DEFAULT '10000000-0000-4000-8000-000000000011',members int DEFAULT 2) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE cid uuid; lid uuid;
BEGIN
 INSERT INTO public.classes(short_label,subject) VALUES(label,'Demo') RETURNING id INTO cid;
 INSERT INTO public.lessons(class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at) VALUES(cid,(st AT TIME ZONE 'Asia/Singapore')::date,st,en,teacher,en+interval '75 minutes') RETURNING id INTO lid;
 INSERT INTO public.lesson_staff VALUES(lid,teacher,'regular');
 INSERT INTO public.lesson_roster(lesson_id,student_id) SELECT lid,id FROM public.students ORDER BY id LIMIT members;
 RETURN lid;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean,text),pg_temp.throws(text,text,text),pg_temp.claims(text) TO authenticated,anon,service_role;
