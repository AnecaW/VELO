import { createClient } from "npm:@supabase/supabase-js@2.118.0";

export const now = () => Math.floor(Date.now() / 1000);
export class Problem extends Error {
  constructor(
    public status: number,
    message: string,
    public code = "request_failed",
    public retry = 0,
    public uncertain = false,
  ) {
    super(message);
  }
}
export const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
export function errorResponse(e: unknown) {
  const p = e instanceof Problem ? e : new Problem(
    503,
    "VELO is tijdelijk niet bereikbaar. Probeer later opnieuw.",
  );
  // Only controlled codes/statuses: never raw exceptions, URLs, tokens or GPS.
  console.warn(
    JSON.stringify({ event: "api_error", code: p.code, status: p.status }),
  );
  return json({ error: { code: p.code, message: p.message } }, p.status);
}
export function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}
export async function checked<T>(
  request: PromiseLike<{ data: T; error: unknown }>,
): Promise<T> {
  const r = await request;
  if (r.error) {
    const code = (r.error as { code?: unknown }).code;
    console.warn(
      JSON.stringify({
        event: "database_error",
        code: typeof code === "string" && /^[A-Z0-9]{5}$/.test(code)
          ? code
          : "unknown",
      }),
    );
    throw new Problem(
      503,
      "Opslaan is tijdelijk niet mogelijk.",
      "database_unavailable",
    );
  }
  return r.data;
}
export async function privateCall(
  action: string,
  args: Record<string, unknown> = {},
) {
  return await checked(
    admin().rpc("velo_private_call", { p_action: action, p_args: args }),
  );
}
export async function requireUser(req: Request) {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new Problem(401, "Meld je opnieuw aan.");
  }
  const { data, error } = await admin().auth.getUser(authorization.slice(7));
  if (error || !data.user) throw new Problem(401, "Meld je opnieuw aan.");
  return data.user;
}
export async function limit(key: string, count: number, window = 3600) {
  const result = await privateCall("rate_limit", { key, limit: count, window });
  if (!result?.allowed) {
    throw new Problem(
      429,
      "Te veel verzoeken. Probeer later opnieuw.",
      "rate_limit",
    );
  }
}
export const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
export const unb64 = (value: string) =>
  Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
export const random = () =>
  b64(crypto.getRandomValues(new Uint8Array(32))).replaceAll("+", "-")
    .replaceAll("/", "_").replaceAll("=", "");
export async function hash(value: string) {
  return b64(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  )
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
async function encryptionKey() {
  const key = Deno.env.get("STRAVA_TOKEN_ENCRYPTION_KEY") ??
    Deno.env.get("VELO_TOKEN_ENCRYPTION_KEY");
  if (!key) {
    throw new Problem(
      503,
      "De koppeling is nog niet beschikbaar.",
      "not_configured",
    );
  }
  return await crypto.subtle.importKey("raw", unb64(key), "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}
export async function seal(value: unknown, owner: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(owner) },
    await encryptionKey(),
    new TextEncoder().encode(JSON.stringify(value)),
  );
  return b64(iv) + "." + b64(new Uint8Array(cipher));
}
export async function unseal(value: string, owner: string) {
  const [iv, data] = value.split(".");
  const raw = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: unb64(iv),
      additionalData: new TextEncoder().encode(owner),
    },
    await encryptionKey(),
    unb64(data),
  );
  return JSON.parse(new TextDecoder().decode(raw));
}
export const missingConfiguration = () => [
  ...(!Deno.env.get("STRAVA_CLIENT_ID") ? ["STRAVA_CLIENT_ID"] : []),
  ...(!Deno.env.get("STRAVA_CLIENT_SECRET") ? ["STRAVA_CLIENT_SECRET"] : []),
  ...(!Deno.env.get("STRAVA_TOKEN_ENCRYPTION_KEY") &&
      !Deno.env.get("VELO_TOKEN_ENCRYPTION_KEY")
    ? ["STRAVA_TOKEN_ENCRYPTION_KEY"]
    : []),
];
export const configured = () => missingConfiguration().length === 0;
export const callback = () =>
  Deno.env.get("SUPABASE_URL") + "/functions/v1/velo-api/oauth/strava/callback";
export async function connection(owner: string) {
  return await privateCall("connection", { user_id: owner });
}
export async function saveConnection(
  owner: string,
  token: Record<string, unknown>,
  previous?: Record<string, unknown>,
  oauthHash?: string,
) {
  await privateCall("save_connection", {
    user_id: owner,
    oauth_hash: oauthHash,
    athlete: token.athlete ?? previous?.athlete ?? {},
    scope: token.scope ?? previous?.scope ?? "",
    token_cipher: await seal({
      access_token: token.access_token,
      refresh_token: token.refresh_token,
    }, owner),
    expires_at: token.expires_at,
  });
}
export async function exchange(form: Record<string, string>) {
  const response = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    redirect: "error",
    body: new URLSearchParams({
      client_id: Deno.env.get("STRAVA_CLIENT_ID")!,
      client_secret: Deno.env.get("STRAVA_CLIENT_SECRET")!,
      ...form,
    }),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    if (response.status === 429) {
      throw new Problem(429, "Strava API-limiet bereikt.", "rate_limit", 900);
    }
    if (response.status >= 500) {
      throw new Problem(
        503,
        "Strava is tijdelijk niet bereikbaar.",
        "strava_unavailable",
        120,
      );
    }
    const error = await response.json().catch(() => ({}));
    if (
      error.errors?.some((e: Record<string, unknown>) =>
        e.resource === "Application" || e.field === "client_id" ||
        e.field === "client_secret"
      )
    ) {
      throw new Problem(
        503,
        "De Strava-appconfiguratie klopt niet. Neem contact op met de beheerder.",
        "client_configuration",
      );
    }
    throw new Problem(
      401,
      "Strava-toestemming is verlopen. Verbind opnieuw.",
      "strava_auth",
    );
  }
  const token = await response.json();
  if (
    typeof token.access_token !== "string" ||
    typeof token.refresh_token !== "string" ||
    !Number.isFinite(token.expires_at)
  ) {
    throw new Problem(
      503,
      "Strava gaf geen geldige tokens terug.",
      "invalid_provider_response",
      120,
    );
  }
  return token;
}
export async function accessToken(
  owner: string,
  force = false,
): Promise<string> {
  let c = await connection(owner);
  if (!c || c.status !== "connected") {
    throw new Problem(401, "Verbind Strava opnieuw.", "strava_auth");
  }
  let tokens = await unseal(c.token_cipher, owner);
  if (!force && c.expires_at > now() + 60) return tokens.access_token;
  const leased = await privateCall("token_lease", { user_id: owner });
  if (!leased?.ok) {
    for (let i = 0; i < 4; i++) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      const updated = await connection(owner);
      if (
        updated?.status === "connected" && updated.expires_at > now() + 60 &&
        updated.token_cipher !== c.token_cipher
      ) return (await unseal(updated.token_cipher, owner)).access_token;
    }
    throw new Problem(
      503,
      "Strava vernieuwt de verbinding. Probeer opnieuw.",
      "refresh_busy",
      2,
    );
  }
  try {
    c = await connection(owner);
    if (!c || c.status !== "connected") {
      throw new Problem(401, "Strava is ontkoppeld.", "strava_auth");
    }
    tokens = await unseal(c.token_cipher, owner);
    if (!force && c.expires_at > now() + 60) return tokens.access_token;
    const next = await exchange({
      grant_type: "refresh_token",
      refresh_token: tokens.refresh_token,
    });
    const saved = await privateCall("refresh_connection", {
      user_id: owner,
      lease: leased.lease,
      generation: leased.generation,
      token_cipher: await seal({
        access_token: next.access_token,
        refresh_token: next.refresh_token,
      }, owner),
      expires_at: next.expires_at,
    });
    if (!saved?.ok) {
      throw new Problem(
        409,
        "De Strava-verbinding is gewijzigd.",
        "connection_changed",
      );
    }
    return next.access_token;
  } catch (e) {
    if (e instanceof Problem && e.status === 401) {
      await markReconnect(owner, leased.generation);
    }
    throw e;
  } finally {
    await privateCall("token_unlock", { user_id: owner, lease: leased.lease });
  }
}
export async function strava(
  owner: string,
  path: string,
  init: RequestInit = {},
) {
  const generation = (await connection(owner))?.generation;
  const blocked = await privateCall("strava_allowed");
  if (blocked?.until > now()) {
    throw new Problem(
      429,
      "Strava API-limiet bereikt.",
      "rate_limit",
      blocked.until - now(),
    );
  }
  // Global application budget across all users, including read requests.
  await limit("strava:15m:" + Math.floor(now() / 900), 90, 900);
  await limit("strava:day:" + Math.floor(now() / 86400), 900, 86400);
  let token = await accessToken(owner);
  let response: Response;
  try {
    response = await fetch("https://www.strava.com/api/v3/" + path, {
      ...init,
      headers: { ...init.headers, Authorization: "Bearer " + token },
      redirect: "error",
      signal: AbortSignal.timeout(25000),
    });
    if (response.status === 401 && (!init.method || init.method === "GET")) {
      token = await accessToken(owner, true);
      response = await fetch("https://www.strava.com/api/v3/" + path, {
        ...init,
        headers: { Authorization: "Bearer " + token },
        signal: AbortSignal.timeout(25000),
      });
    }
  } catch (e) {
    if (e instanceof Problem) throw e;
    throw new Problem(
      503,
      "Strava is tijdelijk niet bereikbaar.",
      "strava_unavailable",
      60,
      init.method === "POST",
    );
  }
  if (response.status === 401) {
    if (generation) await markReconnect(owner, generation);
    throw new Problem(
      401,
      "Strava mist toestemming. Verbind opnieuw.",
      "strava_auth",
    );
  }
  await observeRateLimits(response);
  if (response.status === 403) {
    throw new Problem(
      403,
      "Strava geeft geen toegang tot deze gegevens. Controleer de verleende rechten.",
      "scope_missing",
    );
  }
  if (response.status === 404) {
    throw new Problem(
      404,
      "Deze Strava-activiteit bestaat niet meer of is privé.",
      "not_found",
    );
  }
  if (response.status === 429) {
    await privateCall("strava_block", {
      until: now() +
        Math.max(900, Number(response.headers.get("retry-after")) || 0),
    });
    throw new Problem(
      429,
      "Strava API-limiet bereikt. Later wordt opnieuw geprobeerd.",
      "rate_limit",
      Math.max(900, Number(response.headers.get("retry-after")) || 0),
    );
  }
  if (response.status === 400 && path === "uploads") return response;
  if (response.status === 400) {
    throw new Problem(
      422,
      "Strava heeft de aanvraag geweigerd.",
      "provider_rejected",
    );
  }
  if (!response.ok) {
    throw new Problem(
      503,
      "Strava heeft het verzoek niet voltooid.",
      "strava_unavailable",
      300,
      init.method === "POST",
    );
  }
  return response;
}

async function observeRateLimits(response: Response) {
  let until = 0;
  for (const prefix of ["x-ratelimit", "x-readratelimit"]) {
    const limits = (response.headers.get(prefix + "-limit") ?? "").split(",")
      .map(Number);
    const usage = (response.headers.get(prefix + "-usage") ?? "").split(",")
      .map(Number);
    if (limits[0] > 0 && usage[0] >= limits[0] - 3) {
      until = Math.max(until, (Math.floor(now() / 900) + 1) * 900);
    }
    if (limits[1] > 0 && usage[1] >= limits[1] - 5) {
      until = Math.max(until, (Math.floor(now() / 86400) + 1) * 86400);
    }
  }
  if (until > 0) await privateCall("strava_block", { until });
}
export function capabilities(scope: string) {
  const scopes = new Set(scope.split(","));
  return {
    activities: scopes.has("activity:read") || scopes.has("activity:read_all"),
    uploads: scopes.has("activity:write"),
    routes: scopes.has("read") || scopes.has("read_all"),
    route_export: false,
  };
}

export async function markReconnect(owner: string, generation: string) {
  return await checked(
    admin().rpc("velo_strava_reconnect", {
      p_user_id: owner,
      p_generation: generation,
    }),
  );
}
