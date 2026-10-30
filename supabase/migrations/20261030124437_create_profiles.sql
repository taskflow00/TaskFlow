-- =========================================
-- TASKFLOW: PROFILES TABLE
-- =========================================

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY
        REFERENCES auth.users(id)
        ON DELETE CASCADE,

    full_name TEXT NOT NULL,

    role TEXT NOT NULL DEFAULT 'worker'
        CHECK (role IN ('admin', 'client', 'worker')),

    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended')),

    avatar_url TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;git push -u origin main