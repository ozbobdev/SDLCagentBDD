"use strict";
// OpenAI-compatible gateway: POST /v1/chat/completions, GET /v1/models, GET /healthz.
// Model "sdlc-auto" is routed per request; any other model name passes through.
// Hints: headers x-sdlc-task-type, x-sdlc-complexity, x-sdlc-level, x-sdlc-volume.
const http = require("http");
const https = require("https");
const config = require("../models/routing.json");
const { selectModel, VolumeTracker, CircuitBreaker } = require("../router/router");

const endpoint = process.env.AZURE_HARNESS_ENDPOINT;
const apiKey = process.env.AZURE_HARNESS_API_KEY;
const clientToken = process.env.PROVIDER_CLIENT_TOKEN;
const apiVersion = process.env.AZURE_OPENAI_API_VERSION || "2024-10-21";
const available = (process.env.AZURE_HARNESS_MODEL_DEPLOYMENTS || "").split(",").filter(Boolean);
const port = Number(process.env.PORT || 8080);

const volume = new VolumeTracker();
const breaker = new CircuitBreaker();

function log(event) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), ...event }));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > 4 * 1024 * 1024) {
        reject(new Error("request too large"));
        req.destroy();
      } else chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function callUpstream(deployment, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(`/openai/deployments/${encodeURIComponent(deployment)}/chat/completions?api-version=${apiVersion}`, endpoint);
    const payload = JSON.stringify({ ...body, model: undefined });
    const req = https.request(
      url,
      { method: "POST", headers: { "content-type": "application/json", "api-key": apiKey, "content-length": Buffer.byteLength(payload) } },
      resolve
    );
    req.on("error", reject);
    req.end(payload);
  });
}

async function handleChat(req, res) {
  const body = JSON.parse(await readBody(req));
  const text = (body.messages || []).map((m) => (typeof m.content === "string" ? m.content : JSON.stringify(m.content))).join("\n");
  volume.record("all");
  const decision = selectModel(config, {
    model: body.model,
    taskType: req.headers["x-sdlc-task-type"],
    complexity: req.headers["x-sdlc-complexity"],
    level: req.headers["x-sdlc-level"],
    volume: req.headers["x-sdlc-volume"] || volume.perMinute("all"),
    text,
    available: available.length ? available : undefined,
    unhealthy: [...breaker.unhealthy()],
  });

  const chain = [decision.model, ...decision.fallbacks];
  for (const deployment of chain) {
    try {
      const upstream = await callUpstream(deployment, body);
      if (upstream.statusCode === 429 || upstream.statusCode >= 500) {
        upstream.resume();
        breaker.failure(deployment);
        log({ event: "fallback", deployment, status: upstream.statusCode });
        continue;
      }
      breaker.success(deployment);
      log({ event: "route", deployment, ...decision, status: upstream.statusCode });
      res.writeHead(upstream.statusCode, { "content-type": upstream.headers["content-type"] || "application/json", "x-sdlc-model": deployment, "x-sdlc-reason": decision.reason.replace(/[^\x20-\x7e]/g, "") });
      upstream.pipe(res);
      return;
    } catch (e) {
      breaker.failure(deployment);
      log({ event: "upstream_error", deployment, error: e.message });
    }
  }
  res.writeHead(502, { "content-type": "application/json" });
  res.end(JSON.stringify({ error: { message: "All candidate models failed" } }));
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.url === "/healthz") return res.end("ok");
    if (clientToken && req.headers.authorization !== `Bearer ${clientToken}`) {
      res.writeHead(401, { "content-type": "application/json" });
      return res.end(JSON.stringify({ error: { message: "unauthorized" } }));
    }
    if (req.method === "GET" && req.url === "/v1/models") {
      const ids = [config.virtualModel, ...available];
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ object: "list", data: ids.map((id) => ({ id, object: "model", owned_by: "sdlc-harness" })) }));
    }
    if (req.method === "POST" && req.url === "/v1/chat/completions") return await handleChat(req, res);
    res.writeHead(404);
    res.end();
  } catch (e) {
    log({ event: "error", error: e.message });
    res.writeHead(400, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { message: e.message } }));
  }
});

if (require.main === module) {
  if (!endpoint || !apiKey) {
    console.error("AZURE_HARNESS_ENDPOINT and AZURE_HARNESS_API_KEY are required");
    process.exit(1);
  }
  server.listen(port, () => log({ event: "listening", port }));
}

module.exports = { server };
