import { accessToken, now, seal, strava, unseal } from "./_shared/core.ts";
import {
  enqueue,
  gpx,
  stravaSportType,
  synchronize,
  upload,
  webhook,
} from "./_shared/jobs.ts";
import { handle as receive } from "./velo-webhook/index.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const reply = (
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
function environment() {
  Deno.env.set("SUPABASE_URL", "https://fixture.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-service");
  Deno.env.set("STRAVA_CLIENT_ID", "123");
  Deno.env.set("STRAVA_CLIENT_SECRET", "fixture-client-secret");
  Deno.env.set("VELO_TOKEN_ENCRYPTION_KEY", btoa("k".repeat(32)));
}
async function fixtureConnection() {
  return {
    status: "connected",
    scope: "read,activity:read,activity:write",
    athlete: { id: 42 },
    generation: "generation-1",
    expires_at: now() + 3600,
    token_cipher: await seal({
      access_token: "fixture-access",
      refresh_token: "fixture-refresh",
    }, "alice"),
    preferences: {
      enabled: true,
      activities: true,
      routes: false,
      uploads: false,
      automatic: false,
    },
    cursor: 0,
    full_sync_at: 0,
    sync_window: {},
  };
}
Deno.test("incremental import checkpoints a stable window and resumes page 3 without duplicates", async () => {
  environment();
  const original = fetch;
  const c: Record<string, any> = await fixtureConnection();
  const saved = new Set<number>();
  const pages: number[] = [];
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    if (url.startsWith("https://www.strava.com/api/v3/athlete/activities")) {
      const p = Number(new URL(url).searchParams.get("page"));
      pages.push(p);
      return reply(
        Array.from(
          { length: p <= 2 ? 50 : 1 },
          (_, i) => ({
            id: (p - 1) * 50 + i + 1,
            athlete: { id: 42 },
            start_date: "2026-11-01T10:00:00Z",
            distance: 100,
            moving_time: 20,
            elapsed_time: 25,
          }),
        ),
      );
    }
    const { p_action: a, p_args: v } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(structuredClone(c));
    if (a === "strava_allowed") return reply(null);
    if (a === "rate_limit") return reply({ allowed: true });
    if (a === "sync_window") {
      c.sync_window = structuredClone(v.window);
      return reply({ ok: true });
    }
    if (a === "save_cache") {
      assert(v.generation === c.generation);
      saved.add(v.data.id);
      return reply(null);
    }
    if (a === "sync_complete") {
      assert(v.cursor === c.sync_window.before);
      c.cursor = v.cursor;
      c.sync_window = {};
      return reply({ ok: true });
    }
    throw new Error("Unexpected fixture operation");
  }) as typeof fetch;
  try {
    assert(await synchronize("alice") === false);
    const before = c.sync_window.before;
    assert(c.sync_window.page === 3 && saved.size === 100);
    assert(await synchronize("alice") === true);
    assert(c.cursor === before && Number(saved.size) === 101);
    assert(pages.join(",") === "1,2,3");
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("manual upload works with automatic disabled and resumes by upload ID, never POSTs twice", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  let posts = 0;
  const updates: Record<string, any>[] = [];
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    if (url === "https://www.strava.com/api/v3/uploads") {
      posts++;
      assert(init?.body instanceof FormData);
      assert(String(init.body.get("external_id")).startsWith("velo-"));
      assert(init.body.get("sport_type") === "GravelRide");
      assert(!init.body.has("type"));
      return reply({ id: 101 }, 201);
    }
    if (url === "https://www.strava.com/api/v3/uploads/101") {
      return reply({ id: 101, activity_id: 202 });
    }
    if (url.includes("/rest/v1/velo_documents")) {
      return reply({
        payload: { id: "ride", name: "Fixture ride", bikeType: "gravel" },
      });
    }
    if (url.includes("/rest/v1/velo_tracks")) {
      return reply({
        points: [[51, 4, 10, "2026-11-01T10:00:00Z"], [
          51.01,
          4.01,
          11,
          "2026-11-01T10:01:00Z",
        ]],
      });
    }
    if (url.includes("/rest/v1/velo_jobs")) {
      const value = JSON.parse(String(init?.body));
      updates.push(value);
      return reply({ id: "job" });
    }
    const { p_action: a } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "rate_limit") return reply({ allowed: true });
    if (a === "strava_allowed" || a === "remove_cached_activity") {
      return reply(null);
    }
    throw new Error("Unexpected fixture operation");
  }) as typeof fetch;
  try {
    const job = {
      id: "job",
      user_id: "alice",
      job_key: "ride",
      lease_token: "lease",
      automatic: false,
      result: null,
    };
    assert(await upload(job) === false);
    assert(posts === 1);
    const accepted = updates.find((u) => u.result?.upload_id === 101)!;
    assert(accepted.next_at >= now() + 29);
    const resumed = { ...job, result: accepted.result };
    assert(await upload(resumed) === true);
    assert(posts === 1);
    assert(updates.some((u) => u.result?.activity_id === 202));
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("a persisted uncertain upload intent stops before another provider upload", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  let provider = 0;
  globalThis.fetch = (async (input, init) => {
    if (String(input).startsWith("https://www.strava.com")) {
      provider++;
      throw new Error("Must not upload");
    }
    const { p_action: a } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    let denied = false;
    try {
      await upload({
        user_id: "alice",
        result: { upload_intent: true },
        automatic: false,
      });
    } catch (e) {
      denied = (e as { code: string }).code === "uncertain_upload";
    }
    assert(denied && provider === 0);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("concurrent refresh uses one lease and stores the newest refresh token", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  c.expires_at = now() - 1;
  let leased = false, exchanges = 0;
  globalThis.fetch = (async (input, init) => {
    if (String(input) === "https://www.strava.com/oauth/token") {
      exchanges++;
      await new Promise((r) => setTimeout(r, 25));
      return reply({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_at: now() + 3600,
      });
    }
    const { p_action: a, p_args: v } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "token_lease") {
      if (leased) return reply(null);
      leased = true;
      return reply({ ok: true, lease: "lease-1", generation: c.generation });
    }
    if (a === "token_unlock") {
      assert(v.lease === "lease-1");
      leased = false;
      return reply(null);
    }
    if (a === "refresh_connection") {
      assert(v.lease === "lease-1" && v.generation === c.generation);
      c.token_cipher = v.token_cipher;
      c.expires_at = v.expires_at;
      return reply({ ok: true });
    }
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    const tokens = await Promise.all([
      accessToken("alice"),
      accessToken("alice"),
    ]);
    assert(tokens.every((v) => v === "new-access"));
    assert(exchanges === 1);
    assert(
      (await unseal(c.token_cipher, "alice")).refresh_token === "new-refresh",
    );
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("an old refresh cannot overwrite or disconnect a reconnected account", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  c.expires_at = now() - 1;
  let disconnected = false;
  globalThis.fetch = (async (input, init) => {
    if (String(input) === "https://www.strava.com/oauth/token") {
      return reply({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_at: now() + 3600,
      });
    }
    if (String(input).includes("velo_strava_reconnect")) {
      disconnected = true;
      return reply(false);
    }
    const { p_action: a } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "token_lease") {
      return reply({
        ok: true,
        lease: "old-lease",
        generation: "old-generation",
      });
    }
    if (a === "refresh_connection") return reply(null);
    if (a === "token_unlock") return reply(null);
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    let denied = false;
    try {
      await accessToken("alice");
    } catch {
      denied = true;
    }
    assert(denied && !disconnected);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("provider rate headers stop subsequent requests until the natural window", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  let until = 0, calls = 0;
  globalThis.fetch = (async (input, init) => {
    if (String(input).startsWith("https://www.strava.com/api/v3/")) {
      calls++;
      return reply({ id: 42 }, 200, {
        "x-readratelimit-limit": "100,1000",
        "x-readratelimit-usage": "98,200",
      });
    }
    const { p_action: a, p_args: v } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "rate_limit") return reply({ allowed: true });
    if (a === "strava_allowed") return reply({ until });
    if (a === "strava_block") {
      until = v.until;
      return reply(null);
    }
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    await strava("alice", "athlete");
    assert(until > now());
    let limited = false;
    try {
      await strava("alice", "athlete");
    } catch (e) {
      limited = (e as { status: number }).status === 429;
    }
    assert(limited && calls === 1);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("webhook verifies challenge, ignores other subscriptions and deduplicates persisted events", async () => {
  environment();
  Deno.env.set("STRAVA_WEBHOOK_VERIFY_TOKEN", "fixture-verify");
  Deno.env.set("STRAVA_WEBHOOK_SUBSCRIPTION_ID", "123");
  const original = fetch,
    tasks: Promise<unknown>[] = [],
    events = new Set<string>();
  (globalThis as any).EdgeRuntime = {
    waitUntil: (p: Promise<unknown>) => tasks.push(p),
  };
  globalThis.fetch = (async (_input, init) => {
    const { p_action: a, p_args: v } = JSON.parse(String(init?.body));
    if (a === "webhook_receive") {
      events.add(v.hash);
      return reply(null);
    }
    if (a === "maintenance" || a === "claim_job") return reply(null);
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    const challenge = await receive(
      new Request(
        "https://fixture.test/?hub.mode=subscribe&hub.verify_token=fixture-verify&hub.challenge=hello",
      ),
    );
    assert((await challenge.json())["hub.challenge"] === "hello");
    assert(
      (await receive(
        new Request(
          "https://fixture.test/?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=hello",
        ),
      )).status === 403,
    );
    const event = {
      subscription_id: 123,
      owner_id: 42,
      object_id: 99,
      object_type: "activity",
      aspect_type: "create",
      event_time: now(),
    };
    for (let i = 0; i < 2; i++) {
      assert(
        (await receive(
          new Request("https://fixture.test/", {
            method: "POST",
            body: JSON.stringify(event),
          }),
        )).status === 200,
      );
    }
    await Promise.all(tasks);
    assert(events.size === 1);
  } finally {
    await Promise.allSettled(tasks);
    globalThis.fetch = original;
  }
});
Deno.test("forged revocation is checked against Strava before deleting any account", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  let destroyed = false;
  globalThis.fetch = (async (input, init) => {
    if (String(input) === "https://www.strava.com/api/v3/athlete") {
      return reply({ id: 42 });
    }
    if (String(input).includes("velo_strava_reconnect")) {
      destroyed = true;
      return reply(true);
    }
    const { p_action: a } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "rate_limit") return reply({ allowed: true });
    if (a === "strava_allowed") return reply(null);
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    await webhook({
      user_id: "alice",
      result: {
        generation: c.generation,
        event: { object_type: "athlete", updates: { authorized: "false" } },
      },
    });
    assert(!destroyed);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("GPX rejects empty, stationary and unordered tracks, preserves real segment boundaries", () => {
  for (
    const points of [[], [[51, 4, 1, "2026-11-01T10:00:00Z"], [
      51,
      4,
      1,
      "2026-11-01T10:01:00Z",
    ]], [[51, 4, 1, "2026-11-01T10:01:00Z"], [
      51.1,
      4.1,
      1,
      "2026-11-01T10:00:00Z",
    ]]]
  ) {
    let rejected = false;
    try {
      gpx({ points });
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
  assert(
    gpx({
      points: [[51, 4, 1, "2026-11-01T10:00:00Z"], [
        51.1,
        4.1,
        2,
        "2026-11-01T10:01:00Z",
        0,
        5,
        0,
        true,
      ]],
    }).includes("</trkseg><trkseg>"),
  );
});
Deno.test("a provider-deleted upload is terminal and is never posted again", async () => {
  environment();
  const original = fetch, c = await fixtureConnection();
  let posts = 0;
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    if (url === "https://www.strava.com/api/v3/uploads/101") {
      return reply({
        id: 101,
        status: "The created activity has been deleted.",
        error: null,
        activity_id: null,
      });
    }
    if (url === "https://www.strava.com/api/v3/uploads") {
      posts++;
      throw new Error("Must not re-upload");
    }
    const { p_action: a } = JSON.parse(String(init?.body));
    if (a === "connection") return reply(c);
    if (a === "rate_limit") return reply({ allowed: true });
    if (a === "strava_allowed") return reply(null);
    throw new Error("Unexpected fixture");
  }) as typeof fetch;
  try {
    let removed = false;
    try {
      await upload({
        user_id: "alice",
        result: { upload_id: 101, generation: c.generation, athlete_id: 42 },
      });
    } catch (e) {
      removed = (e as { code: string }).code === "activity_deleted";
    }
    assert(removed && posts === 0);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("webhook never acknowledges a failed durable enqueue as success", async () => {
  environment();
  Deno.env.set("STRAVA_WEBHOOK_SUBSCRIPTION_ID", "123");
  const original = fetch, tasks: Promise<unknown>[] = [];
  (globalThis as any).EdgeRuntime = {
    waitUntil: (p: Promise<unknown>) => tasks.push(p),
  };
  globalThis.fetch =
    (async () => reply({ code: "08006" }, 503)) as typeof fetch;
  try {
    const response = await receive(
      new Request("https://fixture.test/", {
        method: "POST",
        body: JSON.stringify({
          subscription_id: 123,
          object_type: "activity",
          aspect_type: "create",
          object_id: 99,
          owner_id: 42,
          event_time: now(),
        }),
      }),
    );
    assert(response.status === 503);
  } finally {
    await Promise.allSettled(tasks);
    globalThis.fetch = original;
  }
});

Deno.test("all bike profiles use official upload sport_type values with safe legacy fallback", () => {
  const expected = {
    road: "Ride",
    mountain: "MountainBikeRide",
    gravel: "GravelRide",
    electric: "EBikeRide",
    electricMountain: "EMountainBikeRide",
    city: "Ride",
    trekking: "Ride",
    other: "Ride",
  };
  for (const [bike, sport] of Object.entries(expected)) {
    assert(stravaSportType(bike) === sport);
  }
  for (
    const invalid of [
      undefined,
      null,
      "constructor",
      "__proto__",
      {},
      "unknown",
    ]
  ) assert(stravaSportType(invalid) === "Ride");
});
