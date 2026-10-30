-- =========================================
-- TASKFLOW: SUBMISSIONS
-- =========================================

CREATE TABLE public.submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    task_id UUID NOT NULL
        REFERENCES public.tasks(id)
        ON DELETE RESTRICT,

    worker_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT,

    version INTEGER NOT NULL DEFAULT 1,

    description TEXT,

    -- Storage path for the submitted file
    file_path TEXT,

    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'approved',
            'revision'
        )),

    review_feedback TEXT,

    reviewed_by UUID
        REFERENCES public.profiles(id)
        ON DELETE SET NULL,

    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    reviewed_at TIMESTAMPTZ,

    CONSTRAINT valid_submission_version
        CHECK (version >= 1),

    CONSTRAINT unique_submission_version
        UNIQUE (task_id, worker_id, version)
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_submissions_task
    ON public.submissions(task_id);

CREATE INDEX idx_submissions_worker
    ON public.submissions(worker_id);

CREATE INDEX idx_submissions_status
    ON public.submissions(status);

-- =========================================
-- ENABLE RLS
-- =========================================

ALTER TABLE public.submissions ENABLE ROW LEVEL SECURITY;