# Famtastic

Famtastic is a comprehensive family management and child development tracking application backed by Supabase. It provides tools to manage family units, routines, tasks, and child care coordination with external providers (therapists, teachers, doctors).

## Features

- **Family & Identity Management**: Manage family members, child profiles, and invite external providers.
- **Routines & Habits**: Build daily routines and track healthy habits.
- **Task Management**: Assign and track chores, tasks, and responsibilities.
- **Check-ins & Nudges**: Emotional check-ins and subtle nudges to stay on track.
- **Rewards System**: Incentivize progress with a built-in rewards system.
- **Speech & Development Tracking**: Specialized tracking for speech and other developmental milestones.
- **Location Tracking**: Keep track of family members' locations for safety.
- **SOS & Emergency**: Quick access to SOS features and emergency contacts.
- **Content Administration**: Platform admin features for managing application content.

---

## Database Workflow

This project is managed with a **migration-first** workflow.

> **The Golden Rule**: All database changes are version-controlled SQL migrations. No direct SQL Editor usage in production.

### Quick Start

```bash
# 1. Copy environment config
cp .env.example .env
# (fill in your Supabase credentials)

# 2. Install dependencies
npm install

# 3. Register Git hooks
git config core.hooksPath .githooks

# 4. Start local Supabase stack
npm run db:start

# 5. Apply migrations + seed data
npm run db:reset
```

Local Studio: http://127.0.0.1:54323

### Commands

| Task                    | Command                          |
| ----------------------- | -------------------------------- |
| New migration           | `npm run db:new -- <name>`       |
| Apply locally           | `npm run db:reset`               |
| Push to production      | `npm run db:push`                |
| Preview production push | `npm run db:push:dry-run`        |
| Capture schema diff     | `npm run db:diff:file -- <name>` |
| Generate TS types       | `npm run types:generate`         |

**📖 Read the full guide: [docs/MIGRATION_GUIDE.md](./docs/MIGRATION_GUIDE.md)**

---

## Project Structure

```text
famtastic/
├── supabase/
│   ├── config.toml          ← Supabase configuration (version-controlled)
│   ├── seed.sql             ← Local dev seed data (never run in production)
│   ├── migrations/          ← ALL database changes live here
│   └── templates/           ← Copy-paste boilerplate for new migrations
├── scripts/
│   ├── new-migration.js     ← Creates timestamped migration files
│   ├── diff-migration.js    ← Captures schema diffs as migrations
│   └── verify-migrations.js ← Validates filename conventions (used in CI)
├── .github/
│   └── workflows/           ← CI/CD workflows for migrations & types
├── .githooks/
│   └── pre-push             ← Validates migrations before every push
├── docs/
│   └── MIGRATION_GUIDE.md   ← Complete developer workflow guide
├── .env.example             ← Safe-to-commit env variable template
└── package.json             ← All db:* npm scripts
```
