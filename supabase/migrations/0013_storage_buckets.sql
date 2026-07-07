-- ============================================================================
-- STORAGE
-- ============================================================================

INSERT INTO storage.buckets (id, name, public) VALUES
  ('voice-notes', 'voice-notes', false),
  ('task-photos', 'task-photos', false),
  ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- POLICIES
-- ============================================================================

DROP POLICY IF EXISTS "voice_notes_family_rw" ON storage.objects;
CREATE POLICY "voice_notes_family_rw" ON storage.objects
FOR ALL USING (
  bucket_id = 'voice-notes'
  AND is_family_member((storage.foldername(name))[1]::uuid)
);

DROP POLICY IF EXISTS "task_photos_family_rw" ON storage.objects;
CREATE POLICY "task_photos_family_rw" ON storage.objects
FOR ALL USING (
  bucket_id = 'task-photos'
  AND is_family_member((storage.foldername(name))[1]::uuid)
);

DROP POLICY IF EXISTS "avatars_family_rw" ON storage.objects;
CREATE POLICY "avatars_family_rw" ON storage.objects
FOR ALL USING (
  bucket_id = 'avatars'
  AND is_family_member((storage.foldername(name))[1]::uuid)
);
