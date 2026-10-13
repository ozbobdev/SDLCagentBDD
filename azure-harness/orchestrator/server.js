"use strict";
// Orchestrator intake: POST /work-items (Entra-authenticated) -> route sub-tasks through the model router -> GitHub App (comment, labels, PR).
const http = require("http");
const https = require("https");
const config = require("../models/routing.json");
const { selectModel, VolumeTracker, CircuitBreaker } = require("../router/router");
const { verifyToken } = require("./auth");
const { createGitHubClient } = require("./github");
const { createTelemetry } = require("./telemetry");

const LEVELS = ["senior", "junior"];
const COMPLEXITIES = ["low", "medium", "high"];
const BLOCKED_PATH = /(^|\/)\.\.(\/|$)|^\.github\/|^\/|\.\w*ps1$/i;

function chatOnce(env, deployment, messages) {
  return new Promise((resolve, reject) => {
    const url = new URL(`/openai/deployments/${encodeURIComponent(deployment)}/chat/completions?api-version=${env.apiVersion}`, env.endpoint);
    const payload = JSON.stringify({ messages, max_completion_tokens: 4000 });
    const req = https.request(url, { method: "POST", headers: { "content-type": "application/json", "api-key": env.apiKey, "content-length": Buffer.byteLength(payload) } }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        if (res.statusCode === 429 || res.statusCode >= 500) return reject(Object.assign(new Error(`upstream ${res.statusCode}`), { retryable: true }));
        if (res.statusCode >= 300) return reject(new Error(`upstream ${res.statusCode}: ${text.slice(0, 200)}`));
        const json = JSON.parse(text);
        resolve({ text: json.choices[0].message.content, usage: json.usage || {} });
      });
    });
    req.on("error", (e) => reject(Object.assign(e, { retryable: true })));
    req.end(payload);
  });
}

function createOrchestrator(deps) {
  const { env, github, telemetry, chat = chatOnce, verify = verifyToken } = deps;
  const volume = new VolumeTracker();
  const breaker = new CircuitBreaker();
  const seen = new Map(); // idempotency key -> work id

  // One routed sub-task: pick a model, walk the fallback chain on retryable errors
  async function routed(hints, messages) {
    volume.record("all");
    const decision = selectModel(config, { ...hints, text: messages.map((m) => m.content).join("\n"), volume: hints.volume || volume.perMinute("all"), available: env.available.length ? env.available : undefined, unhealthy: [...breaker.unhealthy()] });
    for (const deployment of [decision.model, ...decision.fallbacks]) {
      try {
        const started = Date.now();
        const out = await chat(env, deployment, messages);
        breaker.success(deployment);
        telemetry.event("sdlc.model.route", { deployment, taskType: decision.taskType, complexity: decision.complexity, volumeTier: decision.volumeTier, reason: decision.reason, role: hints.role || "" }, { latencyMs: Date.now() - started, totalTokens: out.usage.total_tokens || 0 });
        return { ...out, decision, deployment };
      } catch (e) {
        if (!e.retryable) throw e;
        breaker.failure(deployment);
        telemetry.event("sdlc.model.fallback", { deployment, error: e.message });
      }
    }
    throw new Error("all candidate models failed");
  }

  function validate(item) {
    if (!item || typeof item !== "object") throw new Error("body must be an object");
    if (!/^[\w.-]+\/[\w.-]+$/.test(item.repo || "")) throw new Error("invalid repo");
    if (env.allowedRepos.length && !env.allowedRepos.includes(item.repo)) throw new Error("repo not allowed");
    if (!Number.isInteger(item.number) || item.number < 1) throw new Error("invalid number");
    if (item.level && !LEVELS.includes(item.level)) throw new Error("invalid level");
    if (item.complexity && !COMPLEXITIES.includes(item.complexity)) throw new Error("invalid complexity");
    if (item.taskType && !config.taskTypes[item.taskType]) throw new Error("invalid taskType");
    return item;
  }

  async function process(id, item) {
    const { repo, number } = item;
    const hints = { taskType: item.taskType || undefined, complexity: item.complexity, level: item.level, volume: item.volume === "high" ? "high" : item.volume, role: item.role };
    try {
      await github.addLabels(repo, number, ["squad:in-progress"]);
      const issue = await github.getIssue(repo, number);
      const context = `Repository: ${repo}\n${issue.pull_request ? "Pull request" : "Issue"} #${number}: ${issue.title}\n\n${(issue.body || "").slice(0, 12000)}`;
      const persona = `You are the ${item.level || "senior"} ${item.role || "squad member"} on an SDLC AI squad.`;

      if (item.mode === "pr") {
        const r = await routed({ ...hints, taskType: hints.taskType || "code_generation" }, [
          { role: "system", content: `${persona} Reply with JSON only: {"title":string,"body":string,"files":[{"path":string,"content":string}]}. Paths must be relative to the repo root and must not touch .github/ or scripts.` },
          { role: "user", content: context },
        ]);
        const plan = JSON.parse(r.text.replace(/^```(?:json)?|```$/gm, "").trim());
        const files = (plan.files || []).filter((f) => f && typeof f.path === "string" && typeof f.content === "string" && !BLOCKED_PATH.test(f.path));
        if (!files.length) throw new Error("model returned no permitted files");
        const pr = await github.openPullRequest(repo, { branch: `squad/issue-${number}-${id.slice(0, 6)}`, title: plan.title || `Squad: #${number}`, body: `${plan.body || ""}\n\nCloses #${number}\n\n_Model: ${r.deployment} (${r.decision.reason})_`, files });
        await github.comment(repo, number, `Opened ${pr.html_url} using \`${r.deployment}\`.`);
      } else {
        const r = await routed(hints, [
          { role: "system", content: `${persona} Triage the work and reply in Markdown with: summary, approach, risks, and the BDD scenarios or tests needed. Be concise.` },
          { role: "user", content: context },
        ]);
        await github.comment(repo, number, `${r.text}\n\n---\n_Squad ${item.level || "senior"} ${item.role || ""} - model \`${r.deployment}\` (${r.decision.taskType}, ${r.decision.complexity} complexity, ${r.decision.volumeTier} volume)_`);
      }
      await github.removeLabel(repo, number, "squad:in-progress");
      await github.addLabels(repo, number, ["squad:needs-review"]);
      telemetry.event("sdlc.workitem.done", { id, repo, number: String(number), mode: item.mode || "triage" });
    } catch (e) {
      telemetry.event("sdlc.workitem.failed", { id, repo, number: String(number), error: e.message });
      try {
        await github.removeLabel(repo, number, "squad:in-progress");
        await github.addLabels(repo, number, ["squad:blocked"]);
        await github.comment(repo, number, `Squad could not complete this work item: ${e.message}`);
      } catch { /* best effort */ }
    }
  }

  async function handle(req, res, body) {
    const send = (code, obj) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
    if (req.url === "/healthz") return send(200, { ok: true, github: github.configured, telemetry: telemetry.enabled });
    if (req.method !== "POST" || req.url !== "/work-items") return send(404, { error: "not found" });
    try {
      const token = (req.headers.authorization || "").replace(/^Bearer /i, "");
      await verify(token, { tenant: env.tenant, audience: env.audience, allowedClientIds: env.allowedClientIds, requiredRole: env.requiredRole });
    } catch (e) {
      telemetry.event("sdlc.workitem.denied", { reason: e.message });
      return send(401, { error: "unauthorized" });
    }
    let item;
    try { item = validate(JSON.parse(body || "{}")); } catch (e) { return send(400, { error: e.message }); }
    const key = req.headers["idempotency-key"];
    if (key && seen.has(key)) return send(200, { id: seen.get(key), duplicate: true });
    if (!github.configured) return send(503, { error: "GitHub App not configured" });
    const id = require("crypto").randomUUID();
    if (key) seen.set(key, id);
    telemetry.event("sdlc.workitem.accepted", { id, repo: item.repo, number: String(item.number), level: item.level || "", taskType: item.taskType || "" });
    send(202, { id });
    process(id, item);
  }

  return { handle, routed, process, validate };
}

function envFromProcess(e = global.process.env) {
  return {
    endpoint: e.AZURE_HARNESS_ENDPOINT,
    apiKey: e.AZURE_HARNESS_API_KEY,
    apiVersion: e.AZURE_OPENAI_API_VERSION || "2024-10-21",
    available: (e.AZURE_HARNESS_MODEL_DEPLOYMENTS || "").split(",").filter(Boolean),
    tenant: e.ENTRA_TENANT_ID,
    audience: e.ORCHESTRATOR_AUDIENCE,
    allowedClientIds: (e.ALLOWED_CLIENT_IDS || "").split(",").filter(Boolean),
    allowedRepos: (e.ALLOWED_REPOS || "").split(",").filter(Boolean),
    requiredRole: e.REQUIRED_APP_ROLE || "Dispatch",
  };
}

if (require.main === module) {
  const e = global.process.env;
  const env = envFromProcess(e);
  const orchestrator = createOrchestrator({
    env,
    github: createGitHubClient({ appId: e.GITHUB_APP_ID, installationId: e.GITHUB_APP_INSTALLATION_ID, privateKey: e.GITHUB_APP_PRIVATE_KEY }),
    telemetry: createTelemetry(e.APPLICATIONINSIGHTS_CONNECTION_STRING),
  });
  http.createServer((req, res) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => { size += c.length; if (size > 1024 * 1024) req.destroy(); else chunks.push(c); });
    req.on("end", () => orchestrator.handle(req, res, Buffer.concat(chunks).toString("utf8")).catch((err) => { res.writeHead(500); res.end(JSON.stringify({ error: err.message })); }));
  }).listen(Number(e.PORT || 8080), () => console.log(JSON.stringify({ event: "listening" })));
}

module.exports = { createOrchestrator, envFromProcess };
