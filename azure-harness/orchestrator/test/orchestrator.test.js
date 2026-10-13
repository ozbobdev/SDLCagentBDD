"use strict";
const assert = require("assert");
const crypto = require("crypto");
const { verifyToken } = require("../auth");
const { createOrchestrator } = require("../server");

const tests = [];
const test = (name, fn) => tests.push([name, fn]);

const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "k1" };
const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function sign(claims, kid = "k1") {
  const u = `${enc({ alg: "RS256", kid })}.${enc(claims)}`;
  return `${u}.${crypto.createSign("RSA-SHA256").update(u).sign(privateKey, "base64url")}`;
}
const now = Math.floor(Date.now() / 1000);
const good = { tid: "t", aud: "api://x", appid: "client1", roles: ["Dispatch"], exp: now + 300 };
const opts = { tenant: "t", audience: "api://x", allowedClientIds: ["client1"], requiredRole: "Dispatch", keys: [jwk] };

test("auth accepts a valid token", async () => { assert.ok(await verifyToken(sign(good), opts)); });
for (const [name, patch, kid] of [
  ["wrong audience", { aud: "api://other" }],
  ["wrong tenant", { tid: "z" }],
  ["expired", { exp: now - 10 }],
  ["caller not allowed", { appid: "evil" }],
  ["missing role", { roles: [] }],
  ["unknown key", {}, "k2"],
]) {
  test(`auth rejects ${name}`, async () => { await assert.rejects(verifyToken(sign({ ...good, ...patch }, kid), opts)); });
}

function harness(overrides = {}) {
  const calls = [];
  const github = {
    configured: true,
    comment: async (...a) => calls.push(["comment", ...a]),
    addLabels: async (...a) => calls.push(["addLabels", ...a]),
    removeLabel: async (...a) => calls.push(["removeLabel", ...a]),
    getIssue: async () => ({ title: "Add login", body: "As a user I want to log in" }),
    openPullRequest: async (...a) => { calls.push(["pr", ...a]); return { html_url: "https://example/pr/1" }; },
  };
  const events = [];
  const telemetry = { enabled: false, event: (n, p) => events.push([n, p]) };
  const env = { available: [], allowedRepos: ["o/r"], tenant: "t", audience: "a", allowedClientIds: [], requiredRole: "Dispatch" };
  const orch = createOrchestrator({ env, github, telemetry, chat: async () => ({ text: "ok", usage: { total_tokens: 5 } }), verify: async () => ({}), ...overrides });
  return { orch, calls, events };
}
function call(orch, method, url, body, headers = {}) {
  return new Promise((resolve) => {
    const res = { writeHead(code) { this.code = code; }, end(b) { resolve({ code: this.code, body: JSON.parse(b) }); } };
    orch.handle({ method, url, headers: { authorization: "Bearer t", ...headers } }, res, body ? JSON.stringify(body) : "");
  });
}

test("healthz is open", async () => { assert.strictEqual((await call(harness().orch, "GET", "/healthz")).code, 200); });
test("rejects unauthenticated", async () => {
  const { orch } = harness({ verify: async () => { throw new Error("no"); } });
  assert.strictEqual((await call(orch, "POST", "/work-items", { repo: "o/r", number: 1 })).code, 401);
});
test("rejects disallowed repo and bad input", async () => {
  const { orch } = harness();
  assert.strictEqual((await call(orch, "POST", "/work-items", { repo: "x/y", number: 1 })).code, 400);
  assert.strictEqual((await call(orch, "POST", "/work-items", { repo: "o/r", number: 0 })).code, 400);
  assert.strictEqual((await call(orch, "POST", "/work-items", { repo: "o/r", number: 1, level: "boss" })).code, 400);
});
test("accepts, is idempotent, and triages with comment and labels", async () => {
  const { orch, calls, events } = harness();
  const a = await call(orch, "POST", "/work-items", { repo: "o/r", number: 7, level: "junior" }, { "idempotency-key": "k" });
  assert.strictEqual(a.code, 202);
  const b = await call(orch, "POST", "/work-items", { repo: "o/r", number: 7 }, { "idempotency-key": "k" });
  assert.ok(b.body.duplicate);
  await new Promise((r) => setTimeout(r, 50));
  assert.ok(calls.some((c) => c[0] === "comment" && c[3].includes("ok")));
  assert.ok(calls.some((c) => c[0] === "addLabels" && c[3].includes("squad:needs-review")));
  assert.ok(events.some((e) => e[0] === "sdlc.model.route"));
});
test("pr mode blocks protected paths", async () => {
  const text = JSON.stringify({ title: "t", body: "b", files: [{ path: ".github/workflows/x.yml", content: "x" }, { path: "src/a.js", content: "1" }] });
  const { orch, calls } = harness({ chat: async () => ({ text, usage: {} }) });
  await orch.process("abcdef123", { repo: "o/r", number: 2, mode: "pr" });
  const pr = calls.find((c) => c[0] === "pr");
  assert.deepStrictEqual(pr[2].files.map((f) => f.path), ["src/a.js"]);
});
test("failure labels blocked and comments", async () => {
  const { orch, calls } = harness({ chat: async () => { throw new Error("boom"); } });
  await orch.process("abcdef123", { repo: "o/r", number: 3 });
  assert.ok(calls.some((c) => c[0] === "addLabels" && c[3].includes("squad:blocked")));
});

(async () => {
  let failed = 0;
  for (const [name, fn] of tests) {
    try { await fn(); console.log(`ok - ${name}`); } catch (e) { failed++; console.log(`FAIL - ${name}: ${e.message}`); }
  }
  process.exit(failed ? 1 : 0);
})();
