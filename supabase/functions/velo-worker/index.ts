import { errorResponse, json, Problem } from "../_shared/core.ts";
import { work } from "../_shared/jobs.ts";
export async function handle(req: Request) {
  try {
    const expected = Deno.env.get("VELO_SCHEDULER_TOKEN");
    if (!expected || req.headers.get("Authorization") !== "Bearer " + expected) throw new Problem(401, "Geen toegang.");
    if (req.method !== "POST") throw new Problem(405, "Niet ondersteund.");
    await work(); return json({ ok: true });
  } catch (e) { return errorResponse(e); }
}
if (import.meta.main) Deno.serve(handle);
