
-- =========================================
-- TASKFLOW: BUSINESS RULE ENFORCEMENT
-- =========================================

-- -----------------------------------------
-- 1. VALIDATE PROJECT MEMBERS
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_project_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = NEW.worker_id
          AND role = 'worker'
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Only active workers can join projects.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_project_member_trigger
BEFORE INSERT OR UPDATE ON public.project_members
FOR EACH ROW
EXECUTE FUNCTION private.validate_project_member();


-- -----------------------------------------
-- 2. VALIDATE TASK ASSIGNMENTS
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_task_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.assigned_to IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.profiles p
        JOIN public.project_members pm
          ON pm.worker_id = p.id
        WHERE p.id = NEW.assigned_to
          AND p.role = 'worker'
          AND p.status = 'active'
          AND pm.project_id = NEW.project_id
          AND pm.membership_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Task must be assigned to an active project worker.';
    END IF;

    IF NEW.status = 'completed'
       AND NOT EXISTS (
           SELECT 1
           FROM public.submissions s
           WHERE s.task_id = NEW.id
             AND s.status = 'approved'
       ) THEN
        RAISE EXCEPTION 'A task requires an approved submission before completion.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_task_assignment_trigger
BEFORE INSERT OR UPDATE ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION private.validate_task_assignment();


-- -----------------------------------------
-- 3. SECURE TIME TRACKING
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_time_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN

        IF auth.uid() IS NULL THEN
            RAISE EXCEPTION 'Authentication required.';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.tasks t
            JOIN public.project_members pm
              ON pm.project_id = t.project_id
            WHERE t.id = NEW.task_id
              AND t.assigned_to = auth.uid()
              AND pm.worker_id = auth.uid()
              AND pm.membership_status = 'active'
        ) THEN
            RAISE EXCEPTION 'You are not assigned to this task.';
        END IF;

        NEW.worker_id := auth.uid();
        NEW.started_at := clock_timestamp();
        NEW.ended_at := NULL;

    ELSE

        IF OLD.worker_id <> auth.uid() THEN
            RAISE EXCEPTION 'You cannot modify another worker''s timer.';
        END IF;

        IF OLD.ended_at IS NOT NULL THEN
            RAISE EXCEPTION 'This timer has already stopped.';
        END IF;

        IF NEW.task_id <> OLD.task_id
           OR NEW.worker_id <> OLD.worker_id
           OR NEW.started_at <> OLD.started_at THEN
            RAISE EXCEPTION 'Timer identity and start time cannot be changed.';
        END IF;

        IF NEW.ended_at IS NOT NULL THEN
            NEW.ended_at := clock_timestamp();
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_time_log_trigger
BEFORE INSERT OR UPDATE ON public.time_logs
FOR EACH ROW
EXECUTE FUNCTION private.validate_time_log();


-- -----------------------------------------
-- 4. SECURE SUBMISSIONS AND VERSIONS
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    next_version INTEGER;
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF auth.uid() IS NULL THEN
            RAISE EXCEPTION 'Authentication required.';
        END IF;

        -- Lock the task to prevent simultaneous
        -- submissions from receiving the same version.
        PERFORM 1
        FROM public.tasks
        WHERE id = NEW.task_id
          AND assigned_to = auth.uid()
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'You are not assigned to this task.';
        END IF;

        SELECT COALESCE(MAX(version), 0) + 1
        INTO next_version
        FROM public.submissions
        WHERE task_id = NEW.task_id
          AND worker_id = auth.uid();

        NEW.worker_id := auth.uid();
        NEW.version := next_version;
        NEW.status := 'pending';
        NEW.reviewed_by := NULL;
        NEW.reviewed_at := NULL;
        NEW.submitted_at := clock_timestamp();

    ELSE

        IF OLD.status <> 'pending' THEN
            RAISE EXCEPTION 'This submission has already been reviewed.';
        END IF;

        IF NEW.task_id <> OLD.task_id
           OR NEW.worker_id <> OLD.worker_id
           OR NEW.version <> OLD.version
           OR NEW.description IS DISTINCT FROM OLD.description
           OR NEW.file_path IS DISTINCT FROM OLD.file_path
           OR NEW.submitted_at <> OLD.submitted_at THEN
            RAISE EXCEPTION 'Submission details cannot be changed after submission.';
        END IF;

        IF NEW.status NOT IN ('approved', 'revision') THEN
            RAISE EXCEPTION 'Invalid submission review status.';
        END IF;

        IF auth.uid() = OLD.worker_id THEN
            RAISE EXCEPTION 'Workers cannot approve their own submissions.';
        END IF;

        IF NOT (
            private.is_admin()
            OR private.owns_project(
                (SELECT project_id
                 FROM public.tasks
                 WHERE id = OLD.task_id)
            )
        ) THEN
            RAISE EXCEPTION 'You cannot review this submission.';
        END IF;

        NEW.reviewed_by := auth.uid();
        IF NEW.status = 'revision'
        AND NULLIF(BTRIM(NEW.review_feedback), '') IS NULL THEN
            RAISE EXCEPTION 'A revision request must include feedback.';
        END IF;
        NEW.reviewed_at := clock_timestamp();

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_submission_trigger
BEFORE INSERT OR UPDATE ON public.submissions
FOR EACH ROW
EXECUTE FUNCTION private.validate_submission();


-- -----------------------------------------
-- 5. UPDATE TASK AFTER SUBMISSION REVIEW
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.update_task_after_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.status = 'approved' THEN
        UPDATE public.tasks
        SET status = 'completed'
        WHERE id = NEW.task_id;

    ELSIF NEW.status = 'revision' THEN
        UPDATE public.tasks
        SET status = 'revision'
        WHERE id = NEW.task_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER update_task_after_review_trigger
AFTER UPDATE OF status ON public.submissions
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION private.update_task_after_review();


-- -----------------------------------------
-- 6. SECURE TIMESHEETS
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_timesheet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.worker_id <> auth.uid()
           OR NOT private.is_project_member(NEW.project_id) THEN
            RAISE EXCEPTION 'You cannot create this timesheet.';
        END IF;

        NEW.status := 'draft';
        NEW.submitted_at := NULL;
        NEW.reviewed_by := NULL;
        NEW.reviewed_at := NULL;

    ELSE

        IF OLD.worker_id = auth.uid() THEN

            IF OLD.status NOT IN ('draft', 'revision')
               OR NEW.status <> 'submitted' THEN
                RAISE EXCEPTION 'Invalid worker timesheet action.';
            END IF;

            IF NEW.worker_id <> OLD.worker_id
               OR NEW.project_id <> OLD.project_id
               OR NEW.period_start <> OLD.period_start
               OR NEW.period_end <> OLD.period_end
               OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
               OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at THEN
                RAISE EXCEPTION 'Workers cannot modify reviewed timesheet details.';
            END IF;

            NEW.submitted_at := clock_timestamp();

            NEW.review_feedback := NULL;
            NEW.reviewed_by := NULL;
            NEW.reviewed_at := NULL;

        ELSE

            IF OLD.status <> 'submitted'
               OR NEW.status NOT IN ('approved', 'revision') THEN
                RAISE EXCEPTION 'Invalid timesheet review action.';
            END IF;

            IF NEW.worker_id <> OLD.worker_id
               OR NEW.project_id <> OLD.project_id
               OR NEW.period_start <> OLD.period_start
               OR NEW.period_end <> OLD.period_end
               OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at THEN
                RAISE EXCEPTION 'Timesheet details cannot be changed during review.';
            END IF;

            IF auth.uid() = OLD.worker_id THEN
                RAISE EXCEPTION 'Workers cannot approve their own timesheets.';
            END IF;

            IF NOT (
                private.is_admin()
                OR private.owns_project(OLD.project_id)
            ) THEN
                RAISE EXCEPTION 'You cannot review this timesheet.';
            END IF;

            NEW.reviewed_by := auth.uid();
            IF NEW.status = 'revision'
            AND NULLIF(BTRIM(NEW.review_feedback), '') IS NULL THEN
                RAISE EXCEPTION 'A revision request must include feedback.';
            END IF;
            NEW.reviewed_at := clock_timestamp();

        END IF;

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_timesheet_trigger
BEFORE INSERT OR UPDATE ON public.timesheets
FOR EACH ROW
EXECUTE FUNCTION private.validate_timesheet();


-- -----------------------------------------
-- 7. VALIDATE TIMESHEET ENTRIES
-- -----------------------------------------

CREATE OR REPLACE FUNCTION private.validate_timesheet_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.timesheets ts
        JOIN public.time_logs tl
          ON tl.id = NEW.time_log_id
        JOIN public.tasks t
          ON t.id = tl.task_id
        WHERE ts.id = NEW.timesheet_id
          AND ts.worker_id = auth.uid()
          AND ts.status = 'draft'
          AND tl.worker_id = auth.uid()
          AND tl.ended_at IS NOT NULL
          AND t.project_id = ts.project_id
    ) THEN
        RAISE EXCEPTION 'This time log cannot be added to this timesheet.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER validate_timesheet_entry_trigger
BEFORE INSERT ON public.timesheet_entries
FOR EACH ROW
EXECUTE FUNCTION private.validate_timesheet_entry();


-- -----------------------------------------
-- 8. RESTRICT DIRECT EXECUTION
-- -----------------------------------------

REVOKE ALL ON FUNCTION private.validate_project_member() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.validate_task_assignment() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.validate_time_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.validate_submission() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.update_task_after_review() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.validate_timesheet() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.validate_timesheet_entry() FROM PUBLIC;
