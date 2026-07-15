// send-push
// Delivers pending notifications as device pushes via FCM HTTP v1, then marks
// them sent/failed.
//
// SERVER-INVOKED ONLY. The database calls this after a notification row is
// inserted (AFTER INSERT trigger -> pg_net). Authenticated with the shared
// PUSH_WEBHOOK_SECRET header - NEVER the service-role key, which must never leave
// the server. Clients do not call this.
//
// Retry is built in: each FCM send retries transient failures with backoff
// inside this invocation (see _shared/fcm.ts). There is no polling cron.
//
// Optional JSON body scopes what to send:
//   { "notification_id": "<uuid>" }    -> that single notification (trigger path)
//   { "notification_ids": ["<uuid>"] } -> those notifications (manual re-drive)
//   { "prompt_id": "<uuid>" }          -> notifications for that check-in prompt
//   {} (or none)                       -> every still-pending notification
//
// Token resolution:
//   - child recipient : the token whose device_id = children.child_mode_device_id
//                       (the device currently running that child's Child Mode)
//   - adult recipient : every token registered to that account

import { type SupabaseClient } from "@supabase/supabase-js";
import { handleCors } from "../_shared/cors.ts";
import { sendPush } from "../_shared/fcm.ts";
import { err, ok } from "../_shared/response.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";

const BATCH = 100;

type Notification = {
  id: string;
  recipient_user_id: string | null;
  recipient_child_id: string | null;
  title: string;
  body: string | null;
  data: Record<string, unknown>;
  priority: "normal" | "high";
};

type TokenRow = { id: string; token: string };

// Length-independent constant-time string comparison, so validating the webhook
// secret leaks no timing signal about how many leading characters matched.
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  // Fold the length difference into the accumulator instead of returning early,
  // keeping the comparison time independent of where the strings first differ.
  let mismatch = ab.length ^ bb.length;
  for (let i = 0; i < ab.length; i++) {
    mismatch |= ab[i] ^ bb[i % bb.length];
  }
  return mismatch === 0;
}

Deno.serve(async (req) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  const secret = req.headers.get("x-webhook-secret");
  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!expected || !secret || !timingSafeEqual(secret, expected)) {
    return err("Unauthorized.", 401);
  }

  try {
    const admin = supabaseAdmin();

    // Optional scoping body. Absent/invalid body => drain all pending.
    let body: {
      notification_id?: string;
      notification_ids?: string[];
      prompt_id?: string;
    } = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const ids =
      body.notification_ids ??
      (body.notification_id ? [body.notification_id] : undefined);

    let query = admin
      .from("notifications")
      .select(
        "id, recipient_user_id, recipient_child_id, title, body, data, priority",
      )
      .eq("status", "pending");

    if (ids?.length) {
      query = query.in("id", ids);
    } else if (body.prompt_id) {
      query = query
        .eq("entity_type", "check_in_prompt")
        .eq("entity_id", body.prompt_id);
    }

    const { data: pending, error: pErr } = await query
      .order("created_at", { ascending: true })
      .limit(BATCH);
    if (pErr) throw pErr;

    const rows = (pending ?? []) as Notification[];
    let sent = 0;
    let failed = 0;

    // Resolve every recipient's tokens in a handful of batched queries up front,
    // rather than per-notification (which was an N+1 across the batch).
    const tokensByNotification = await resolveTokensBatch(admin, rows);

    for (const n of rows) {
      const tokens = tokensByNotification.get(n.id) ?? [];

      if (tokens.length === 0) {
        await markFailed(admin, n.id, "no registered device token");
        failed++;
        continue;
      }

      const errors: string[] = [];
      // Fan the sends for this notification out concurrently across its devices.
      const results = await Promise.all(
        tokens.map((t) =>
          sendPush(t.token, n.title, n.body, n.data, n.priority).then((r) => ({
            t,
            r,
          })),
        ),
      );

      let delivered = false;
      for (const { t, r } of results) {
        if (r.ok) {
          delivered = true;
        } else {
          if (r.error) errors.push(r.error);
          if (r.unregistered) {
            // Dead token: remove it so it is not retried forever.
            await admin.from("push_tokens").delete().eq("id", t.id);
          }
        }
      }

      if (delivered) {
        await admin
          .from("notifications")
          .update({ status: "sent", sent_at: new Date().toISOString() })
          .eq("id", n.id);
        sent++;
      } else {
        // FCM already retried transient failures in-invocation; this is terminal.
        const lastError = errors.join("; ").slice(0, 500) || "delivery failed";
        await markFailed(admin, n.id, lastError);
        failed++;
      }
    }

    return ok({ processed: rows.length, sent, failed });
  } catch (e) {
    console.error("send-push error:", e);
    return err("Internal server error.", 500);
  }
});

async function markFailed(admin: SupabaseClient, id: string, error: string) {
  await admin
    .from("notifications")
    .update({
      status: "failed",
      sent_at: new Date().toISOString(),
      last_error: error.slice(0, 500),
    })
    .eq("id", id);
}

// Resolve the target device tokens for every notification in the batch using a
// fixed number of queries (independent of batch size). Child recipients route to
// the token(s) on the device running that child's Child Mode; adult recipients
// route to every token registered to the account.
async function resolveTokensBatch(
  admin: SupabaseClient,
  rows: Notification[],
): Promise<Map<string, TokenRow[]>> {
  const childIds = [
    ...new Set(rows.map((n) => n.recipient_child_id).filter(Boolean)),
  ] as string[];
  const userIds = [
    ...new Set(rows.map((n) => n.recipient_user_id).filter(Boolean)),
  ] as string[];

  // child_id -> child_mode_device_id
  const deviceByChild = new Map<string, string>();
  if (childIds.length) {
    const { data: children } = await admin
      .from("children")
      .select("id, child_mode_device_id")
      .in("id", childIds);
    for (const c of (children ?? []) as {
      id: string;
      child_mode_device_id: string | null;
    }[]) {
      if (c.child_mode_device_id) {
        deviceByChild.set(c.id, c.child_mode_device_id);
      }
    }
  }

  // device_id -> tokens (for child-mode delivery)
  const tokensByDevice = new Map<string, TokenRow[]>();
  const deviceIds = [...new Set(deviceByChild.values())];
  if (deviceIds.length) {
    const { data } = await admin
      .from("push_tokens")
      .select("id, token, device_id")
      .in("device_id", deviceIds);
    for (const t of (data ?? []) as (TokenRow & { device_id: string })[]) {
      const list = tokensByDevice.get(t.device_id) ?? [];
      list.push({ id: t.id, token: t.token });
      tokensByDevice.set(t.device_id, list);
    }
  }

  // user_id -> tokens (for adult delivery)
  const tokensByUser = new Map<string, TokenRow[]>();
  if (userIds.length) {
    const { data } = await admin
      .from("push_tokens")
      .select("id, token, user_id")
      .in("user_id", userIds);
    for (const t of (data ?? []) as (TokenRow & { user_id: string })[]) {
      const list = tokensByUser.get(t.user_id) ?? [];
      list.push({ id: t.id, token: t.token });
      tokensByUser.set(t.user_id, list);
    }
  }

  const out = new Map<string, TokenRow[]>();
  for (const n of rows) {
    if (n.recipient_child_id) {
      const deviceId = deviceByChild.get(n.recipient_child_id);
      out.set(n.id, deviceId ? (tokensByDevice.get(deviceId) ?? []) : []);
    } else if (n.recipient_user_id) {
      out.set(n.id, tokensByUser.get(n.recipient_user_id) ?? []);
    } else {
      out.set(n.id, []);
    }
  }
  return out;
}
