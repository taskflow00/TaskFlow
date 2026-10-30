-- =========================================
-- TASKFLOW: TIME LOGS
-- =========================================

CREATE TABLE public.time_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    task_id UUID NOT NULL
        REFERENCES public.tasks(id)
        ON DELETE RESTRICT,

    worker_id UUID NOT NULL
        REFERENCES public.profiles(id)
        ON DELETE RESTRICT,

    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    ended_at TIMESTAMPTZ,

    notes TEXT,

    duration_seconds BIGINT GENERATED ALWAYS AS (
        CASE
            WHEN ended_at IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM (ended_at - started_at))::BIGINT
        END
    ) STORED,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_time_log_duration
        CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- =========================================
-- INDEXES
-- =========================================

CREATE INDEX idx_time_logs_worker
    ON public.time_logs(worker_id);

CREATE INDEX idx_time_logs_task
    ON public.time_logs(task_id);

CREATE INDEX idx_time_logs_started_at
    ON public.time_logs(started_at);

-- =========================================
-- ONE ACTIVE TIMER PER WORKER
-- =========================================

CREATE UNIQUE INDEX idx_one_active_timer_per_worker
    ON public.time_logs(worker_id)
    WHERE ended_at IS NULL;

-- =========================================
-- ENABLE RLS
-- =========================================

ALTER TABLE public.time_logs ENABLE ROW LEVEL SECURITY;