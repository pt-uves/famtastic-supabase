// FCM HTTP v1 delivery. Mints an OAuth2 access token from a Google service
// account (RS256-signed JWT, cached until near expiry) and sends per-token
// pushes. The legacy FCM server-key API is dead, so this uses the v1 endpoint.
//
// Required env (set via `supabase secrets set` / .env):
//   FCM_PROJECT_ID   - Firebase project id
//   FCM_CLIENT_EMAIL - service account client_email
//   FCM_PRIVATE_KEY  - service account private_key (PEM; literal \n allowed)

const TOKEN_URI = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

type SendResult = {
  ok: boolean;
  // Token is dead (uninstalled / invalid) and should be pruned.
  unregistered: boolean;
  // Number of send attempts made (>=1).
  attempts: number;
  error?: string;
};

// Built-in retry: transient FCM failures (5xx, 429, network) are retried within
// this single invocation with exponential backoff. Permanent failures (dead
// token, 4xx) short-circuit immediately.
const MAX_ATTEMPTS = 3;
const BACKOFF_MS = [400, 1200]; // waits before attempt 2 and 3

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// --- OAuth token cache -----------------------------------------------------

let cachedToken: string | null = null;
let cachedExpiry = 0; // epoch ms

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

async function getAccessToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && now < cachedExpiry - 60_000) return cachedToken;

  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FCM_PRIVATE_KEY");
  if (!clientEmail || !privateKey) {
    throw new Error("FCM service account env not configured");
  }

  const iat = Math.floor(now / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: clientEmail,
    scope: SCOPE,
    aud: TOKEN_URI,
    iat,
    exp: iat + 3600,
  };
  const enc = new TextEncoder();
  const signingInput = `${b64url(enc.encode(JSON.stringify(header)))}.${
    b64url(enc.encode(JSON.stringify(claim)))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(signingInput),
  );
  const jwt = `${signingInput}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch(TOKEN_URI, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json() as { access_token: string; expires_in: number };
  cachedToken = json.access_token;
  cachedExpiry = now + json.expires_in * 1000;
  return cachedToken;
}

// --- Send ------------------------------------------------------------------

// Deliver one message to one device token via FCM HTTP v1, with built-in retry
// on transient failures. Returns once delivered or permanently failed / retries
// exhausted.
export async function sendPush(
  deviceToken: string,
  title: string,
  body: string | null,
  data: Record<string, unknown>,
  priority: "normal" | "high" = "normal",
): Promise<SendResult> {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  if (!projectId) {
    return { ok: false, unregistered: false, attempts: 0, error: "FCM_PROJECT_ID unset" };
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch (e) {
    return { ok: false, unregistered: false, attempts: 0, error: String(e) };
  }

  // FCM data values must be strings.
  const stringData: Record<string, string> = {};
  for (const [k, v] of Object.entries(data ?? {})) {
    stringData[k] = typeof v === "string" ? v : JSON.stringify(v);
  }

  // Per-platform overrides. high => wake the device now, sound + time-sensitive
  // interruption (SOS-class). normal => default priority.
  const message: Record<string, unknown> = {
    token: deviceToken,
    notification: { title, body: body ?? "" },
    data: stringData,
  };
  if (priority === "high") {
    message.android = {
      priority: "high",
      notification: { sound: "default", channel_id: "high_priority" },
    };
    message.apns = {
      headers: { "apns-priority": "10" },
      payload: { aps: { sound: "default", "interruption-level": "time-sensitive" } },
    };
  } else {
    message.android = { priority: "normal" };
  }
  const payload = JSON.stringify({ message });

  let lastError = "delivery failed";
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: payload,
        },
      );

      if (res.ok) return { ok: true, unregistered: false, attempts: attempt };

      const text = await res.text();
      // UNREGISTERED / INVALID_ARGUMENT on the token => prune it, never retry.
      const unregistered = res.status === 404 ||
        /UNREGISTERED|NOT_FOUND|INVALID_ARGUMENT/i.test(text);
      lastError = `${res.status} ${text}`;
      // Permanent: dead token, or any 4xx except 429 (rate limit). Stop.
      if (unregistered || (res.status >= 400 && res.status < 500 && res.status !== 429)) {
        return { ok: false, unregistered, attempts: attempt, error: lastError };
      }
      // else transient (5xx / 429): fall through to retry.
    } catch (e) {
      lastError = String(e); // network error: transient, retry.
    }

    if (attempt < MAX_ATTEMPTS) await sleep(BACKOFF_MS[attempt - 1]);
  }

  return { ok: false, unregistered: false, attempts: MAX_ATTEMPTS, error: lastError };
}
