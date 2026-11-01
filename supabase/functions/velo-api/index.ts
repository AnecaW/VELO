declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import {
  accessToken,
  admin,
  callback,
  capabilities,
  checked,
  configured,
  connection,
  errorResponse,
  exchange,
  hash,
  json,
  limit,
  missingConfiguration,
  now,
  privateCall,
  Problem,
  random,
  requireUser,
  seal,
  strava,
} from "../_shared/core.ts";
import { enqueue, work } from "../_shared/jobs.ts";

async function oauth(url: URL) {
  if (!configured()) {
    throw new Problem(
      503,
      "De Strava-configuratie ontbreekt.",
      "not_configured",
    );
  }
  if (
    [...url.searchParams.keys()].some((k) =>
      url.searchParams.getAll(k).length !== 1
    )
  ) throw new Problem(400, "Ongeldige terugkeerlink.");
  const state = url.searchParams.get("state") ?? "";
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(state)) {
    throw new Problem(400, "Ongeldige autorisatiesessie.");
  }
  const stateHash = await hash(state);
  const row = await privateCall("oauth_lock", { hash: stateHash });
  if (!row) throw new Problem(400, "De koppeling is verlopen. Begin opnieuw.");
  if (url.searchParams.has("error")) {
    return Response.redirect(
      "ultimatebike://oauth/strava?state=" + encodeURIComponent(state) +
        "&error=denied",
      302,
    );
  }
  const code = url.searchParams.get("code");
  if (!code) throw new Problem(400, "Autorisatiecode ontbreekt.");
  try {
    const token = await exchange({ grant_type: "authorization_code", code });
    const profileResponse = await fetch(
      "https://www.strava.com/api/v3/athlete",
      {
        headers: { Authorization: "Bearer " + token.access_token },
        redirect: "error",
        signal: AbortSignal.timeout(20000),
      },
    );
    if (!profileResponse.ok) {
      throw new Problem(
        503,
        "Je Strava-profiel kon niet worden opgehaald.",
        "profile_unavailable",
      );
    }
    const athlete = await profileResponse.json();
    if (!Number.isSafeInteger(athlete.id) || athlete.id <= 0) {
      throw new Problem(503, "Strava gaf geen geldig profiel terug.");
    }
    const profile = Object.fromEntries(
      ["id", "firstname", "lastname", "username", "profile", "profile_medium"]
        .filter((k) => athlete[k] !== undefined).map((k) => [k, athlete[k]]),
    );
    const scope = (url.searchParams.get("scope") ?? "").split(",").filter((s) =>
      ["read", "activity:read", "activity:read_all", "activity:write"].includes(
        s,
      )
    ).join(",");
    const handoff = random();
    const result = await privateCall("oauth_stage", {
      hash: stateHash,
      handoff_hash: await hash(handoff),
      connection: {
        athlete: profile,
        scope,
        expires_at: token.expires_at,
        token_cipher: await seal({
          access_token: token.access_token,
          refresh_token: token.refresh_token,
        }, row.user_id),
      },
    });
    if (!result?.ok) {
      throw new Problem(400, "De autorisatiesessie is verlopen.");
    }
    return Response.redirect(
      "ultimatebike://oauth/strava?state=" + encodeURIComponent(state) +
        "&handoff=" + handoff,
      302,
    );
  } catch (e) {
    console.warn(
      JSON.stringify({
        event: "strava_oauth_error",
        code: e instanceof Problem ? e.code : "unexpected",
        status: e instanceof Problem ? e.status : 503,
      }),
    );
    return Response.redirect(
      "ultimatebike://oauth/strava?state=" + encodeURIComponent(state) +
        "&error=exchange_failed",
      302,
    );
  }
}
export async function handle(req: Request): Promise<Response> {
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/velo-api/config")) {
      return json({
        password_reset_enabled:
          Deno.env.get("VELO_PASSWORD_RESET_ENABLED") === "true",
      });
    }
    if (
      req.method === "GET" && url.pathname.endsWith("/oauth/strava/callback")
    ) return await oauth(url);
    if (req.method !== "POST") throw new Problem(405, "Niet ondersteund.");
    const user = await requireUser(req);
    if (Number(req.headers.get("content-length")) > 11000000) {
      throw new Problem(413, "Verzoek te groot.");
    }
    const envelope = await req.json();
    const method = envelope.method;
    if (
      typeof envelope.path !== "string" || !envelope.path.startsWith("/api/v1/")
    ) throw new Problem(400, "Ongeldig verzoek.");
    const path = new URL(envelope.path, "https://velo.invalid");
    const body = envelope.body ?? {};
    const parts = path.pathname.split("/").filter(Boolean);
    await limit("api:" + user.id, 600);
    if (path.pathname === "/api/v1/me" && method === "DELETE") {
      // Require the password again using an isolated anon client, not admin impersonation.
      const verifier = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      const verified = await verifier.auth.signInWithPassword({
        email: user.email!,
        password: body.password ?? "",
      });
      if (verified.error || verified.data.user?.id !== user.id) {
        throw new Problem(401, "Controleer je huidige wachtwoord.");
      }
      await verifier.auth.signOut();
      const c = await connection(user.id);
      if (c) {
        try {
          const token = await accessToken(user.id);
          await fetch("https://www.strava.com/oauth/deauthorize", {
            method: "POST",
            headers: { Authorization: "Bearer " + token },
            signal: AbortSignal.timeout(10000),
          });
        } catch (_) {
          /* Deletion must not be blocked by an unavailable provider. */
        }
      }
      const { error } = await admin().auth.admin.deleteUser(user.id);
      if (error) {
        throw new Problem(503, "Verwijderen kon niet worden voltooid.");
      }
      return json({ ok: true });
    }
    if (parts[2] === "navigation") {
      const key = Deno.env.get("ORS_API_KEY");
      if (!key) {
        throw new Problem(
          503,
          "Routeplanning is nog niet beschikbaar. Opgeslagen routes blijven werken.",
          "navigation_unavailable",
        );
      }
      await limit("navigation:" + user.id, 60);
      let target: string;
      const init: RequestInit = {
        headers: { Authorization: key, "Content-Type": "application/json" },
        signal: AbortSignal.timeout(25000),
        redirect: "error",
      };
      if (parts[3] === "search" && method === "GET") {
        const q = path.searchParams.get("q") ?? "";
        if (q.length < 3 || q.length > 200) {
          throw new Problem(422, "Vul een geldige zoekterm in.");
        }
        target = "/geocode/search?size=5&text=" + encodeURIComponent(q);
      } else if (parts[3] === "directions" && method === "POST") {
        const profile = body.profile ?? "cycling-regular";
        if (
          ![
            "cycling-regular",
            "cycling-road",
            "cycling-mountain",
            "cycling-electric",
          ].includes(profile) ||
          !Array.isArray(body.coordinates) || body.coordinates.length !== 2 ||
          body.coordinates.some((p: unknown) =>
            !Array.isArray(p) || p.length !== 2 || !Number.isFinite(p[0]) ||
            !Number.isFinite(p[1]) || Math.abs(p[0]) > 180 ||
            Math.abs(p[1]) > 90
          )
        ) throw new Problem(422, "Ongeldige routepunten.");
        target = `/v2/directions/${profile}/geojson`;
        init.method = "POST";
        init.body = JSON.stringify({
          coordinates: body.coordinates,
          elevation: true,
          instructions: true,
        });
      } else throw new Problem(404, "Route niet gevonden.");
      const response = await fetch(
        "https://api.openrouteservice.org" + target,
        init,
      );
      if (!response.ok) {
        throw new Problem(
          response.status === 429 ? 429 : 503,
          "Routeplanning is tijdelijk niet beschikbaar.",
        );
      }
      return json(await response.json());
    }
    if (parts[2] === "jobs") {
      let query = admin().from("velo_jobs").select("*").eq("user_id", user.id);
      if (parts[3]) query = query.eq("id", parts[3]);
      const rideId = path.searchParams.get("ride_id");
      if (rideId) query = query.eq("kind", "upload").eq("job_key", rideId);

      if (parts[4] === "retry" && method === "POST") {
        const job = await checked(query.maybeSingle());
        if (!job) throw new Problem(404, "Taak niet gevonden.");
        if (
          job.status === "needs_review" && body.confirmed_no_duplicate !== true
        ) {
          throw new Problem(
            409,
            "Controleer eerst of de rit al in Strava staat.",
          );
        }
        if (["running", "complete"].includes(job.status)) {
          throw new Problem(409, "Deze taak kan niet opnieuw worden gestart.");
        }
        await checked(
          admin().from("velo_jobs").update({
            status: "pending",
            next_at: now(),
            attempts: 0,
            error: null,
            ...(job.result?.upload_id
              ? {}
              : { result: { ...job.result, upload_intent: false } }),
          }).eq("id", job.id).eq("user_id", user.id),
        );
        EdgeRuntime.waitUntil(work(user.id));
        return json({ ok: true });
      }
      if (method !== "GET") throw new Problem(405, "Niet ondersteund.");
      return json(
        parts[3] ? await checked(query.single()) : await checked(
          query.order("next_at", { ascending: false }).limit(100),
        ),
      );
    }
    if (path.pathname === "/api/v1/sync/history" && method === "GET") {
      return json(
        await checked(
          admin().from("velo_sync_history").select("*").eq("user_id", user.id)
            .order("created_at", { ascending: false }).limit(100),
        ),
      );
    }
    if (parts[2] !== "integrations" || parts[3] !== "strava") {
      throw new Problem(404, "Functie niet gevonden.");
    }
    const c = await connection(user.id);
    if (parts.length === 4 && method === "GET") {
      const counts = await privateCall("cache_counts", { user_id: user.id });
      const jobs = await checked(
        admin().from("velo_jobs").select("*").eq("user_id", user.id).order(
          "updated_at",
          { ascending: false },
        ).limit(100),
      );
      const recent = (jobs ?? []).filter((j: Record<string, unknown>) =>
        j.kind !== "upload"
      );
      const history = await checked(
        admin().from("velo_sync_history").select("*").eq("user_id", user.id)
          .order("created_at", { ascending: false }).limit(20),
      );
      return json({
        configured: configured(),
        missing_configuration: missingConfiguration(),
        connected: c?.status === "connected",
        status: c?.status ?? "disconnected",
        athlete: c?.athlete,
        scope: c?.scope,
        last_sync: c?.last_sync,
        error: c?.error,
        features: capabilities(c?.scope ?? ""),
        counts,
        preferences: c?.preferences,
        sync_status: recent?.[0]?.status,
        sync_error: recent?.[0]?.error,
        jobs: (jobs ?? []).filter((j: Record<string, unknown>) =>
          j.kind === "upload"
        ),
        history,
        webhook_configured: Boolean(
          Deno.env.get("STRAVA_WEBHOOK_SUBSCRIPTION_ID"),
        ),
      });
    }
    if (!configured()) {
      throw new Problem(
        503,
        "De Strava-configuratie ontbreekt. De beheerder moet Strava activeren.",
        "not_configured",
      );
    }
    if (parts.length === 4 && method === "DELETE") {
      if (c?.status === "connected") {
        const token = await accessToken(user.id);
        const response = await fetch(
          "https://www.strava.com/oauth/deauthorize",
          {
            method: "POST",
            headers: { Authorization: "Bearer " + token },
            signal: AbortSignal.timeout(20000),
          },
        );
        if (![200, 401].includes(response.status)) {
          throw new Problem(
            503,
            "Strava kon de toestemming nog niet intrekken. Probeer opnieuw.",
          );
        }
      }
      await checked(
        admin().rpc("velo_strava_disconnect", { p_user_id: user.id }),
      );
      return json({ ok: true });
    }
    if (parts[4] === "authorize" && method === "POST") {
      await limit("strava-authorize:" + user.id, 10);
      if (
        !/^[A-Za-z0-9_-]{32,128}$/.test(body.state) ||
        !/^[A-Za-z0-9_-]{43}$/.test(body.code_challenge) ||
        !Array.isArray(body.scopes) || body.scopes.length < 1 ||
        body.scopes.some((s: string) =>
          !["activity:read", "activity:read_all", "activity:write", "read"]
            .includes(s)
        )
      ) throw new Problem(422, "Ongeldige autorisatiesessie.");
      await privateCall("oauth_create", {
        user_id: user.id,
        hash: await hash(body.state),
        state: body.state,
        challenge: body.code_challenge,
      });
      const auth = new URL("https://www.strava.com/oauth/mobile/authorize");
      auth.search = new URLSearchParams({
        client_id: Deno.env.get("STRAVA_CLIENT_ID")!,
        redirect_uri: callback(),
        response_type: "code",
        approval_prompt: "auto",
        scope: body.scopes.join(","),
        state: body.state,
      }).toString();
      return json({ authorization_url: auth.toString() });
    }
    if (parts[4] === "confirm" && method === "POST") {
      const result = await privateCall("oauth_confirm", {
        user_id: user.id,
        hash: await hash(body.state ?? ""),
        handoff_hash: await hash(body.handoff ?? ""),
        challenge: await hash(body.code_verifier ?? ""),
      });
      if (!result?.ok) {
        throw new Problem(400, "De autorisatiesessie is ongeldig of verlopen.");
      }
      return json({ ok: true });
    }
    if (!c || c.status !== "connected") {
      throw new Problem(409, "Verbind Strava eerst.");
    }
    if (parts[4] === "preferences" && method === "PUT") {
      const preferences = { ...c.preferences };
      for (
        const k of ["enabled", "automatic", "activities", "routes", "uploads"]
      ) {
        if (body[k] !== undefined && typeof body[k] !== "boolean") {
          throw new Problem(422, "Ongeldige voorkeur.");
        }
        if (body[k] !== undefined) preferences[k] = body[k];
      }
      if (body.history_days !== undefined) {
        if (
          !Number.isInteger(body.history_days) || body.history_days < 1 ||
          body.history_days > 365
        ) throw new Problem(422, "Kies een periode tussen 1 en 365 dagen.");
        preferences.history_days = body.history_days;
      }
      await privateCall("preferences", { user_id: user.id, preferences });
      if (
        !c.last_sync && preferences.enabled &&
        (preferences.activities || preferences.routes)
      ) {
        const id = await enqueue(user.id, "sync", "initial");
        EdgeRuntime.waitUntil(work(user.id));
        return json({ ok: true, job_id: id });
      }
      return json({ ok: true });
    }
    if (parts[4] === "cache" && method === "DELETE") {
      await privateCall("reset_cache", { user_id: user.id });
      return json({ ok: true });
    }
    if (parts[4] === "sync" && method === "POST") {
      await limit("sync:" + user.id, 20);
      const id = await enqueue(user.id, "sync", "manual");
      EdgeRuntime.waitUntil(work(user.id));
      return json({ job_id: id });
    }
    if (parts[4] === "uploads" && parts[5] && method === "POST") {
      if (!capabilities(c.scope).uploads) {
        throw new Problem(
          403,
          "Verbind opnieuw met toestemming om activiteiten te uploaden.",
          "scope_missing",
        );
      }
      const automatic = body.automatic === true;
      if (
        !c.preferences.enabled ||
        (automatic && (!c.preferences.uploads || !c.preferences.automatic))
      ) throw new Problem(403, "Automatisch uploaden is uitgeschakeld.");
      const id = await enqueue(
        user.id,
        "upload",
        decodeURIComponent(parts.slice(5).join("/")),
        automatic,
      );
      EdgeRuntime.waitUntil(work(user.id));
      return json({ job_id: id });
    }
    if (["activities", "routes"].includes(parts[4]) && method === "GET") {
      if (parts[5] && parts[4] === "activities") {
        if (!/^\d+$/.test(parts[5])) {
          throw new Problem(422, "Ongeldige activiteit.");
        }
        const detail = await (await strava(user.id, "activities/" + parts[5]))
          .json();
        if (detail.athlete?.id !== c.athlete.id) {
          throw new Problem(403, "Deze activiteit is niet van jouw account.");
        }
        return json(detail);
      }
      if (path.searchParams.has("page")) {
        const page = Number(path.searchParams.get("page")), size = 50;
        if (!Number.isInteger(page) || page < 1 || page > 10000) {
          throw new Problem(422, "Ongeldige pagina.");
        }
        const result = await privateCall("cache_page", {
          user_id: user.id,
          kind: parts[4],
          offset: (page - 1) * size,
          limit: size,
        });
        return json({
          ...result,
          next_page: page * size < result.total ? page + 1 : null,
        });
      }
      return json(
        await privateCall("cache", { user_id: user.id, kind: parts[4] }),
      );
    }
    throw new Problem(404, "Functie niet gevonden.");
  } catch (e) {
    return errorResponse(e);
  }
}
if (import.meta.main) Deno.serve(handle);
