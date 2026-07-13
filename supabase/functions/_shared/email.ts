import { SMTPClient } from "denomailer";

export interface SendEmailParams {
  to: string;
  subject: string;
  html: string;
}

/**
 * Provider-agnostic transactional email over SMTP.
 *
 * Reads the SAME SMTP credentials GoTrue uses for auth emails
 * (config.toml -> [auth.email.smtp], all sourced from .env), so switching
 * providers - Resend today, Amazon SES tomorrow, anything with an SMTP
 * endpoint - is a `.env` change with NO code change here.
 *
 * Env vars (shared with the auth mailer):
 *   SMTP_HOST         e.g. smtp.resend.com | email-smtp.us-east-1.amazonaws.com
 *   SMTP_PORT         465 = implicit TLS (default) | 587/2587 = STARTTLS
 *   SMTP_USER         "resend" for Resend | the IAM SMTP username for SES
 *   SMTP_PASS         API key / SES SMTP password
 *   SMTP_ADMIN_EMAIL  From address (must be a verified sender/domain)
 *   SMTP_SENDER_NAME  Display name (default "Famtastic")
 *
 * No-ops with a warning when SMTP is not configured, mirroring the previous
 * SendGrid helper so local dev without email set up still works.
 */
export async function sendEmail(params: SendEmailParams): Promise<void> {
  const { to, subject, html } = params;

  const host = Deno.env.get("SMTP_HOST");
  const user = Deno.env.get("SMTP_USER");
  const pass = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("SMTP_ADMIN_EMAIL");

  if (
    !host ||
    !user ||
    !pass ||
    !from ||
    pass === "re_your_resend_api_key" // .env.example placeholder
  ) {
    console.warn(
      "SMTP is not configured (need SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_ADMIN_EMAIL). Skipping transactional email.",
    );
    return;
  }

  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const senderName = Deno.env.get("SMTP_SENDER_NAME") ?? "Famtastic";

  const client = new SMTPClient({
    connection: {
      hostname: host,
      port,
      // 465 connects over implicit TLS; 587/2587 start plaintext then STARTTLS.
      tls: port === 465,
      auth: { username: user, password: pass },
    },
  });

  try {
    await client.send({
      from: `${senderName} <${from}>`,
      to,
      subject,
      content: "auto", // auto-generate a text/plain part from the HTML
      html,
    });
    console.log(`Successfully sent transactional email to ${to}`);
  } catch (err) {
    console.error("Failed to dispatch transactional email over SMTP:", err);
  } finally {
    await client.close();
  }
}
