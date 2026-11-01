import { handle } from "./velo-api/index.ts";
import { accessToken, hash, now, random, seal } from "./_shared/core.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const reply = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
function environment() {
  Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-only-key");
  Deno.env.set("STRAVA_CLIENT_ID", "123-test");
  Deno.env.set("STRAVA_CLIENT_SECRET", "test-only-secret");
  Deno.env.set("VELO_TOKEN_ENCRYPTION_KEY", btoa("k".repeat(32)));
}
Deno.test("Strava OAuth callback is one-time, owner-bound and requires the handoff proof", async () => {
  environment();
  const original = globalThis.fetch;
  const sessions = new Map<string, any>();
  const tasks: Promise<unknown>[] = [];
  (globalThis as any).EdgeRuntime = {
    waitUntil: (p: Promise<unknown>) => tasks.push(p),
  };
  let exchanges = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/auth/v1/user")) {
      const headers = new Headers(init?.headers);
      return reply({
        id: headers.get("Authorization")?.includes("bob") ? "bob" : "alice",
        email: "fixture@example.invalid",
      });
    }
    if (url === "https://www.strava.com/oauth/token") {
      exchanges++;
      assert(String(init?.body).includes("client_secret=test-only-secret"));
      return reply({
        access_token: "fixture-provider-access",
        refresh_token: "fixture-provider-refresh",
        expires_at: now() + 3600,
        athlete: { id: 42 },
      });
    }
    if (url === "https://www.strava.com/api/v3/athlete") {
      return reply({ id: 42, firstname: "Fixture" });
    }
    if (url.includes("/rest/v1/velo_jobs")) return reply({ id: "fixture-job" });
    const { p_action: action, p_args: args } = JSON.parse(String(init?.body));
    if (action === "rate_limit") return reply({ allowed: true });
    if (action === "connection") return reply(null);
    if (action === "oauth_create") {
      sessions.set(args.hash, { ...args, completed: false });
      return reply(null);
    }
    if (action === "oauth_lock") {
      const row = sessions.get(args.hash);
      if (!row || row.completed) return reply(null);
      row.completed = true;
      return reply(row);
    }
    if (action === "oauth_stage") {
      const row = sessions.get(args.hash);
      assert(row.user_id === "alice");
      assert(!args.connection.token_cipher.includes("fixture-provider-access"));
      row.handoff_hash = args.handoff_hash;
      return reply({ ok: true });
    }
    if (action === "maintenance" || action === "claim_job") return reply(null);
    if (action === "oauth_confirm") {
      const row = sessions.get(args.hash);
      if (
        !row || row.user_id !== args.user_id ||
        row.handoff_hash !== args.handoff_hash ||
        row.challenge !== args.challenge
      ) return reply(null);
      sessions.delete(args.hash);
      return reply({ ok: true });
    }
    throw new Error("Unexpected fixture action: " + action);
  }) as typeof fetch;
  const invoke = (path: string, body: unknown, who = "alice") =>
    handle(
      new Request("https://test-project.supabase.co/functions/v1/velo-api", {
        method: "POST",
        headers: { Authorization: "Bearer test-" + who },
        body: JSON.stringify({ path, method: "POST", body }),
      }),
    );
  try {
    const state = random(), verifier = random() + random();
    const start = await invoke("/api/v1/integrations/strava/authorize", {
      state,
      code_challenge: await hash(verifier),
      scopes: ["activity:read"],
    });
    assert(start.status === 200);
    const data = await start.json();
    const authorization = new URL(data.authorization_url);
    assert(authorization.origin === "https://www.strava.com");
    assert(!JSON.stringify(data).includes("test-only-secret"));
    const callback = new URL(authorization.searchParams.get("redirect_uri")!);
    callback.search = new URLSearchParams({
      state,
      code: "fixture-code",
      scope: "activity:read",
    }).toString();
    const response = await handle(new Request(callback));
    assert(response.status === 302);
    const location = new URL(response.headers.get("Location")!);
    assert(location.protocol === "ultimatebike:");
    assert((await handle(new Request(callback))).status === 400);
    assert(exchanges === 1, "OAuth code exchange must not replay");
    const proof = {
      state,
      handoff: location.searchParams.get("handoff"),
      code_verifier: verifier,
    };
    assert(
      (await invoke("/api/v1/integrations/strava/confirm", proof, "bob"))
        .status === 400,
    );
    assert(
      (await invoke("/api/v1/integrations/strava/confirm", {
        ...proof,
        code_verifier: "wrong",
      })).status === 400,
    );
    assert(
      (await invoke("/api/v1/integrations/strava/confirm", proof)).status ===
        200,
    );
    assert(
      (await invoke("/api/v1/integrations/strava/confirm", proof)).status ===
        400,
    );
  } finally {
    await Promise.allSettled(tasks);
    globalThis.fetch = original;
  }
});
Deno.test("expired Strava token refreshes server-side and revoked permission requires reconnect", async () => {
  environment();
  const original = globalThis.fetch;
  const encrypted = await seal({
    access_token: "expired-fixture-token",
    refresh_token: "fixture-refresh",
  }, "alice");
  let revoked = false, marked = false, saved = false;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    if (String(input) === "https://www.strava.com/oauth/token") {
      return revoked ? reply({}, 400) : reply({
        access_token: "fresh-fixture-token",
        refresh_token: "new-refresh",
        expires_at: now() + 3600,
      });
    }
    if (String(input).endsWith("/rpc/velo_strava_reconnect")) {
      marked = true;
      return reply(true);
    }
    const { p_action: action, p_args: args } = JSON.parse(String(init?.body));
    if (action === "connection") {
      return reply({
        status: "connected",
        generation: "fixture-generation",
        token_cipher: encrypted,
        expires_at: now() - 1,
      });
    }
    if (action === "token_lease") {
      return reply({
        ok: true,
        lease: "fixture-lease",
        generation: "fixture-generation",
      });
    }
    if (action === "token_unlock") return reply(null);
    if (action === "refresh_connection") {
      saved = true;
      assert(args.user_id === "alice");
      return reply({ ok: true });
    }
    if (action === "reconnect") {
      marked = true;
      return reply(null);
    }
    throw new Error("Unexpected fixture operation");
  }) as typeof fetch;
  try {
    assert(await accessToken("alice") === "fresh-fixture-token");
    assert(saved);
    revoked = true;
    let denied = false;
    try {
      await accessToken("alice", true);
    } catch {
      denied = true;
    }
    assert(denied && marked);
  } finally {
    globalThis.fetch = original;
  }
});
