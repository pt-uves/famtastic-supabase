# Famtastic Edge Functions API

All edge functions are hosted on Supabase and must be called with a valid `Authorization: Bearer <JWT>` header (the access token from Supabase Auth), unless otherwise specified.

Base URL: `https://<project-ref>.supabase.co/functions/v1/`

---

## 1. Auth & Profiles

### POST `/auth/complete-onboarding`
Completes the initial sign-up by setting the profile name and creating a family atomically.

**Request Body:**
```json
{
  "full_name": "Sarah Johnson",
  "family_name": "The Johnsons",
  "avatar_url": "https://..." // optional
}
```
**Response (200 OK):**
```json
{
  "profile": { ... },
  "family": { ... }
}
```

*(Note: Updating profile details later is handled via direct PostgREST calls to the `profiles` table, as requested.)*

---

## 2. Children

### POST `/children/create`
Creates a child profile. Caller must be the owner of the family.

**Request Body:**
```json
{
  "family_id": "uuid",
  "name": "Aarav",
  "date_of_birth": "2016-03-15", // optional
  "gender": "male", // male, female, other, prefer_not_to_say (optional)
  "diagnosis": "ASD", // optional
  "special_notes": "...", // optional
  "language_level": "standard", // simple, standard, full (optional, default: standard)
  "communication_preferences": "..." // optional
}
```
**Response (200 OK):**
```json
{ "child": { ... } }
```

---

## 3. Invitations

### POST `/invitations/send`
Invite a new or existing user to be linked to a child. Sends an email (to be implemented with provider).

**Request Body:**
```json
{
  "email": "rohan@email.com",
  "child_id": "uuid",
  "role_category": "co_parent", // co_parent, caregiver, grandparent, teacher, therapist, relative, other
  "role_label": "Speech Therapist" // optional
}
```
**Response (200 OK):**
```json
{ "membership": { ... } }
```

### POST `/invitations/accept`
Accepts a pending invitation.

**Request Body:**
```json
{ "membership_id": "uuid" }
```
**Response (200 OK):**
```json
{ "membership": { ... } }
```

### POST `/invitations/decline`
Declines a pending invitation.

**Request Body:**
```json
{ "membership_id": "uuid" }
```
**Response (200 OK):**
```json
{ "membership": { ... } }
```

---

## 4. Check-Ins

### POST `/check-ins/create`
Submits a check-in. Can be initiated by an adult or by the child (in Child Mode).

**Request Body:**
```json
{
  "child_id": "uuid",
  "mood": "happy", // happy, calm, overwhelmed, angry
  "text_response": "...", // optional
  "voice_note_url": "...", // optional (upload via pre-signed URL first)
  "shared_with_family": true, // optional, default true
  "is_from_child": false, // optional, default false
  "reply_prompt_id": "uuid" // optional (if replying to a specific prompt)
}
```
**Response (200 OK):**
```json
{ "check_in": { ... } }
```

### POST `/check-ins/prompt`
Sends a push notification to prompt a child to check in (creates a `check_in_prompts` row).

**Request Body:**
```json
{
  "child_id": "uuid",
  "question_text": "How was school today?", // optional
  "scheduled_at": "2026-07-08T15:00:00Z" // optional (if scheduling for later)
}
```
**Response (200 OK):**
```json
{ "prompt": { ... } }
```

---

## 5. Child Mode

### POST `/child-mode/enable`
Enables Child Mode on a device.

**Request Body:**
```json
{
  "child_id": "uuid",
  "device_id": "unique-device-identifier"
}
```
**Response (200 OK):**
```json
{ "child_id": "uuid", "child_mode_enabled": true }
```

### POST `/child-mode/disable`
Disables Child Mode. Requires the parent to enter their account password to verify intent.

**Request Body:**
```json
{
  "child_id": "uuid",
  "password": "my-account-password"
}
```
**Response (200 OK):**
```json
{ "child_id": "uuid", "child_mode_enabled": false }
```

---

## 6. Push Notifications

### POST `/push-tokens/register`
Registers a device push token for the current user.

**Request Body:**
```json
{
  "token": "ExponentPushToken[...]", // e.g. Expo Push token
  "platform": "ios" // ios, android, web
}
```
**Response (200 OK):**
```json
{ "registered": true }
```

### POST `/push-tokens/unregister`
Removes a device push token (usually called on sign-out). *(Accepts POST or DELETE)*

**Request Body:**
```json
{
  "token": "ExponentPushToken[...]"
}
```
**Response (200 OK):**
```json
{ "unregistered": true }
```
