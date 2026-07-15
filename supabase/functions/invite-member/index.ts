// invite-member
// Invites a person (by email) to one or more of the caller's children.
//
// Why this needs the service role: a parent cannot resolve an arbitrary
// email -> account (profiles RLS blocks reading other people's profiles) and
// cannot create an auth account for a brand-new email. Everything else in the
// invitation flow (accept/decline) is a direct client update by the invitee.

import { z } from "zod";
import { AuthError, requireAuth } from "../_shared/auth.ts";
import { handleCors } from "../_shared/cors.ts";
import { sendEmail } from "../_shared/email.ts";
import { err, ok } from "../_shared/response.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { getInviteExistingMemberHtml } from "./invite-existing-member.ts";

const bodySchema = z.object({
  email: z
    .string()
    .email()
    .transform((e) => e.trim().toLowerCase()),
  child_ids: z.array(z.string().uuid()).min(1),
  role_category: z.enum([
    "co_parent",
    "caregiver",
    "grandparent",
    "teacher",
    "therapist",
    "relative",
    "other",
  ]),
  role_label: z.string().trim().min(1).max(100).optional(),
  inviter_name: z.string().trim().min(1).max(100),
});

Deno.serve(async (req) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  try {
    const user = await requireAuth(req);
    const { email, child_ids, role_category, role_label, inviter_name } =
      bodySchema.parse(await req.json());

    const admin = supabaseAdmin();

    // Authorization re-check: the caller must own the active family that every
    // target child belongs to. The admin client bypasses RLS, so this is manual.
    const { data: ownedChildren, error: childErr } = await admin
      .from("children")
      .select("id, name, families!inner(owner_id, status)")
      .in("id", child_ids);
    if (childErr) throw childErr;

    const childrenData = ownedChildren as unknown as
      | {
          id: string;
          name: string;
          families: {
            owner_id: string;
            status: string;
          } | null;
        }[]
      | null;

    const ownedIds = new Set(
      (childrenData ?? [])
        .filter(
          (c) =>
            c.families?.owner_id === user.id && c.families?.status === "active",
        )
        .map((c) => c.id),
    );
    if (ownedIds.size !== child_ids.length) {
      return err("You can only invite members to your own children.", 403);
    }

    // Resolve details for the invitation email template metadata
    const childNames = (childrenData ?? [])
      .filter((c) => ownedIds.has(c.id))
      .map((c) => c.name)
      .join(", ");

    // Resolve the invitee's account by email, creating it if needed.
    let accountId: string | null = null;
    let createdNewAccount = false;

    const { data: existing, error: lookupErr } = await admin
      .from("profiles")
      .select("id")
      .eq("email", email)
      .maybeSingle();
    if (lookupErr) throw lookupErr;

    if (existing) {
      accountId = existing.id;
    } else {
      // Creates the auth user and sends a set-password invite email.
      // handle_new_user() then creates the matching profile row.
      const { data: invited, error: inviteErr } =
        await admin.auth.admin.inviteUserByEmail(email, {
          data: {
            inviter_name,
            child_names: childNames,
            role_label: role_label || role_category.replace("_", " "),
          },
        });
      if (inviteErr || !invited.user) {
        // A concurrent invite for the same brand-new email wins the race and
        // creates the account first; inviteUserByEmail then fails on the
        // duplicate. Fall back to the account that now exists instead of erroring.
        const { data: raced } = await admin
          .from("profiles")
          .select("id")
          .eq("email", email)
          .maybeSingle();

        if (!raced) {
          throw inviteErr ?? new Error("Failed to create invited account.");
        }
        accountId = raced.id;
      } else {
        accountId = invited.user.id;
        createdNewAccount = true;
      }
    }

    // A family owner already has full access to their own children and must never
    // be a member of them (the DB trigger enforces this too).
    if (accountId === user.id) {
      return err(
        "You already have full access to your own children as the family admin - you can't invite yourself as a member.",
        400,
      );
    }

    // Create a pending membership per child. Every invite - brand-new account or
    // existing - starts 'pending' and must be explicitly accepted by the invitee
    // in the app; there is no auto-approval. Never duplicate (unique on
    // account_id, child_id) and never downgrade an already-accepted membership:
    // existing rows only get their role refreshed, new rows start 'pending'.
    // If any membership write fails after we just minted a brand-new account,
    // that account is rolled back (deleted) so a failed link never leaves an
    // orphaned account holding a dead-end set-password email.
    let declinedChildIds: string[] = [];
    let insertedChildIds: string[] = [];
    try {
      const { data: current, error: curErr } = await admin
        .from("memberships")
        .select("child_id, invite_status")
        .eq("account_id", accountId)
        .in("child_id", child_ids);
      if (curErr) throw curErr;

      const currentMemberships = current as
        | { child_id: string; invite_status: string }[]
        | null;
      const existingChildIds = new Set(
        (currentMemberships ?? []).map((m) => m.child_id),
      );
      // A previously declined invite must be re-openable: reset it to 'pending'
      // so the person can accept again. Never touch already-'accepted' rows.
      declinedChildIds = (currentMemberships ?? [])
        .filter((m) => m.invite_status === "declined")
        .map((m) => m.child_id);

      const toInsert = child_ids
        .filter((id) => !existingChildIds.has(id))
        .map((id) => ({
          account_id: accountId,
          child_id: id,
          role_category,
          role_label: role_label ?? null,
          invited_by: user.id,
          invite_status: "pending" as const,
        }));

      insertedChildIds = toInsert.map((i) => i.child_id);

      if (toInsert.length > 0) {
        const { error: insErr } = await admin
          .from("memberships")
          .insert(toInsert);
        if (insErr) throw insErr;
      }

      if (existingChildIds.size > 0) {
        const { error: updErr } = await admin
          .from("memberships")
          .update({
            role_category,
            role_label: role_label ?? null,
            invited_by: user.id,
          })
          .eq("account_id", accountId)
          .in("child_id", [...existingChildIds]);
        if (updErr) throw updErr;
      }

      // Re-open declined invites (account_id/child_id stay put, so the identity
      // trigger is satisfied).
      if (declinedChildIds.length > 0) {
        const { error: reopenErr } = await admin
          .from("memberships")
          .update({ invite_status: "pending" })
          .eq("account_id", accountId)
          .in("child_id", declinedChildIds);
        if (reopenErr) throw reopenErr;
      }
    } catch (linkErr) {
      if (createdNewAccount && accountId) {
        await admin.auth.admin.deleteUser(accountId);
      }
      throw linkErr;
    }

    // Notify existing accounts about children newly linked OR re-opened after a
    // decline - these are 'pending' and need the invitee to respond. They get
    // BOTH an in-app notification (per child, deep-linkable to Accept/Decline)
    // and an email. Brand-new accounts already got the set-password invite email
    // (and see the same Accept/Decline UI on first login), so they are not
    // re-notified here.
    if (existing) {
      const notifyIds = new Set<string>([
        ...insertedChildIds,
        ...declinedChildIds,
      ]);
      const notifyChildren = (childrenData ?? []).filter((c) =>
        notifyIds.has(c.id),
      );

      if (notifyChildren.length > 0) {
        // In-app notification per child - rides the notifications -> send-push
        // pipeline (push delivered + inbox row). Best-effort: a failed enqueue
        // must not fail the invite, which already succeeded.
        for (const c of notifyChildren) {
          const { error: notifyErr } = await admin.rpc("enqueue_notification", {
            p_title: "New family invitation",
            p_body: `${inviter_name} invited you to ${c.name}`,
            p_recipient_user_id: accountId,
            p_entity_type: "membership_invite",
            p_entity_id: c.id,
            p_data: {
              child_id: c.id,
              role_label: role_label || role_category.replace("_", " "),
            },
          });
          if (notifyErr) {
            console.error(
              "invite-member enqueue_notification error:",
              notifyErr,
            );
          }
        }

        const html = await getInviteExistingMemberHtml({
          inviter_name,
          child_names: notifyChildren.map((c) => c.name).join(", "),
          role_label: role_label || role_category.replace("_", " "),
        });

        await sendEmail({
          to: email,
          subject: "New Family Member Invitation on Famtastic",
          html,
        });
      }
    }

    // created_new_account is intentionally NOT returned: it would reveal to the
    // caller whether the email already had an account (existence enumeration).
    return ok({
      account_id: accountId,
      invited_child_ids: child_ids,
    });
  } catch (e) {
    if (e instanceof AuthError) return err(e.message, 401);
    if (e instanceof z.ZodError)
      return err(e.errors[0]?.message ?? "Invalid request body.", 400);
    console.error("invite-member error:", e);
    return err("Internal server error.", 500);
  }
});
