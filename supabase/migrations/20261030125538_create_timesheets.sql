-- =========================================
-- TASKFLOW: TIMESHEETS
-- =========================================

CREATE TABLE public.timesheets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    worker_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT,

    project_id UUID NOT NULL
        REFERENCES public.projects(id)
        ON DELETE RESTRICT,

    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft',
            'submitted',
            'approved',
            'revision'
        )),

    review_feedback TEXT,

    reviewed_by UUID
        REFERENCES public.profiles(id)
        ON DELETE SET NULL,

    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_timesheet_period
        CHECK (period_end >= period_start),

    CONSTRAINT unique_worker_project_period
        UNIQUE (worker_id, project_id, period_start, period_end)
);

-- =========================================
-- TASKFLOW: TIMESHEET ENTRIES
-- =========================================

CREATE TABLE public.timesheet_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    timesheet_id UUID NOT NULL
        REFERENCES public.timesheets(id)
        ON DELETE CASCADE,

    time_log_id UUID NOT NULL
        REFERENCES public.time_logs(id)
        ON DELETE RESTRICT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- A time log can only belong to one timesheet
    CONSTRAINT unique_timesheet_time_log
        UNIQUE (time_log_id)
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_timesheets_worker
    ON public.timesheets(worker_id);

CREATE INDEX idx_timesheets_project
    ON public.timesheets(project_id);

CREATE INDEX idx_timesheets_status
    ON public.timesheets(status);

CREATE INDEX idx_timesheet_entries_timesheet
    ON public.timesheet_entries(timesheet_id);

-- =========================================
-- ENABLE RLS
-- =========================================

ALTER TABLE public.timesheets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timesheet_entries ENABLE ROW LEVEL SECURITY;