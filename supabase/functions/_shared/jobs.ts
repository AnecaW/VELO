import { admin, checked, connection, now, privateCall, Problem, strava } from "./core.ts";

const escape = (s: unknown) => String(s).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll('"', "&quot;");
export function gpx(payload: Record<string, unknown>) {
  const points = payload.points as unknown[][];
  if (!Array.isArray(points) || points.length < 2) throw new Problem(422, "Een upload vereist een eigen GPS-spoor.");
  return '<?xml version="1.0"?><gpx version="1.1" creator="VELO" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>' +
    points.map(p => {
      if (!Number.isFinite(p[0]) || !Number.isFinite(p[1]) || Math.abs(Number(p[0])) > 90 || Math.abs(Number(p[1])) > 180 || !Number.isFinite(Date.parse(String(p[3])))) {
        throw new Problem(422, "Het GPS-spoor bevat ongeldige punten.");
      }
      return `<trkpt lat="${escape(p[0])}" lon="${escape(p[1])}"><ele>${escape(p[2])}</ele><time>${escape(p[3])}</time></trkpt>`;
    }).join("") + "</trkseg></trk></gpx>";
}
export async function enqueue(owner: string, kind: "sync" | "upload", key: string) {
  const db = admin();
  const previous = await checked(db.from("velo_jobs").select("*").eq("user_id", owner).eq("kind", kind).eq("job_key", key).maybeSingle());
  if (previous) {
    if (kind === "sync" && !["pending", "running"].includes(previous.status)) {
      await checked(db.from("velo_jobs").update({ status: "pending", next_at: Math.max(now(), previous.next_at), error: null }).eq("id", previous.id));
    }
    return previous.id;
  }
  const result = await db.from("velo_jobs").upsert({ user_id: owner, kind, job_key: key }, { onConflict: "user_id,kind,job_key", ignoreDuplicates: true }).select().maybeSingle();
  if (result.error) throw new Problem(503, "Taak kon niet worden ingepland.");
  return result.data?.id ?? (await checked(db.from("velo_jobs").select("id").eq("user_id", owner).eq("kind", kind).eq("job_key", key).single()))!.id;
}
async function cache(owner: string, kind: string, id: string, data: unknown) {
  if (!(await connection(owner))) throw new Problem(401, "Strava is ontkoppeld.");
  await privateCall("save_cache", { user_id: owner, kind, id, data });
}
async function synchronize(owner: string) {
  const c = await connection(owner);
  if (!c) throw new Problem(401, "Strava is niet verbonden.");
  const prefs = c.preferences;
  if (!prefs.enabled) return;
  const before = now();
  let complete = !prefs.activities;
  if (prefs.activities) {
    if (!c.scope.split(",").some((s: string) => ["activity:read", "activity:read_all"].includes(s))) throw new Problem(403, "Geef Strava toestemming om activiteiten te lezen.");
    const after = Math.max(before - 7 * 86400, c.cursor - 300);
    for (let page = 1; page <= 2; page++) {
      const values = await (await strava(owner, `athlete/activities?after=${after}&before=${before}&per_page=50&page=${page}`)).json();
      for (const value of values) await cache(owner, "activities", String(value.id), value);
      if (values.length < 50) { complete = true; break; }
    }
  }
  let routePage = Number(prefs.route_page) || 1;
  if (prefs.routes) {
    if (!c.scope.split(",").some((s: string) => ["read", "read_all"].includes(s))) throw new Problem(403, "Geef Strava toestemming om routes te lezen.");
    const values = await (await strava(owner, `athletes/${c.athlete.id}/routes?per_page=2&page=${routePage}`)).json();
    routePage = values.length < 2 ? 1 : routePage + 1;
    for (const value of values) {
      const route = await (await strava(owner, `routes/${value.id}/export_gpx`)).text();
      await cache(owner, "routes", String(value.id), { ...value, gpx: route });
    }
  }
  // Never advance over a truncated page range: next sync will continue safely.
  await privateCall("sync_complete", { user_id: owner, cursor: complete ? before : c.cursor, route_page: routePage });
}
async function upload(job: Record<string, any>) {
  const c = await connection(job.user_id);
  if (!c?.preferences.enabled || !c?.preferences.uploads || !c.scope.split(",").includes("activity:write")) throw new Problem(403, "Uploads zijn uitgeschakeld of missen toestemming.");
  let uploadId = job.result?.upload_id;
  if (!uploadId) {
    const document = await checked(admin().from("velo_documents").select("payload").eq("user_id", job.user_id).eq("kind", "rides").eq("id", job.job_key).eq("deleted", false).single());
    const track = await checked(admin().from("velo_tracks").select("points").eq("user_id", job.user_id).eq("ride_id", job.job_key).single());
    if (!track) throw new Problem(422, "Het GPS-spoor ontbreekt.");
    const form = new FormData();
    form.set("file", new Blob([gpx({ ...document!.payload, points: track.points })], { type: "application/gpx+xml" }), "velo.gpx");
    form.set("data_type", "gpx"); form.set("external_id", "velo-" + job.id); form.set("sport_type", "Ride");
    const result = await (await strava(job.user_id, "uploads", { method: "POST", body: form })).json();
    uploadId = result.id;
    if (!uploadId) throw new Problem(503, "Controleer de upload in Strava voordat je opnieuw probeert.", "uncertain_upload", 0, true);
    await checked(admin().from("velo_jobs").update({ result: { upload_id: uploadId } }).eq("id", job.id));
  }
  const result = await (await strava(job.user_id, "uploads/" + uploadId)).json();
  if (result.error) throw new Problem(422, "Strava heeft deze upload geweigerd. Controleer op een dubbele activiteit.");
  if (!result.activity_id) {
    await checked(admin().from("velo_jobs").update({ status: "pending", next_at: now() + 30, lease_until: 0, result: { upload_id: uploadId } }).eq("id", job.id));
    return false;
  }
  await checked(admin().from("velo_jobs").update({ result: { upload_id: uploadId, activity_id: result.activity_id } }).eq("id", job.id));
  return true;
}
export async function work(owner?: string) {
  await privateCall("maintenance");
  // Bounded execution; scheduled invocations resume remaining work.
  for (let i = 0; i < 1; i++) {
    const job = await privateCall("claim_job", owner ? { user_id: owner } : {});
    if (!job) break;
    try {
      if (job.kind === "sync") await synchronize(job.user_id);
      else if (!await upload(job)) continue;
      await checked(admin().from("velo_jobs").update({ status: "complete", error: null, lease_until: 0 }).eq("id", job.id));
      await checked(admin().from("velo_sync_history").insert({ user_id: job.user_id, status: "complete", message: "Synchronisatie geslaagd" }));
    } catch (e) {
      const p = e instanceof Problem ? e : new Problem(503, "Synchronisatie tijdelijk onderbroken.", "temporary", 300, job.kind === "upload" && !job.result?.upload_id);
      const retry = Math.max(p.retry, Math.min(21600, 30 * 2 ** Math.min(job.attempts, 9)));
      await checked(admin().from("velo_jobs").update({
        status: p.uncertain ? "needs_review" : [401, 403, 422].includes(p.status) || job.attempts >= 10 ? "failed" : "pending",
        next_at: now() + retry, lease_until: 0, error: p.message,
      }).eq("id", job.id));
      await checked(admin().from("velo_sync_history").insert({ user_id: job.user_id, status: "error", message: p.message }));
    }
  }
}
