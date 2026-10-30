-- =========================================
-- TASKFLOW: AUTOMATIC PROFILE CREATION
-- =========================================

-- Create a private schema for internal functions
CREATE SCHEMA IF NOT EXISTS private;

-- Prevent application users from accessing this schema
REVOKE ALL ON SCHEMA private FROM PUBLIC;

-- Function that creates a profile after registration
CREATE OR REPLACE FUNCTION private.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (
        id,
        full_name
    )
    VALUES (
        NEW.id,
        COALESCE(
            NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'full_name'), ''),
            NULLIF(SPLIT_PART(COALESCE(NEW.email, ''), '@', 1), ''),
            'New User'
        )
    );

    RETURN NEW;
END;
$$;

-- Restrict direct execution of the function
REVOKE ALL ON FUNCTION private.handle_new_user()
FROM PUBLIC, anon, authenticated;

-- Run the function whenever a new Auth user is created
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION private.handle_new_user();