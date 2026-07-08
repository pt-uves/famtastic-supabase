-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS exercise_difficulty CASCADE;
CREATE TYPE exercise_difficulty AS ENUM ('beginner', 'intermediate', 'advanced');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- speech_exercises
-- Global library managed by the platform admin.
-- Words, audio pronunciation (TTS), picture cue, photo, difficulty level.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.speech_exercises (
    id              UUID                        PRIMARY KEY DEFAULT uuid_generate_v7(),
    word            TEXT                        NOT NULL,
    language_code   VARCHAR(10)                 NOT NULL DEFAULT 'en',
    audio_url       TEXT,
    image_url       TEXT,
    photo_url       TEXT,
    difficulty      exercise_difficulty         NOT NULL DEFAULT 'beginner',
    is_active       BOOLEAN                     NOT NULL DEFAULT true,
    created_by      UUID,
    created_at      TIMESTAMPTZ                 NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_speech_exercises_word CHECK (length(trim(word)) > 0)
);

-- ----------------------------------------------------------------------------
-- child_custom_words
-- Custom word lists added per child by the parent or a linked therapist.
-- Completely separate from the global library.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.child_custom_words (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id    UUID        NOT NULL,
    added_by    UUID        NOT NULL,
    word        TEXT        NOT NULL,
    audio_url   TEXT,
    image_url   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_child_custom_words_word CHECK (length(trim(word)) > 0)
);

-- ----------------------------------------------------------------------------
-- speech_sessions
-- One session = one 15-minute practice block containing multiple word attempts.
-- Aggregated totals are stored here to avoid recalculating on every read.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.speech_sessions (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id        UUID        NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at        TIMESTAMPTZ,
    total_words     INTEGER     NOT NULL DEFAULT 0 CHECK (total_words >= 0),
    words_mastered  INTEGER     NOT NULL DEFAULT 0 CHECK (words_mastered >= 0),
    accuracy_pct    NUMERIC(5,2)              CHECK (accuracy_pct BETWEEN 0 AND 100),

    CONSTRAINT chk_speech_sessions_mastered CHECK (words_mastered <= total_words)
);

-- ----------------------------------------------------------------------------
-- speech_attempts
-- One row per word attempt within a session.
-- References either the global library (exercise_id) or a custom word
-- (custom_word_id). At least one must be non-NULL.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.speech_attempts (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    session_id          UUID        NOT NULL,
    child_id            UUID        NOT NULL,
    exercise_id         UUID,
    custom_word_id      UUID,
    recorded_audio_url  TEXT,
    transcription       TEXT,
    stt_confidence      NUMERIC(4,3)            CHECK (stt_confidence BETWEEN 0 AND 1),
    ai_score            SMALLINT                CHECK (ai_score BETWEEN 0 AND 100),
    ai_feedback         TEXT,
    is_mastered         BOOLEAN     NOT NULL DEFAULT false,
    attempted_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_speech_attempts_source CHECK (
        exercise_id IS NOT NULL OR custom_word_id IS NOT NULL
    )
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.speech_exercises DROP CONSTRAINT IF EXISTS fk_speech_exercises_created_by;
ALTER TABLE public.speech_exercises ADD CONSTRAINT fk_speech_exercises_created_by
    FOREIGN KEY (created_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

-- Unique word per language in the global library.
CREATE UNIQUE INDEX IF NOT EXISTS uk_speech_exercises_word_lang
    ON public.speech_exercises (word, language_code);

-- Active exercise lookup by difficulty for the admin exercise browser.
CREATE INDEX IF NOT EXISTS idx_speech_exercises_active_diff
    ON public.speech_exercises (is_active, difficulty);

ALTER TABLE public.child_custom_words DROP CONSTRAINT IF EXISTS fk_child_custom_words_child;
ALTER TABLE public.child_custom_words ADD CONSTRAINT fk_child_custom_words_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.child_custom_words DROP CONSTRAINT IF EXISTS fk_child_custom_words_added_by;
ALTER TABLE public.child_custom_words ADD CONSTRAINT fk_child_custom_words_added_by
    FOREIGN KEY (added_by) REFERENCES public.profiles (id) ON DELETE RESTRICT;

-- A child can't have the same custom word twice.
CREATE UNIQUE INDEX IF NOT EXISTS uk_child_custom_words_child_word
    ON public.child_custom_words (child_id, word);

ALTER TABLE public.speech_sessions DROP CONSTRAINT IF EXISTS fk_speech_sessions_child;
ALTER TABLE public.speech_sessions ADD CONSTRAINT fk_speech_sessions_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

-- Progress tracking: all sessions for a child ordered by time.
CREATE INDEX IF NOT EXISTS idx_speech_sessions_child_started
    ON public.speech_sessions (child_id, started_at DESC);

ALTER TABLE public.speech_attempts DROP CONSTRAINT IF EXISTS fk_speech_attempts_session;
ALTER TABLE public.speech_attempts ADD CONSTRAINT fk_speech_attempts_session
    FOREIGN KEY (session_id) REFERENCES public.speech_sessions (id) ON DELETE CASCADE;

ALTER TABLE public.speech_attempts DROP CONSTRAINT IF EXISTS fk_speech_attempts_child;
ALTER TABLE public.speech_attempts ADD CONSTRAINT fk_speech_attempts_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.speech_attempts DROP CONSTRAINT IF EXISTS fk_speech_attempts_exercise;
ALTER TABLE public.speech_attempts ADD CONSTRAINT fk_speech_attempts_exercise
    FOREIGN KEY (exercise_id) REFERENCES public.speech_exercises (id) ON DELETE SET NULL;

ALTER TABLE public.speech_attempts DROP CONSTRAINT IF EXISTS fk_speech_attempts_custom_word;
ALTER TABLE public.speech_attempts ADD CONSTRAINT fk_speech_attempts_custom_word
    FOREIGN KEY (custom_word_id) REFERENCES public.child_custom_words (id) ON DELETE SET NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.speech_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_custom_words ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.speech_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.speech_attempts ENABLE ROW LEVEL SECURITY;

-- POLICIES — speech_exercises (global library)

DROP POLICY IF EXISTS "speech_exercises_select_policy" ON public.speech_exercises;
CREATE POLICY "speech_exercises_select_policy" ON public.speech_exercises
    FOR SELECT USING (is_active = true OR is_platform_admin());

DROP POLICY IF EXISTS "speech_exercises_insert_policy" ON public.speech_exercises;
CREATE POLICY "speech_exercises_insert_policy" ON public.speech_exercises
    FOR INSERT WITH CHECK (is_platform_admin());

DROP POLICY IF EXISTS "speech_exercises_update_policy" ON public.speech_exercises;
CREATE POLICY "speech_exercises_update_policy" ON public.speech_exercises
    FOR UPDATE USING (is_platform_admin());

DROP POLICY IF EXISTS "speech_exercises_delete_policy" ON public.speech_exercises;
CREATE POLICY "speech_exercises_delete_policy" ON public.speech_exercises
    FOR DELETE USING (is_platform_admin());

-- POLICIES — child_custom_words

DROP POLICY IF EXISTS "child_custom_words_select_policy" ON public.child_custom_words;
CREATE POLICY "child_custom_words_select_policy" ON public.child_custom_words
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "child_custom_words_insert_policy" ON public.child_custom_words;
CREATE POLICY "child_custom_words_insert_policy" ON public.child_custom_words
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "child_custom_words_update_policy" ON public.child_custom_words;
CREATE POLICY "child_custom_words_update_policy" ON public.child_custom_words
    FOR UPDATE USING (added_by = auth.uid() OR owns_child(child_id));

DROP POLICY IF EXISTS "child_custom_words_delete_policy" ON public.child_custom_words;
CREATE POLICY "child_custom_words_delete_policy" ON public.child_custom_words
    FOR DELETE USING (added_by = auth.uid() OR owns_child(child_id));

-- POLICIES — speech_sessions

DROP POLICY IF EXISTS "speech_sessions_select_policy" ON public.speech_sessions;
CREATE POLICY "speech_sessions_select_policy" ON public.speech_sessions
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "speech_sessions_insert_policy" ON public.speech_sessions;
CREATE POLICY "speech_sessions_insert_policy" ON public.speech_sessions
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "speech_sessions_update_policy" ON public.speech_sessions;
CREATE POLICY "speech_sessions_update_policy" ON public.speech_sessions
    FOR UPDATE USING (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

-- POLICIES — speech_attempts

DROP POLICY IF EXISTS "speech_attempts_select_policy" ON public.speech_attempts;
CREATE POLICY "speech_attempts_select_policy" ON public.speech_attempts
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "speech_attempts_insert_policy" ON public.speech_attempts;
CREATE POLICY "speech_attempts_insert_policy" ON public.speech_attempts
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  exercise_difficulty                           IS 'Difficulty tier of a speech therapy exercise in the global library.';

COMMENT ON TABLE  public.speech_exercises                           IS 'Global speech therapy exercise library managed by the platform admin. Each entry is one word with audio, image, and difficulty metadata.';
COMMENT ON COLUMN public.speech_exercises.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.speech_exercises.word                      IS 'The target word the child is asked to pronounce.';
COMMENT ON COLUMN public.speech_exercises.language_code             IS 'BCP 47 language code (e.g. en, hi). Paired with word for uniqueness.';
COMMENT ON COLUMN public.speech_exercises.audio_url                 IS 'URL of the TTS-generated model pronunciation audio.';
COMMENT ON COLUMN public.speech_exercises.image_url                 IS 'Picture cue image URL (Supabase Storage).';
COMMENT ON COLUMN public.speech_exercises.photo_url                 IS 'Real-world photograph URL to accompany the word.';
COMMENT ON COLUMN public.speech_exercises.difficulty                IS 'Difficulty tier: beginner, intermediate, or advanced.';
COMMENT ON COLUMN public.speech_exercises.is_active                 IS 'Inactive exercises are hidden from the child UI but retained for history.';
COMMENT ON COLUMN public.speech_exercises.created_by                IS 'Platform admin who added this exercise.';
COMMENT ON COLUMN public.speech_exercises.created_at                IS 'Row creation timestamp.';

COMMENT ON TABLE  public.child_custom_words                         IS 'Per-child custom practice words added by the parent or linked therapist. Separate from the global exercise library.';
COMMENT ON COLUMN public.child_custom_words.id                      IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.child_custom_words.child_id                IS 'The child this word was added for.';
COMMENT ON COLUMN public.child_custom_words.added_by                IS 'Member (parent or therapist) who added this word.';
COMMENT ON COLUMN public.child_custom_words.word                    IS 'The custom practice word.';
COMMENT ON COLUMN public.child_custom_words.audio_url               IS 'Optional custom audio uploaded by the member.';
COMMENT ON COLUMN public.child_custom_words.image_url               IS 'Optional custom image uploaded by the member.';
COMMENT ON COLUMN public.child_custom_words.created_at              IS 'Row creation timestamp.';

COMMENT ON TABLE  public.speech_sessions                            IS 'A single 15-minute speech therapy practice block. Aggregates attempt totals for fast progress-tracking reads.';
COMMENT ON COLUMN public.speech_sessions.id                         IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.speech_sessions.child_id                   IS 'The child who completed this session.';
COMMENT ON COLUMN public.speech_sessions.started_at                 IS 'When the session began.';
COMMENT ON COLUMN public.speech_sessions.ended_at                   IS 'When the session ended. NULL if still in progress.';
COMMENT ON COLUMN public.speech_sessions.total_words                IS 'Number of words attempted in this session.';
COMMENT ON COLUMN public.speech_sessions.words_mastered             IS 'Number of words the AI scored as mastered.';
COMMENT ON COLUMN public.speech_sessions.accuracy_pct              IS 'Average AI score across all attempts (0-100).';

COMMENT ON TABLE  public.speech_attempts                            IS 'One word attempt within a speech session. References either the global exercise library or a child-specific custom word.';
COMMENT ON COLUMN public.speech_attempts.id                         IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.speech_attempts.session_id                 IS 'The session this attempt belongs to.';
COMMENT ON COLUMN public.speech_attempts.child_id                   IS 'Denormalised child reference for efficient per-child history queries.';
COMMENT ON COLUMN public.speech_attempts.exercise_id                IS 'Global exercise attempted. NULL if a custom word was used.';
COMMENT ON COLUMN public.speech_attempts.custom_word_id             IS 'Custom word attempted. NULL if a global exercise was used.';
COMMENT ON COLUMN public.speech_attempts.recorded_audio_url         IS 'URL of the child''s recorded attempt (Supabase Storage).';
COMMENT ON COLUMN public.speech_attempts.transcription              IS 'Google STT primary transcription of the child''s recording.';
COMMENT ON COLUMN public.speech_attempts.stt_confidence             IS 'Google STT confidence score (0.000-1.000).';
COMMENT ON COLUMN public.speech_attempts.ai_score                   IS 'AI-generated pronunciation score (0-100).';
COMMENT ON COLUMN public.speech_attempts.ai_feedback                IS 'Child-friendly feedback text generated by the AI model.';
COMMENT ON COLUMN public.speech_attempts.is_mastered                IS 'True when the AI determined the word was correctly pronounced.';
COMMENT ON COLUMN public.speech_attempts.attempted_at               IS 'Timestamp of the attempt.';
