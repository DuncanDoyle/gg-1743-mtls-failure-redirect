// Real Chromium with the valid client cert: load the API, flush sockets (the TLS session cache survives), load again.
// Run through ../browser-test.sh, which sets up the certs, the cert auto-select policy and these env vars.
import { chromium } from "playwright";

const API = process.env.API_URL;
const args = [`--host-resolver-rules=${process.env.HOST_RULES}`];
let failed = false;

async function load(page, label, expectRedirect) {
  const resp = await page.goto(API);
  const redirected = page.url().includes("reason=");
  const ok = redirected === expectRedirect;
  console.log(`${ok ? (expectRedirect ? "INFO" : "PASS") : "FAIL"}  ${label.padEnd(44)} ${page.url()} (${resp.status()})`);
  return ok;
}

const ctx = await chromium.launchPersistentContext("/tmp/profile", { channel: "chromium", args });
const page = await ctx.newPage();
failed ||= !(await load(page, "1. first connection (full handshake)", false));
await load(page, "2. same connection", false);
for (const n of [3, 4]) {
  await page.goto("chrome://net-internals/#sockets");
  await page.getByRole("button", { name: /flush socket pools/i }).click();
  // Known limitation: Envoy doesn't re-validate the cert on a resumed session, so this gets redirected.
  await load(page, `${n}. new connection (resumed TLS session)`, true);
}
await ctx.close();

// Control: a fresh profile has no session cache, so it does a full handshake and gets through.
const fresh = await chromium.launchPersistentContext("/tmp/profile-fresh", { channel: "chromium", args });
failed ||= !(await load(await fresh.newPage(), "5. fresh browser profile (full handshake)", false));
await fresh.close();

process.exit(failed ? 1 : 0);
