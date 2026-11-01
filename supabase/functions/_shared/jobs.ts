import {
  admin,
  capabilities,
  checked,
  connection,
  hash,
  now,
  privateCall,
  Problem,
  strava,
} from "./core.ts";

const escape = (s: unknown) =>
  String(s).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(
    '"',
    "&quot;",
  );
export function gpx(payload: Record<string, unknown>) {
  const points = payload.points as unknown[][];
  if (!Array.isArray(points) || points.length < 2) {
    throw new Problem(
      422,
      "Deze rit heeft geen bruikbaar GPS-spoor (minimaal twee punten met tijdstempels).",
      "invalid_track",
    );
  }
  let previous = -Infinity;
  let different = false;
  const segments = points.map((p, i) => {
    const time = Date.parse(String(p[3]));
    if (
      !Number.isFinite(p[0]) || !Number.isFinite(p[1]) ||
      Math.abs(Number(p[0])) > 90 || Math.abs(Number(p[1])) > 180 ||
      !Number.isFinite(time) || time <= previous
    ) {
      throw new Problem(
        422,
        "Het GPS-spoor bevat ongeldige punten of tijdstempels.",
        "invalid_track",
      );
    }
    previous = time;
    if (i > 0 && (p[0] !== points[0][0] || p[1] !== points[0][1])) {
      different = true;
    }
    return (i > 0 && p[7] === true ? "</trkseg><trkseg>" : "") +
      `<trkpt lat="${escape(p[0])}" lon="${escape(p[1])}">${
        Number.isFinite(p[2]) ? `<ele>${escape(p[2])}</ele>` : ""
      }<time>${new Date(time).toISOString()}</time></trkpt>`;
  });
  if (!different) {
    throw new Problem(
      422,
      "Het GPS-spoor bevat geen verplaatsing. Deze rit kan niet als GPS-activiteit worden verstuurd.",
      "invalid_track",
    );
  }
  return '<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="VELO" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>' +
    escape(payload.name ?? "VELO-rit") + "</name><trkseg>" + segments.join("") +
    "</trkseg></trk></gpx>";
}
export async function enqueue(
  owner: string,
  kind: "sync" | "upload",
  key: string,
  automatic = false,
) {
  const db = admin();
  const previous = await checked(
    db.from("velo_jobs").select("*").eq("user_id", owner).eq("kind", kind).eq(
      "job_key",
      key,
    ).maybeSingle(),
  );
  if (previous) {
    if (kind === "sync" && !["pending", "running"].includes(previous.status)) {
      await checked(
        db.from("velo_jobs").update({
          status: "pending",
          attempts: 0,
          next_at: Math.max(now(), previous.next_at),
          error: null,
        }).eq("id", previous.id),
      );
    }
    return previous.id;
  }
  const result = await db.from("velo_jobs").upsert({
    user_id: owner,
    kind,
    job_key: key,
    automatic,
  }, { onConflict: "user_id,kind,job_key", ignoreDuplicates: true }).select()
    .maybeSingle();
  if (result.error) throw new Problem(503, "Taak kon niet worden ingepland.");
  return result.data?.id ??
    (await checked(
      db.from("velo_jobs").select("id").eq("user_id", owner).eq("kind", kind)
        .eq("job_key", key).single(),
    ))!.id;
}
export async function cacheActivity(
  owner: string,
  value: Record<string, any>,
  generation: string,
) {
  const c = await connection(owner);
  if (!c || c.generation !== generation || c.status !== "connected") {
    throw new Problem(
      409,
      "De Strava-verbinding is gewijzigd.",
      "connection_changed",
    );
  }
  if (value.athlete?.id && value.athlete.id !== c.athlete.id) {
    throw new Problem(
      403,
      "Deze activiteit hoort niet bij jouw Strava-account.",
    );
  }
  await privateCall("save_cache", {
    user_id: owner,
    kind: "activities",
    id: String(value.id),
    data: value,
    generation,
  });
}
export async function synchronize(owner: string) {
  const c = await connection(owner);
  if (!c || c.status !== "connected") {
    throw new Problem(401, "Verbind Strava opnieuw.");
  }
  const p = c.preferences, rights = capabilities(c.scope);
  if (!p.enabled) return true;
  let window = c.sync_window;
  if (p.activities) {
    if (!rights.activities) {
      throw new Problem(
        403,
        "Activiteiten lezen is niet toegestaan. Verbind opnieuw met leesrechten.",
        "scope_missing",
      );
    }
    if (!window?.before) {
      const full = now() - c.full_sync_at >= 20 * 3600 || !c.cursor;
      window = {
        after: full
          ? now() -
            Math.max(1, Math.min(365, Number(p.history_days) || 30)) * 86400
          : Math.max(0, c.cursor - 300),
        before: now(),
        page: 1,
        full,
      };
      await privateCall("sync_window", {
        user_id: owner,
        generation: c.generation,
        window,
      });
    }
    let complete = false;
    for (let i = 0; i < 2; i++) {
      const values = await (await strava(
        owner,
        `athlete/activities?after=${window.after}&before=${window.before}&per_page=50&page=${window.page}`,
      )).json();
      if (!Array.isArray(values)) {
        throw new Problem(
          503,
          "Strava gaf geen geldige activiteitenlijst terug.",
          "invalid_provider_response",
        );
      }
      for (const value of values) {
        await cacheActivity(owner, value, c.generation);
      }
      if (values.length < 50) {
        complete = true;
        break;
      }
      window.page++;
      const saved = await privateCall("sync_window", {
        user_id: owner,
        generation: c.generation,
        window,
      });
      if (!saved?.ok) {
        throw new Problem(
          409,
          "Strava-account gewijzigd.",
          "connection_changed",
        );
      }
    }
    if (!complete) return false;
  }
  let routePage = Number(p.route_page) || 1;
  if (p.routes && rights.routes) {
    const values = await (await strava(
      owner,
      `athletes/${c.athlete.id}/routes?per_page=2&page=${routePage}`,
    )).json();
    routePage = values.length < 2 ? 1 : routePage + 1;
    for (const value of values) {
      const route = await (await strava(owner, `routes/${value.id}/export_gpx`))
        .text();
      await privateCall("save_cache", {
        user_id: owner,
        kind: "routes",
        id: String(value.id),
        data: { ...value, gpx: route },
        generation: c.generation,
      });
    }
  }
  const saved = await privateCall("sync_complete", {
    user_id: owner,
    generation: c.generation,
    cursor: window?.before ?? now(),
    full: window?.full ?? false,
    route_page: routePage,
  });
  if (!saved?.ok) {
    throw new Problem(409, "Strava-account gewijzigd.", "connection_changed");
  }
  return true;
}
async function updateJob(
  job: Record<string, any>,
  value: Record<string, unknown>,
) {
  return await checked(
    admin().from("velo_jobs").update(value).eq("id", job.id).eq(
      "lease_token",
      job.lease_token,
    ).eq("status", "running").select("id").maybeSingle(),
  );
}
export async function upload(job: Record<string, any>) {
  const c = await connection(job.user_id);
  if (
    !c || c.status !== "connected" || !c.preferences.enabled ||
    !capabilities(c.scope).uploads
  ) {
    throw new Problem(
      403,
      "Verbind Strava met toestemming om ritten te uploaden.",
      "scope_missing",
    );
  }
  if (job.automatic && (!c.preferences.uploads || !c.preferences.automatic)) {
    throw new Problem(
      403,
      "Automatisch uploaden is uitgeschakeld.",
      "automatic_disabled",
    );
  }
  if (
    job.result?.generation && job.result.generation !== c.generation &&
    job.result.athlete_id !== c.athlete.id
  ) {
    throw new Problem(
      409,
      "De rit hoort bij een vorige Strava-koppeling.",
      "connection_changed",
    );
  }
  let result = { ...job.result };
  if (!result.upload_id) {
    if (result.upload_intent) {
      throw new Problem(
        409,
        "Controleer eerst in Strava of de vorige upload geslaagd is.",
        "uncertain_upload",
        0,
        true,
      );
    }
    const doc = await checked(
      admin().from("velo_documents").select("payload").eq(
        "user_id",
        job.user_id,
      ).eq("kind", "rides").eq("id", job.job_key).eq("deleted", false)
        .maybeSingle(),
    );
    const track = await checked(
      admin().from("velo_tracks").select("points").eq("user_id", job.user_id)
        .eq("ride_id", job.job_key).maybeSingle(),
    );
    if (!doc || !track) {
      throw new Problem(
        422,
        "De opgeslagen rit of het GPS-spoor ontbreekt.",
        "invalid_track",
      );
    }
    const file = gpx({ ...doc.payload, points: track.points });
    const externalId = "velo-" + await hash(job.user_id + ":" + job.job_key);
    result = {
      external_id: externalId,
      upload_intent: true,
      generation: c.generation,
      athlete_id: c.athlete.id,
    };
    if (!await updateJob(job, { result })) {
      throw new Problem(
        409,
        "De upload wordt al elders verwerkt.",
        "lease_changed",
      );
    }
    const form = new FormData();
    form.set(
      "file",
      new Blob([file], { type: "application/gpx+xml" }),
      "velo.gpx",
    );
    form.set("data_type", "gpx");
    form.set("external_id", externalId);
    form.set("sport_type", "Ride");
    const response = await strava(job.user_id, "uploads", {
      method: "POST",
      body: form,
    });
    const uploaded = await response.json();
    if (uploaded.error || !uploaded.id) {
      throw new Problem(
        422,
        "Strava heeft deze upload geweigerd. Controleer of de rit al bestaat.",
        "upload_rejected",
      );
    }
    result = { ...result, upload_id: uploaded.id, polls: 0 };
    await updateJob(job, {
      result,
      status: "pending",
      next_at: now() + 30,
      lease_until: 0,
      lease_token: null,
    });
    return false;
  }
  const progress =
    await (await strava(job.user_id, "uploads/" + result.upload_id)).json();
  if (/\b(deleted|removed)\b/i.test(String(progress.status ?? ""))) {
    throw new Problem(
      410,
      "Deze activiteit is verwijderd in Strava. VELO uploadt ze niet automatisch opnieuw.",
      "activity_deleted",
    );
  }
  if (progress.error) {
    throw new Problem(
      422,
      "Strava kon de upload niet verwerken. Controleer op een dubbele activiteit.",
      "upload_rejected",
    );
  }
  if (!progress.activity_id) {
    if ((result.polls ?? 0) >= 60) {
      throw new Problem(
        409,
        "Strava verwerkt deze upload nog. Controleer de status voordat je opnieuw probeert.",
        "uncertain_upload",
        0,
        true,
      );
    }
    await updateJob(job, {
      status: "pending",
      next_at: now() + 30,
      lease_until: 0,
      lease_token: null,
      result: { ...result, polls: (result.polls ?? 0) + 1 },
    });
    return false;
  }
  await updateJob(job, {
    result: { ...result, activity_id: progress.activity_id },
  });
  await privateCall("remove_cached_activity", {
    user_id: job.user_id,
    id: String(progress.activity_id),
  });
  return true;
}
export async function webhook(job: Record<string, any>) {
  const c = await connection(job.user_id), event = job.result.event;
  if (
    !c || c.status !== "connected" || c.generation !== job.result.generation
  ) return;
  if (event.object_type === "athlete") {
    // Strava webhooks are unsigned. Confirm revocation against the provider before
    // making a destructive change; forged events cannot disconnect a valid token.
    try {
      await strava(job.user_id, "athlete");
    } catch (e) {
      if (!(e instanceof Problem && e.status === 401)) throw e;
    }
    return;
  }
  if (
    !c.preferences.enabled || !c.preferences.activities ||
    !capabilities(c.scope).activities
  ) return;
  try {
    const activity =
      await (await strava(job.user_id, "activities/" + event.object_id)).json();
    await cacheActivity(job.user_id, activity, c.generation);
  } catch (e) {
    if (e instanceof Problem && [403, 404].includes(e.status)) {
      await privateCall("remove_cached_activity", {
        user_id: job.user_id,
        id: String(event.object_id),
      });
    } else throw e;
  }
}
export async function work(owner?: string) {
  await privateCall("maintenance");
  const job = await privateCall("claim_job", owner ? { user_id: owner } : {});
  if (!job) return;
  try {
    if (job.kind === "sync") {
      if (!await synchronize(job.user_id)) {
        await updateJob(job, {
          status: "pending",
          next_at: now() + 5,
          lease_until: 0,
          lease_token: null,
          attempts: 0,
        });
        return;
      }
    } else if (job.kind === "webhook") await webhook(job);
    else if (!await upload(job)) return;
    if (
      await updateJob(job, {
        status: "complete",
        error: null,
        lease_until: 0,
        lease_token: null,
      })
    ) {
      await checked(
        admin().from("velo_sync_history").insert({
          user_id: job.user_id,
          status: "complete",
          message: job.kind === "upload"
            ? "Rit verwerkt door Strava"
            : "Synchronisatie geslaagd",
        }),
      );
    }
  } catch (e) {
    const p = e instanceof Problem ? e : new Problem(
      503,
      "Synchronisatie tijdelijk onderbroken.",
      "temporary",
      120,
      job.kind === "upload" && !job.result?.upload_id,
    );
    console.warn(
      JSON.stringify({
        event: "strava_job_error",
        kind: job.kind,
        code: p.code,
        status: p.status,
        attempt: job.attempts,
      }),
    );
    const retry = Math.max(
      p.retry,
      Math.min(21600, 30 * 2 ** Math.min(job.attempts, 9)),
    );
    const definite = [401, 403, 404, 409, 410, 422].includes(p.status);
    let preserved: Record<string, unknown> = p.status === 410
      ? {
        result: {
          external_id: job.result?.external_id,
          removed: true,
          previously_submitted: true,
        },
      }
      : {};
    if (
      job.kind === "upload" && !p.uncertain &&
      [401, 403, 422, 429].includes(p.status) && !job.result?.upload_id
    ) {
      const current = await checked(
        admin().from("velo_jobs").select("result").eq("id", job.id)
          .maybeSingle(),
      );
      if (!current?.result?.upload_id) {
        preserved = { result: { ...current?.result, upload_intent: false } };
      }
    }
    await updateJob(job, {
      ...preserved,
      status: p.uncertain
        ? "needs_review"
        : definite || job.attempts >= 10
        ? "failed"
        : "pending",
      next_at: now() + retry,
      lease_until: 0,
      lease_token: null,
      error: p.message,
    });
    await checked(
      admin().from("velo_sync_history").insert({
        user_id: job.user_id,
        status: "error",
        message: p.message,
      }),
    );
  }
}
