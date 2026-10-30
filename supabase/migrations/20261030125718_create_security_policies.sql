-- =========================================
-- TASKFLOW: SECURITY HELPER FUNCTIONS
-- =========================================

CREATE OR REPLACE FUNCTION private.current_user_role()
RETURNS TEXT
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT role
    FROM public.profiles
    WHERE id = auth.uid()
      AND status = 'active';
$$;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(private.current_user_role() = 'admin', FALSE);
$$;

CREATE OR REPLACE FUNCTION private.owns_project(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.projects
        WHERE id = p_project_id
          AND client_id = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION private.is_project_member(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.project_members
        WHERE project_id = p_project_id
          AND worker_id = auth.uid()
          AND membership_status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION private.is_assigned_task(p_task_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks t
        JOIN public.project_members pm
          ON pm.project_id = t.project_id
        WHERE t.id = p_task_id
          AND t.assigned_to = auth.uid()
          AND pm.worker_id = auth.uid()
          AND pm.membership_status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION private.can_access_task(p_task_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT
        private.is_admin()
        OR EXISTS (
            SELECT 1
            FROM public.tasks t
            WHERE t.id = p_task_id
              AND (
                  private.owns_project(t.project_id)
                  OR private.is_assigned_task(t.id)
              )
        );
$$;

-- Allow authenticated users to use these internal helpers
GRANT USAGE ON SCHEMA private TO authenticated;

GRANT EXECUTE ON FUNCTION private.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.owns_project(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_project_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_assigned_task(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_access_task(UUID) TO authenticated;


-- =========================================
-- PROFILES POLICIES
-- =========================================

CREATE POLICY "Users can view own profile"
ON public.profiles
FOR SELECT TO authenticated
USING (id = auth.uid() OR private.is_admin());

CREATE POLICY "Users can update own profile"
ON public.profiles
FOR UPDATE TO authenticated
USING (id = auth.uid() OR private.is_admin())
WITH CHECK (id = auth.uid() OR private.is_admin());

-- Prevent users from changing their own role or status
REVOKE UPDATE ON public.profiles FROM authenticated;
GRANT UPDATE (full_name, avatar_url)
ON public.profiles TO authenticated;


-- =========================================
-- PROJECT POLICIES
-- =========================================

CREATE POLICY "Project access"
ON public.projects
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR private.owns_project(id)
    OR private.is_project_member(id)
);

CREATE POLICY "Clients can create projects"
ON public.projects
FOR INSERT TO authenticated
WITH CHECK (
    client_id = auth.uid()
    AND private.current_user_role() = 'client'
);

CREATE POLICY "Clients can update own projects"
ON public.projects
FOR UPDATE TO authenticated
USING (private.is_admin() OR private.owns_project(id))
WITH CHECK (private.is_admin() OR private.owns_project(id));

CREATE POLICY "Clients can delete own projects"
ON public.projects
FOR DELETE TO authenticated
USING (private.is_admin() OR private.owns_project(id));


-- =========================================
-- PROJECT MEMBERS POLICIES
-- =========================================

CREATE POLICY "Project members can view memberships"
ON public.project_members
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR worker_id = auth.uid()
    OR private.owns_project(project_id)
);

CREATE POLICY "Clients can add project members"
ON public.project_members
FOR INSERT TO authenticated
WITH CHECK (
    private.is_admin()
    OR private.owns_project(project_id)
);

CREATE POLICY "Clients can remove project members"
ON public.project_members
FOR DELETE TO authenticated
USING (
    private.is_admin()
    OR private.owns_project(project_id)
);


-- =========================================
-- TASK POLICIES
-- =========================================

CREATE POLICY "Users can view authorized tasks"
ON public.tasks
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR private.owns_project(project_id)
    OR assigned_to = auth.uid()
);

CREATE POLICY "Clients can create tasks"
ON public.tasks
FOR INSERT TO authenticated
WITH CHECK (
    private.is_admin()
    OR private.owns_project(project_id)
);

CREATE POLICY "Clients can update tasks"
ON public.tasks
FOR UPDATE TO authenticated
USING (private.is_admin() OR private.owns_project(project_id))
WITH CHECK (private.is_admin() OR private.owns_project(project_id));

CREATE POLICY "Clients can delete tasks"
ON public.tasks
FOR DELETE TO authenticated
USING (private.is_admin() OR private.owns_project(project_id));


-- =========================================
-- TIME LOG POLICIES
-- =========================================

CREATE POLICY "Users can view authorized time logs"
ON public.time_logs
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR worker_id = auth.uid()
    OR private.can_access_task(task_id)
);

CREATE POLICY "Workers can start timers"
ON public.time_logs
FOR INSERT TO authenticated
WITH CHECK (
    worker_id = auth.uid()
    AND ended_at IS NULL
    AND private.is_assigned_task(task_id)
);

CREATE POLICY "Workers can stop own timers"
ON public.time_logs
FOR UPDATE TO authenticated
USING (
    worker_id = auth.uid()
    AND ended_at IS NULL
)
WITH CHECK (
    worker_id = auth.uid()
    AND private.is_assigned_task(task_id)
);

REVOKE UPDATE ON public.time_logs FROM authenticated;
GRANT UPDATE (ended_at, notes)
ON public.time_logs TO authenticated;


-- =========================================
-- SUBMISSION POLICIES
-- =========================================

CREATE POLICY "Users can view authorized submissions"
ON public.submissions
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR worker_id = auth.uid()
    OR private.can_access_task(task_id)
);

CREATE POLICY "Workers can submit deliverables"
ON public.submissions
FOR INSERT TO authenticated
WITH CHECK (
    worker_id = auth.uid()
    AND status = 'pending'
    AND private.is_assigned_task(task_id)
);

CREATE POLICY "Clients can review submissions"
ON public.submissions
FOR UPDATE TO authenticated
USING (
    private.is_admin()
    OR (
        private.owns_project(
            (SELECT project_id FROM public.tasks WHERE id = task_id)
        )
    )
)
WITH CHECK (
    private.is_admin()
    OR private.owns_project(
        (SELECT project_id FROM public.tasks WHERE id = task_id)
    )
);

REVOKE UPDATE ON public.submissions FROM authenticated;
GRANT UPDATE (status, review_feedback, reviewed_by, reviewed_at)
ON public.submissions TO authenticated;


-- =========================================
-- TIMESHEET POLICIES
-- =========================================

CREATE POLICY "Users can view authorized timesheets"
ON public.timesheets
FOR SELECT TO authenticated
USING (
    private.is_admin()
    OR worker_id = auth.uid()
    OR private.owns_project(project_id)
);

CREATE POLICY "Workers can create timesheets"
ON public.timesheets
FOR INSERT TO authenticated
WITH CHECK (
    worker_id = auth.uid()
    AND private.is_project_member(project_id)
);

CREATE POLICY "Workers can update own timesheets"
ON public.timesheets
FOR UPDATE TO authenticated
USING (
    worker_id = auth.uid()
    AND status IN ('draft', 'revision')
)
WITH CHECK (
    worker_id = auth.uid()
    AND status IN ('draft', 'submitted', 'revision')
);

CREATE POLICY "Clients can review timesheets"
ON public.timesheets
FOR UPDATE TO authenticated
USING (
    private.is_admin()
    OR private.owns_project(project_id)
)
WITH CHECK (
    private.is_admin()
    OR private.owns_project(project_id)
);

GRANT UPDATE (status, review_feedback, reviewed_by, submitted_at, reviewed_at)
ON public.timesheets TO authenticated;


-- =========================================
-- TIMESHEET ENTRY POLICIES
-- =========================================

CREATE POLICY "Users can view authorized timesheet entries"
ON public.timesheet_entries
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.timesheets ts
        WHERE ts.id = timesheet_id
          AND (
              private.is_admin()
              OR ts.worker_id = auth.uid()
              OR private.owns_project(ts.project_id)
          )
    )
);

CREATE POLICY "Workers can add own completed time logs"
ON public.timesheet_entries
FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.timesheets ts
        JOIN public.time_logs tl
          ON tl.id = time_log_id
        JOIN public.tasks t
          ON t.id = tl.task_id
        WHERE ts.id = timesheet_id
          AND ts.worker_id = auth.uid()
          AND ts.status IN ('draft', 'revision')
          AND tl.worker_id = auth.uid()
          AND tl.ended_at IS NOT NULL
          AND t.project_id = ts.project_id
    )
);

CREATE POLICY "Workers can remove entries from draft sheets"
ON public.timesheet_entries
FOR DELETE TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.timesheets ts
        WHERE ts.id = timesheet_id
          AND ts.worker_id = auth.uid()
          AND ts.status IN ('draft', 'revision')
    )
);