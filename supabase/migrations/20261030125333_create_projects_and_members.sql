
-- =========================================
-- TASKFLOW: PROJECTS
-- =========================================

CREATE TABLE public.projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    client_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT,

    title TEXT NOT NULL,
    description TEXT,
    budget NUMERIC(12,2),

    start_date DATE,
    due_date DATE,

    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN (
            'active',
            'completed',
            'cancelled',
            'on_hold'
        )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_project_budget
        CHECK (budget IS NULL OR budget >= 0),

    CONSTRAINT valid_project_dates
        CHECK (
            start_date IS NULL
            OR due_date IS NULL
            OR due_date >= start_date
        )
);

-- =========================================
-- TASKFLOW: PROJECT MEMBERS
-- =========================================

CREATE TABLE public.project_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    project_id UUID NOT NULL
        REFERENCES public.projects(id)
        ON DELETE CASCADE,

    worker_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT,

    membership_status TEXT NOT NULL DEFAULT 'active'
        CHECK (membership_status IN ('active', 'removed')),

    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_project_worker
        UNIQUE (project_id, worker_id)
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_projects_client
    ON public.projects(client_id);

CREATE INDEX idx_projects_status
    ON public.projects(status);

CREATE INDEX idx_project_members_worker
    ON public.project_members(worker_id);

CREATE INDEX idx_project_members_project
    ON public.project_members(project_id);

-- =========================================
-- ENABLE RLS
-- =========================================

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
