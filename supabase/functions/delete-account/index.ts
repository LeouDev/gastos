// Deletes the caller's gastos account: revokes their Sign in with Apple token (App Store requirement),
// then deletes the auth user, which cascades to every synced row.
//
// Body: { "authorizationCode": "<fresh code from Sign in with Apple>" }
// Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 contents), APPLE_CLIENT_ID (bundle id).
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** Apple wants a short-lived ES256 JWT signed with the Sign in with Apple key as the client secret. */
async function appleClientSecret(): Promise<string | null> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const pem = Deno.env.get("APPLE_PRIVATE_KEY");
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  if (!teamId || !keyId || !pem || !clientId) return null;
  const key = await importPKCS8(pem.replace(/\\n/g, "\n"), "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

async function revokeAppleToken(authorizationCode: string): Promise<string> {
  const clientId = Deno.env.get("APPLE_CLIENT_ID")!;
  const secret = await appleClientSecret();
  if (!secret) return "skipped: Apple key not configured";

  // Exchange the fresh authorization code for a refresh token, then revoke it.
  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientId, client_secret: secret, code: authorizationCode, grant_type: "authorization_code" }),
  });
  const tokens = await tokenRes.json();
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!tokenRes.ok || !token) return `token exchange failed: ${tokenRes.status} ${tokens.error ?? ""}`;

  const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId, client_secret: secret, token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  });
  return revokeRes.ok ? "revoked" : `revoke failed: ${revokeRes.status}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Who is asking: the caller's own session (the gateway already verified the JWT).
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error: userError } = await asUser.auth.getUser();
  if (userError || !user) return json({ error: "not signed in" }, 401);

  const { authorizationCode } = await req.json().catch(() => ({}));
  // Revocation failing must not block deletion: the person asked for their data to be gone.
  const apple = typeof authorizationCode === "string" && authorizationCode
    ? await revokeAppleToken(authorizationCode).catch((e) => `error: ${e}`)
    : "skipped: no authorization code";

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return json({ error: error.message, apple }, 500);

  console.log(`deleted ${user.id}; apple: ${apple}`);
  return json({ deleted: true, apple });
});
