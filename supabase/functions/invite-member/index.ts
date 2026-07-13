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
        throw inviteErr ?? new Error("Failed to create invited account.");
      }
      accountId = invited.user.id;
      createdNewAccount = true;
    }

    // A family owner already has full access to their own children and must never
    // be a member of them (the DB trigger enforces this too).
    if (accountId === user.id) {
      return err(
        "You already have full access to your own children as the family admin - you can't invite yourself as a member.",
        400,
      );
    }

    // Create a pending membership per child. Never duplicate (unique on
    // account_id, child_id) and never downgrade an already-accepted membership:
    // existing rows only get their role refreshed, new rows start 'pending'.
    const { data: current, error: curErr } = await admin
      .from("memberships")
      .select("child_id")
      .eq("account_id", accountId)
      .in("child_id", child_ids);
    if (curErr) throw curErr;

    const currentMemberships = current as { child_id: string }[] | null;
    const existingChildIds = new Set(
      (currentMemberships ?? []).map((m) => m.child_id),
    );

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

    if (existing && toInsert.length > 0) {
      const newChildNames = (childrenData ?? [])
        .filter((c) => toInsert.some((ins) => ins.child_id === c.id))
        .map((c) => c.name)
        .join(", ");

      if (newChildNames) {
        const html = await getInviteExistingMemberHtml({
          inviter_name,
          child_names: newChildNames,
          role_label: role_label || role_category.replace("_", " "),
        });

        await sendEmail({
          to: email,
          subject: "New Family Member Invitation on Famtastic",
          html,
        });
      }
    }

    return ok({
      account_id: accountId,
      invited_child_ids: child_ids,
      created_new_account: createdNewAccount,
    });
  } catch (e) {
    if (e instanceof AuthError) return err(e.message, 401);
    if (e instanceof z.ZodError)
      return err(e.errors[0]?.message ?? "Invalid request body.", 400);
    console.error("invite-member error:", e);
    return err("Internal server error.", 500);
  }
});
