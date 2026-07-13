-- ============================================================================
-- STORAGE BUCKETS
-- ============================================================================
-- Creates the three storage buckets required for Milestone 1.
-- All buckets are private - no public access. Clients use pre-signed URLs.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Create buckets
-- storage.buckets is managed by Supabase Storage. We INSERT idempotently.
-- ----------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    (
        'avatars',
        'avatars',
        false,
        5242880, -- 5 MiB
        ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
    ),
    (
        'voice-notes',
        'voice-notes',
        false,
        26214400, -- 25 MiB
        ARRAY['audio/mpeg', 'audio/mp4', 'audio/webm', 'audio/ogg', 'audio/wav', 'audio/x-m4a']
    ),
    (
        'child-photos',
        'child-photos',
        false,
        5242880, -- 5 MiB
        ARRAY['image/jpeg', 'image/png', 'image/webp']
    )
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- RLS POLICIES - avatars
-- ============================================================================
-- Path convention: avatars/{user_id}/{filename}
-- Only the owner can upload/delete; any authenticated user can read
-- (avatars are shown across the app in member lists).
-- ============================================================================

DROP POLICY IF EXISTS "avatars_select_policy" ON storage.objects;
CREATE POLICY "avatars_select_policy" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'avatars'
        AND auth.role() = 'authenticated'
    );

DROP POLICY IF EXISTS "avatars_insert_policy" ON storage.objects;
CREATE POLICY "avatars_insert_policy" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "avatars_update_policy" ON storage.objects;
CREATE POLICY "avatars_update_policy" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

DROP POLICY IF EXISTS "avatars_delete_policy" ON storage.objects;
CREATE POLICY "avatars_delete_policy" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ============================================================================
-- RLS POLICIES - voice-notes
-- ============================================================================
-- Path convention: voice-notes/{child_id}/{check_in_id}/{filename}
-- Upload: only members linked to the child.
-- Read: only members linked to the child.
-- ============================================================================

DROP POLICY IF EXISTS "voice_notes_select_policy" ON storage.objects;
CREATE POLICY "voice_notes_select_policy" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'voice-notes'
        AND (
            public.owns_child((storage.foldername(name))[1]::uuid)
            OR public.is_linked_to_child((storage.foldername(name))[1]::uuid)
            OR public.is_platform_admin()
        )
    );

DROP POLICY IF EXISTS "voice_notes_insert_policy" ON storage.objects;
CREATE POLICY "voice_notes_insert_policy" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'voice-notes'
        AND (
            public.owns_child((storage.foldername(name))[1]::uuid)
            OR public.is_linked_to_child((storage.foldername(name))[1]::uuid)
        )
    );

DROP POLICY IF EXISTS "voice_notes_delete_policy" ON storage.objects;
CREATE POLICY "voice_notes_delete_policy" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'voice-notes'
        AND (
            public.owns_child((storage.foldername(name))[1]::uuid)
            OR public.is_platform_admin()
        )
    );

-- ============================================================================
-- RLS POLICIES - child-photos
-- ============================================================================
-- Path convention: child-photos/{child_id}/{filename}
-- Upload/delete: only the parent who owns the child.
-- Read: any member linked to the child.
-- ============================================================================

DROP POLICY IF EXISTS "child_photos_select_policy" ON storage.objects;
CREATE POLICY "child_photos_select_policy" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'child-photos'
        AND (
            public.owns_child((storage.foldername(name))[1]::uuid)
            OR public.is_linked_to_child((storage.foldername(name))[1]::uuid)
            OR public.is_platform_admin()
        )
    );

DROP POLICY IF EXISTS "child_photos_insert_policy" ON storage.objects;
CREATE POLICY "child_photos_insert_policy" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'child-photos'
        AND public.owns_child((storage.foldername(name))[1]::uuid)
    );

DROP POLICY IF EXISTS "child_photos_update_policy" ON storage.objects;
CREATE POLICY "child_photos_update_policy" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'child-photos'
        AND public.owns_child((storage.foldername(name))[1]::uuid)
    );

DROP POLICY IF EXISTS "child_photos_delete_policy" ON storage.objects;
CREATE POLICY "child_photos_delete_policy" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'child-photos'
        AND (
            public.owns_child((storage.foldername(name))[1]::uuid)
            OR public.is_platform_admin()
        )
    );
