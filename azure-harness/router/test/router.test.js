"use strict";
const assert = require("assert");
const config = require("../../models/routing.json");
const { selectModel, VolumeTracker, CircuitBreaker } = require("../router");

const tests = [];
const test = (name, fn) => tests.push([name, fn]);

test("explicit model passes through", () => {
  assert.strictEqual(selectModel(config, { model: "gpt-6-sol", taskType: "debugging" }).model, "gpt-6-sol");
});
test("virtual model routes by task type", () => {
  assert.strictEqual(selectModel(config, { model: "sdlc-auto", taskType: "code_generation", complexity: "medium" }).model, "gpt-5.6-terra");
});
test("design review uses gpt-6.1-sol", () => {
  assert.strictEqual(selectModel(config, { taskType: "design_review", complexity: "medium" }).model, "gpt-6.1-sol");
});
test("high complexity escalates", () => {
  assert.strictEqual(selectModel(config, { taskType: "pr_review", complexity: "high" }).model, "gpt-6.1-sol");
});
test("chatbot high volume uses astra", () => {
  assert.strictEqual(selectModel(config, { taskType: "chatbot_knowledge", complexity: "medium", volume: 100 }).model, "gpt-6-astra");
});
test("simple code at high volume uses gpt-4o-mini", () => {
  assert.strictEqual(selectModel(config, { taskType: "code_generation", complexity: "low", volume: "high" }).model, "gpt-4o-mini");
});
test("medium code at high volume stays on normal model", () => {
  assert.strictEqual(selectModel(config, { taskType: "code_generation", complexity: "medium", volume: "high" }).model, "gpt-5.6-terra");
});
test("high complexity ignores volume", () => {
  assert.strictEqual(selectModel(config, { taskType: "chatbot_knowledge", complexity: "high", volume: "high" }).model, "gpt-6.1-sol");
});
test("low complexity at normal volume uses cost-optimised model", () => {
  assert.strictEqual(selectModel(config, { taskType: "pr_review", complexity: "low", volume: "normal" }).model, "gpt-6-sol");
});
test("senior level -> medium complexity, normal volume", () => {
  const r = selectModel(config, { taskType: "code_generation", level: "senior" });
  assert.strictEqual(r.model, "gpt-5.6-terra");
  assert.strictEqual(r.volumeTier, "normal");
});
test("junior level -> low complexity, high volume", () => {
  const r = selectModel(config, { taskType: "code_generation", level: "junior" });
  assert.strictEqual(r.model, "gpt-4o-mini");
  assert.strictEqual(r.volumeTier, "high");
});
test("classifies incident text", () => {
  const r = selectModel(config, { text: "Sev1 outage in production, please analyse the incident timeline" });
  assert.strictEqual(r.taskType, "incident_analysis");
  assert.strictEqual(r.model, "gpt-6.1-sol");
});
test("falls back when model unavailable", () => {
  const r = selectModel(config, { taskType: "debugging", complexity: "high", unhealthy: ["gpt-6.1-sol"] });
  assert.strictEqual(r.model, "gpt-6-sol");
});
test("falls back when deployment missing", () => {
  const r = selectModel(config, { taskType: "debugging", complexity: "high", available: ["gpt-4o-mini"] });
  assert.strictEqual(r.model, "gpt-4o-mini");
});
test("throws when nothing usable", () => {
  assert.throws(() => selectModel(config, { taskType: "debugging", available: [] }));
});
test("long context tier", () => {
  assert.strictEqual(selectModel(config, { taskType: "debugging", tokens: 150000 }).contextTier, "long_context");
});
test("volume tracker sliding window", () => {
  let t = 0;
  const v = new VolumeTracker(60000, () => t);
  for (let i = 0; i < 40; i++) v.record("k");
  assert.strictEqual(v.perMinute("k"), 40);
  t = 61000;
  assert.strictEqual(v.perMinute("k"), 0);
});
test("circuit breaker opens and recovers", () => {
  let t = 0;
  const cb = new CircuitBreaker({ threshold: 2, cooldownMs: 1000, now: () => t });
  cb.failure("m");
  assert.strictEqual(cb.isOpen("m"), false);
  cb.failure("m");
  assert.strictEqual(cb.isOpen("m"), true);
  t = 2000;
  assert.strictEqual(cb.isOpen("m"), false);
});

let failed = 0;
for (const [name, fn] of tests) {
  try {
    fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failed++;
    console.log(`FAIL ${name}: ${e.message}`);
  }
}
console.log(`${tests.length - failed}/${tests.length} passed`);
process.exit(failed ? 1 : 0);
