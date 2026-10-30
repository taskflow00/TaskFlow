-- =========================================
-- TASKFLOW: TASKS
-- =========================================

CREATE TABLE public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    project_id UUID NOT NULL
        REFERENCES public.projects(id)
        ON DELETE CASCADE,

    assigned_to UUID
        REFERENCES public.profiles(id)
        ON DELETE SET NULL,

    title TEXT NOT NULL,
    description TEXT,

    priority TEXT NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low', 'medium', 'high', 'urgent')),

    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'in_progress',
            'submitted',
            'revision',
            'completed',
            'cancelled'
        )),

    estimated_hours NUMERIC(8,2),

    start_date TIMESTAMPTZ,
    due_date TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_estimated_hours
        CHECK (estimated_hours IS NULL OR estimated_hours >= 0),

    CONSTRAINT valid_task_dates
        CHECK (
            start_date IS NULL
            OR due_date IS NULL
            OR due_date >= start_date
        )
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_tasks_project
    ON public.tasks(project_id);

CREATE INDEX idx_tasks_assigned_to
    ON public.tasks(assigned_to);

CREATE INDEX idx_tasks_status
    ON public.tasks(status);

CREATE INDEX idx_tasks_due_date
    ON public.tasks(due_date);

-- =========================================
-- ENABLE RLS
-- =========================================

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;