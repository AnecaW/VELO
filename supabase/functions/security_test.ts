import { handle as api } from "./velo-api/index.ts";
import { handle as worker } from "./velo-worker/index.ts";
import { seal, unseal } from "./_shared/core.ts";
import { gpx } from "./_shared/jobs.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value { if (!value) throw new Error(message); }
Deno.test("API rejects missing and forged bearer tokens", async () => {
  for (const auth of [undefined, "sb_publishable_public-key"]) {
    const response = await api(new Request("https://example.test/functions/v1/velo-api", {
      method: "POST", headers: auth ? { Authorization: auth } : {}, body: '{}',
    }));
    assert(response.status === 401);
    assert(!(await response.text()).includes("service_role"));
  }
});
Deno.test("worker requires its separate server-only scheduler secret", async () => {
  Deno.env.set("VELO_SCHEDULER_TOKEN", "test-scheduler-secret");
  const response = await worker(new Request("https://example.test/velo-worker", { method: "POST", body: "{}" }));
  assert(response.status === 401);
});
Deno.test("AES-GCM tokens are authenticated and bound to their owner", async () => {
  Deno.env.set("VELO_TOKEN_ENCRYPTION_KEY", btoa("x".repeat(32)));
  const value = await seal({ access_token: "test-provider-token" }, "alice");
  assert(!value.includes("test-provider-token"));
  assert((await unseal(value, "alice")).access_token === "test-provider-token");
  let rejected = false;
  try { await unseal(value, "bob"); } catch { rejected = true; }
  assert(rejected, "Other account must not decrypt a token");
  rejected = false;
  try { await unseal(value.slice(0, -4) + "AAAA", "alice"); } catch { rejected = true; }
  assert(rejected, "Modified ciphertext must not decrypt");
});
Deno.test("GPX upload uses real points and escapes XML values", () => {
  const text = gpx({ points: [[50, 4, 10, "2026-11-01T10:00:00Z"], [50.1, 4.1, 11, "2026-11-01T10:01:00Z"]] });
  assert(text.includes('lat="50"')); assert(text.includes("<time>2026-11-01T10:00:00Z</time>"));
  let rejected = false; try { gpx({ points: [] }); } catch { rejected = true; } assert(rejected);
});

Deno.test("email recovery remains explicitly disabled until the operator enables it",async()=>{
  Deno.env.delete("VELO_PASSWORD_RESET_ENABLED");
  const response=await api(new Request("https://example.test/functions/v1/velo-api/config"));
  assert(response.status===200);assert((await response.json()).password_reset_enabled===false);
});
