"use strict";
// Minimal Application Insights ingestion (no SDK): sends custom events to the v2 track endpoint.
const https = require("https");

function parse(cs) {
  const parts = Object.fromEntries((cs || "").split(";").filter(Boolean).map((p) => p.split(/=(.*)/s).slice(0, 2)));
  return { key: parts.InstrumentationKey, endpoint: (parts.IngestionEndpoint || "https://dc.services.visualstudio.com/").replace(/\/$/, "") };
}

function createTelemetry(connectionString, role = "sdlc-orchestrator") {
  const cfg = parse(connectionString);
  return {
    enabled: !!cfg.key,
    event(name, properties = {}, measurements = {}) {
      console.log(JSON.stringify({ ts: new Date().toISOString(), event: name, ...properties, ...measurements }));
      if (!cfg.key) return;
      const body = JSON.stringify({
        name: "Microsoft.ApplicationInsights.Event",
        time: new Date().toISOString(),
        iKey: cfg.key,
        tags: { "ai.cloud.role": role },
        data: { baseType: "EventData", baseData: { ver: 2, name, properties, measurements } },
      });
      const req = https.request(`${cfg.endpoint}/v2/track`, { method: "POST", headers: { "content-type": "application/json", "content-length": Buffer.byteLength(body) } }, (r) => r.resume());
      req.on("error", () => {});
      req.end(body);
    },
  };
}

module.exports = { createTelemetry };
