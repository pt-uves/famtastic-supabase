# Famtastic - Auth Email Templates

Branded HTML email templates that replace Supabase's default auth emails. They use
the Famtastic brand: warm violet (`#7C5CFF → #6438E8`), Plus Jakarta Sans / Baloo 2,
a rounded logo badge, and care-focused copy for families raising a child with
special needs.

## Files

| Template                | Auth event                         | Key variables                                                                                             |
| ----------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `confirmation.html`     | Confirm signup (6-digit OTP)       | `{{ .Token }}`, `{{ .Email }}`                                                                            |
| `invite.html`           | Invite a member to a child         | `{{ .Data.inviter_name }}`, `{{ .Data.child_names }}`, `{{ .Data.role_label }}`, `{{ .ConfirmationURL }}` |
| `recovery.html`         | Reset password                     | `{{ .Token }}`, `{{ .Email }}`                                                                            |
| `magic_link.html`       | Passwordless sign-in               | `{{ .Token }}`, `{{ .Email }}`                                                                            |
| `email_change.html`     | Change email address               | `{{ .Email }}`, `{{ .NewEmail }}`, `{{ .Token }}`                                                         |
| `reauthentication.html` | Reauthenticate (sensitive actions) | `{{ .Token }}`                                                                                            |

The `invite.html` metadata (`{{ .Data.* }}`) is populated by the `invite-member`
edge function via `admin.auth.admin.inviteUserByEmail(email, { data: {...} })`.

> **All auth emails are OTP-only** - they show a 6-digit `{{ .Token }}` the user
> copies into the app (verified via `supabase.auth.verifyOtp`), with **no clickable
> link**. The app has not implemented any link-landing flow, so `confirmation`,
> `recovery`, `magic_link`, `email_change`, and `reauthentication` all omit the
> `ConfirmationURL` button entirely. **`invite.html` is the one exception**: it keeps
> the `{{ .ConfirmationURL }}` "Accept invitation" link, since accepting an invite
> lands the new member on a page to set their password.

## Local development

These are already wired in `config.toml` under `[auth.email.template.*]`. Restart
the local stack to pick up changes:

```bash
npm run db:stop && npm run db:start
```

### Email delivery: Resend SMTP (real emails)

The local stack is configured to send **real** emails through Resend via
`[auth.email.smtp]` in `config.toml`, so it no longer captures them in the Inbucket
test server. No 2FA required - just an API key. One-time setup:

1. Sign up at <https://resend.com> (free tier) and create an API key at
   <https://resend.com/api-keys>.
2. Fill these in `supabase/.env` (never commit real values). This **one block
   drives both** the auth emails (via `config.toml` → `[auth.email.smtp]`) and the
   edge-function transactional emails (via `functions/_shared/email.ts`):
   ```
   SMTP_HOST=smtp.resend.com
   SMTP_PORT=465
   SMTP_USER=resend
   SMTP_PASS=re_your_resend_api_key
   SMTP_ADMIN_EMAIL=onboarding@resend.dev   # or an address on your verified domain
   SMTP_SENDER_NAME=Famtastic
   ```
3. Restart: `npm run db:stop && npm run db:start`.

For Resend the SMTP username is the literal `resend`; the API key is the password.
`SMTP_ADMIN_EMAIL` is the From address and must be on a domain you've **verified in
Resend** - for local testing use `onboarding@resend.dev`, which Resend lets you send
from without verifying a domain. Port `465` (SSL) is the default - switch to `587`
(STARTTLS), `2465`, or `2587` (set both `SMTP_PORT` and the `port` in `config.toml`)
if your network blocks it.

> **Switching providers (e.g. to Amazon SES) is config-only** - change the `SMTP_*`
> values in `.env` (SES: `host = email-smtp.<region>.amazonaws.com`, `port = 587`,
> `user` = IAM SMTP username, `pass` = SES SMTP password, a verified From). No code
> changes; both email systems follow the same variables.

> To go back to the offline Inbucket catcher instead, set `enabled = false` under
> `[auth.email.smtp]`; captured mail is then viewable at <http://127.0.0.1:54324>.

## Hosted / production project

`config.toml` email templates apply to the **local** stack only. For the hosted
Supabase project, apply the same HTML one of two ways:

1. **Dashboard** → Authentication → Email Templates → pick each template, paste the
   contents of the matching file, and set the subject (subjects are listed in
   `config.toml`).
2. **Management API** - `PATCH /v1/projects/{ref}/config/auth` with
   `mailer_templates_<type>_content` + `mailer_subjects_<type>` fields.

Also set a production SMTP sender (`[auth.email.smtp]` in `config.toml` for local;
Dashboard → Project Settings → Auth → SMTP for hosted) so emails come from a
Famtastic domain instead of the Supabase default.

## Editing

- Keep everything inline-styled and table-based - email clients strip `<style>`
  blocks, external CSS, and most modern CSS. The web-font `<link>` is a progressive
  enhancement; every element has a system-font fallback stack.
- The logo badge uses `background-image: linear-gradient(...)` with a solid
  `bgcolor="#7C5CFF"` fallback for Outlook. CTA buttons include a VML fallback so
  they render as pill buttons in Outlook too.
- Do not rename the `{{ .Var }}` / `{{ .Data.* }}` placeholders - they are
  substituted by Supabase (or, for the SendGrid templates below, by the edge fn).

## Related transactional templates (edge function, not Supabase auth)

The `invite-member` edge function sends its own emails via SMTP (see
`../functions/_shared/email.ts` → `sendEmail()`, which reuses the same `SMTP_*`
credentials as the auth mailer), branded to match, in
`../functions/_shared/email-templates/`:

- `supabase-invite-user.html` - reference copy of `invite.html` (paste into the
  hosted "Invite user" template; kept identical to this folder's `invite.html`).
- `invite-existing-member.html` - sent when an already-registered account is linked
  to a new child (single-brace `{{ inviter_name }}` etc., substituted in code).
