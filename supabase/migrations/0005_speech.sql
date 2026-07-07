-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS speech_difficulty CASCADE;
CREATE TYPE speech_difficulty AS ENUM ('easy','medium','hard');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS speech_exercises (
  id uuid primary key default public.uuid_generate_v7(),
  target_word text not null,
  difficulty speech_difficulty not null default 'medium',
  category text,
  audio_url text,
  image_url text,
  phonetic_hint text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS custom_word_lists (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  child_id uuid not null references family_members(id) on delete cascade,
  word text not null,
  phonetic_hint text,
  added_by uuid references family_members(id),
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS speech_attempts (
  id uuid primary key default public.uuid_generate_v7(),
  child_id uuid not null references family_members(id) on delete cascade,
  exercise_id uuid references speech_exercises(id),
  custom_word_id uuid references custom_word_lists(id),
  transcript text,
  confidence numeric,
  alternatives jsonb,
  ai_score int,
  ai_feedback text,
  attempt_number int not null default 1,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  constraint chk_speech_attempt_target check (exercise_id is not null or custom_word_id is not null)
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_custom_word_lists_child ON custom_word_lists (child_id);
CREATE INDEX IF NOT EXISTS idx_speech_attempts_child_created ON speech_attempts (child_id, created_at desc);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE speech_exercises IS 'Global library of speech exercises.';
COMMENT ON COLUMN speech_exercises.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN speech_exercises.target_word IS 'Target word for practice.';
COMMENT ON COLUMN speech_exercises.difficulty IS 'Difficulty level.';
COMMENT ON COLUMN speech_exercises.category IS 'Exercise category.';
COMMENT ON COLUMN speech_exercises.audio_url IS 'Audio example URL.';
COMMENT ON COLUMN speech_exercises.image_url IS 'Image example URL.';
COMMENT ON COLUMN speech_exercises.phonetic_hint IS 'Phonetic hint.';
COMMENT ON COLUMN speech_exercises.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN speech_exercises.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE custom_word_lists IS 'Custom practice words for a child.';
COMMENT ON COLUMN custom_word_lists.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN custom_word_lists.family_id IS 'Family ID.';
COMMENT ON COLUMN custom_word_lists.child_id IS 'Child ID.';
COMMENT ON COLUMN custom_word_lists.word IS 'Custom target word.';
COMMENT ON COLUMN custom_word_lists.phonetic_hint IS 'Phonetic hint.';
COMMENT ON COLUMN custom_word_lists.added_by IS 'Member who added the word.';
COMMENT ON COLUMN custom_word_lists.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN custom_word_lists.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE speech_attempts IS 'Attempts recorded for speech exercises.';
COMMENT ON COLUMN speech_attempts.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN speech_attempts.child_id IS 'Child ID.';
COMMENT ON COLUMN speech_attempts.exercise_id IS 'Associated exercise ID.';
COMMENT ON COLUMN speech_attempts.custom_word_id IS 'Associated custom word ID.';
COMMENT ON COLUMN speech_attempts.transcript IS 'Audio transcript.';
COMMENT ON COLUMN speech_attempts.confidence IS 'Speech recognition confidence.';
COMMENT ON COLUMN speech_attempts.alternatives IS 'Alternative transcripts.';
COMMENT ON COLUMN speech_attempts.ai_score IS 'AI calculated score.';
COMMENT ON COLUMN speech_attempts.ai_feedback IS 'AI generated feedback.';
COMMENT ON COLUMN speech_attempts.attempt_number IS 'Sequential attempt number.';
COMMENT ON COLUMN speech_attempts.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN speech_attempts.updated_at IS 'Last update timestamp.';
