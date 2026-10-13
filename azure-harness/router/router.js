"use strict";

const COMPLEXITY_ORDER = { low: 0, medium: 1, high: 2 };

class VolumeTracker {
  constructor(windowMs = 60000, now = () => Date.now()) {
    this.windowMs = windowMs;
    this.now = now;
    this.events = new Map();
  }
  record(key = "all") {
    const list = this.events.get(key) || [];
    list.push(this.now());
    this.events.set(key, list);
  }
  perMinute(key = "all") {
    const cutoff = this.now() - this.windowMs;
    const list = (this.events.get(key) || []).filter((t) => t > cutoff);
    this.events.set(key, list);
    return (list.length * 60000) / this.windowMs;
  }
}

class CircuitBreaker {
  constructor({ threshold = 3, cooldownMs = 30000, now = () => Date.now() } = {}) {
    this.threshold = threshold;
    this.cooldownMs = cooldownMs;
    this.now = now;
    this.state = new Map();
  }
  failure(model) {
    const s = this.state.get(model) || { count: 0, openUntil: 0 };
    s.count += 1;
    if (s.count >= this.threshold) s.openUntil = this.now() + this.cooldownMs;
    this.state.set(model, s);
  }
  success(model) {
    this.state.delete(model);
  }
  isOpen(model) {
    const s = this.state.get(model);
    return !!s && s.openUntil > this.now();
  }
  unhealthy() {
    return new Set([...this.state.keys()].filter((m) => this.isOpen(m)));
  }
}

function classifyTaskType(config, text) {
  const lower = (text || "").toLowerCase();
  for (const [type, words] of Object.entries(config.keywords || {})) {
    if (words.some((w) => lower.includes(w))) return type;
  }
  return config.defaultTaskType;
}

function classifyComplexity(config, taskType, text, tokens) {
  const size = tokens || Math.ceil((text || "").length / 4);
  if (size > 20000) return "high";
  if (["incident_analysis", "debugging", "design_review"].includes(taskType) && size > 2000) return "high";
  if (size < 300) return "low";
  return "medium";
}

function selectModel(config, request = {}) {
  const available = request.available ? new Set(request.available) : null;
  const unhealthy = request.unhealthy ? new Set(request.unhealthy) : new Set();
  const usable = (m) => (!available || available.has(m)) && !unhealthy.has(m);
  const reasons = [];

  const level = request.level && config.levels[request.level];
  let taskType = request.taskType;
  if (!taskType || !config.taskTypes[taskType]) {
    taskType = classifyTaskType(config, request.text);
    reasons.push(`taskType=${taskType} (classified)`);
  }
  let complexity = request.complexity;
  if (!complexity && level) complexity = level.complexity.includes("medium") ? "medium" : level.complexity[0];
  if (!complexity) {
    complexity = classifyComplexity(config, taskType, request.text, request.tokens);
    reasons.push(`complexity=${complexity} (classified)`);
  }
  let volumeTier = request.volume;
  if (volumeTier !== "high" && volumeTier !== "normal") {
    const perMin = typeof request.volume === "number" ? request.volume : 0;
    volumeTier = level ? level.volume : perMin >= config.highVolumeThresholdPerMinute ? "high" : "normal";
  }

  const result = (model, extra) => ({
    model,
    fallbacks: config.fallbackChain.filter((m) => m !== model && usable(m)),
    taskType,
    complexity,
    volumeTier,
    reasoningEffort: config.reasoningEffort[complexity],
    contextTier: request.tokens && request.tokens > config.longContextTokens ? "long_context" : "default",
    reason: [...reasons, ...extra].join("; "),
  });

  // Rule 1: explicit model passes through when usable
  if (request.model && request.model !== config.virtualModel && usable(request.model)) {
    return result(request.model, ["explicit model pass-through"]);
  }

  // Rules 2-4: base model, complexity, volume
  const entry = config.taskTypes[taskType];
  let chosen = entry.normal;
  const notes = [`base ${chosen}`];
  if (complexity === "high") {
    chosen = entry.high;
    notes.push(`high complexity -> ${chosen}`);
  } else if (volumeTier === "high" && entry.highVolume) {
    const max = entry.highVolumeMaxComplexity || "high";
    if (COMPLEXITY_ORDER[complexity] <= COMPLEXITY_ORDER[max]) {
      chosen = entry.highVolume;
      notes.push(`high volume -> ${chosen}`);
    }
  } else if (complexity === "low" && entry.highVolume) {
    chosen = config.costOptimisedModel;
    notes.push(`low complexity -> ${chosen}`);
  }

  // Rule 5: fallback chain
  if (!usable(chosen)) {
    const next = config.fallbackChain.find(usable);
    if (!next) throw new Error("No usable model available");
    notes.push(`${chosen} unavailable -> fallback ${next}`);
    chosen = next;
  }
  return result(chosen, notes);
}

module.exports = { selectModel, VolumeTracker, CircuitBreaker, classifyTaskType, classifyComplexity };
