import {
  errorResponse,
  hash,
  json,
  now,
  privateCall,
  Problem,
} from "../_shared/core.ts";
import { work } from "../_shared/jobs.ts";
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
export async function handle(req: Request): Promise<Response> {
  try {
    const url = new URL(req.url);
    if (req.method === "GET") {
      const token = Deno.env.get("STRAVA_WEBHOOK_VERIFY_TOKEN");
      if (
        !token || url.searchParams.get("hub.verify_token") !== token ||
        url.searchParams.get("hub.mode") !== "subscribe"
      ) throw new Problem(403, "Geen toegang.");
      const challenge = url.searchParams.get("hub.challenge");
      if (!challenge || challenge.length > 200) {
        throw new Problem(400, "Ongeldige challenge.");
      }
      return json({ "hub.challenge": challenge });
    }
    if (req.method !== "POST") throw new Problem(405, "Niet ondersteund.");
    if (Number(req.headers.get("content-length")) > 10000) {
      throw new Problem(413, "Verzoek te groot.");
    }
    const reader = req.body?.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    if (reader) {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 10000) {
          await reader.cancel();
          throw new Problem(413, "Verzoek te groot.");
        }
        chunks.push(value);
      }
    }
    const raw = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      raw.set(chunk, offset);
      offset += chunk.length;
    }
    const text = new TextDecoder().decode(raw);
    const e = JSON.parse(text);
    const expected = Number(Deno.env.get("STRAVA_WEBHOOK_SUBSCRIPTION_ID"));
    if (!expected || e.subscription_id !== expected) return json({ ok: true });
    if (
      !["activity", "athlete"].includes(e.object_type) ||
      !["create", "update", "delete"].includes(e.aspect_type) ||
      ![e.owner_id, e.object_id, e.event_time].every((v) =>
        Number.isSafeInteger(v) && v > 0
      ) || Math.abs(now() - e.event_time) > 7 * 86400
    ) throw new Problem(400, "Ongeldig event.");
    const event = {
      object_type: e.object_type,
      object_id: e.object_id,
      owner_id: e.owner_id,
      aspect_type: e.aspect_type,
      event_time: e.event_time,
      updates: {
        ...(e.updates?.authorized === "false" ? { authorized: "false" } : {}),
        ...(e.updates?.private !== undefined
          ? { private: String(e.updates.private) }
          : {}),
      },
    };
    const persisted = privateCall("webhook_receive", {
      event,
      hash: await hash(JSON.stringify(event)),
    });
    EdgeRuntime.waitUntil(
      persisted.catch(() =>
        console.warn(
          JSON.stringify({
            event: "webhook_persist_error",
            code: "provider_must_retry",
          }),
        )
      ),
    );
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        persisted,
        new Promise((_, reject) => {
          timeout = setTimeout(() =>
            reject(
              new Problem(503, "Event nog niet opgeslagen.", "webhook_retry"),
            ), 1500);
        }),
      ]);
    } finally {
      if (timeout !== undefined) clearTimeout(timeout);
    }
    // Acknowledge only after durable enqueue. Strava retries a failed enqueue;
    // its event hash deduplicates a late commit. Provider work runs afterwards.
    EdgeRuntime.waitUntil(
      work().catch(() =>
        console.warn(
          JSON.stringify({
            event: "webhook_processing_error",
            code: "retry_by_worker",
          }),
        )
      ),
    );
    return json({ ok: true });
  } catch (e) {
    return errorResponse(e);
  }
}
if (import.meta.main) Deno.serve(handle);
