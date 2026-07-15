export interface ChildModePinResetParams {
  full_name: string;
  reset_url: string;
  expiry_minutes: string;
}

const templateHtml = `<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html lang="en" xmlns="https://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
  <title>Reset your Child Mode PIN</title>
  <link href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@600;700&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <!--[if mso]><style type="text/css">body,table,td,a,h1,p,span{font-family:'Segoe UI',Arial,sans-serif !important;}</style><![endif]-->
</head>
<body style="margin:0;padding:0;background-color:#F5F3FF;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Reset your Famtastic Child Mode PIN. This link expires in {{ expiry_minutes }} minutes.</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#F5F3FF" style="background-color:#F5F3FF;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="480" cellpadding="0" cellspacing="0" border="0" style="width:480px;max-width:480px;background-color:#ffffff;border-radius:20px;border:1px solid #ECE8FA;overflow:hidden;">

          <!-- Header -->
          <tr>
            <td style="padding:36px 40px 4px;text-align:center;">
              <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0"><tr>
                <td bgcolor="#7C5CFF" width="44" height="44" style="width:44px;height:44px;background-color:#7C5CFF;background-image:linear-gradient(135deg,#8B6BFF,#6438E8);border-radius:14px;text-align:center;vertical-align:middle;font-family:'Baloo 2',Verdana,sans-serif;font-size:24px;font-weight:700;color:#ffffff;">&#10022;</td>
                <td style="padding-left:12px;font-family:'Baloo 2','Plus Jakarta Sans',Segoe UI,Helvetica,Arial,sans-serif;font-size:23px;font-weight:700;color:#2B2340;letter-spacing:-0.3px;">Famtastic</td>
              </tr></table>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding:24px 40px 8px;text-align:center;">
              <h1 style="margin:0 0 12px;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:24px;line-height:1.25;font-weight:700;color:#2B2340;">Reset your Child Mode PIN</h1>
              <p style="margin:0 0 20px;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#6B6480;">Hi <strong style="color:#2B2340;">{{ full_name }}</strong>, we received a request to reset the Child Mode PIN for your family. Tap the button below in the Famtastic app to set a new PIN - you won't need the old one.</p>
              <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0"><tr>
                <td bgcolor="#6438E8" style="border-radius:12px;">
                  <a href="{{ reset_url }}" style="display:inline-block;padding:14px 32px;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:12px;">Set a new PIN</a>
                </td>
              </tr></table>
              <p style="margin:20px 0 0;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;line-height:1.6;color:#6B6480;">This link expires in <strong style="color:#2B2340;">{{ expiry_minutes }} minutes</strong> and can be used once. If you didn't request this, you can safely ignore this email - your PIN stays unchanged.</p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:28px 40px 34px;text-align:center;">
              <div style="border-top:1px solid #ECE8FA;padding-top:22px;">
                <p style="margin:0 0 6px;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;line-height:1.5;color:#6B6480;">Made with care for families raising a child with special needs.</p>
                <p style="margin:0;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#A29DB4;">This is an automated security email from Famtastic.</p>
                <p style="margin:14px 0 0;font-family:'Plus Jakarta Sans',-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;color:#C3BFD2;">&copy; Famtastic</p>
              </div>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

export function getChildModePinResetHtml(
  params: ChildModePinResetParams,
): string {
  const data = params as unknown as Record<string, string>;

  // Replace any {{ key }} pattern with the corresponding value from params
  return templateHtml.replace(/\{\{\s*(\w+)\s*\}\}/g, (match, key) => {
    return key in data ? data[key] : match;
  });
}
