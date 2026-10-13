# Plan: Copilot Provider and Azure AI Harness with model routing

## Problem and approach

Pick the right model per task and sub-task using type, complexity and volume. Two pieces:

1. Router core (`azure-harness/router/`): `selectModel(task) -> { deployment, fallbacks, reason }`, driven by `azure-harness/models/routing.json`.
2. Two front doors over the same core:
   - Copilot Provider: OpenAI-compatible endpoint (`/v1/chat/completions`, `/v1/models`) for local Copilot SDK BYOK; virtual model `sdlc-auto` triggers routing, explicit model names pass through.
   - Azure AI Harness: Azure-hosted orchestrator (Container Apps) calls the router per sub-agent call and fans out to Foundry deployments.

GitHub cloud-agent boundary ([sub-agents.md](./sub-agents.md), [github.md](./github.md)) is unchanged; Foundry keys never become Agents secrets.

## Routing model

Inputs: taskType, complexity (low/med/high), volume (rolling req/min tier), optional budget/latency class.
Classification: caller hints win (header `x-sdlc-task-type`); else cheap classifier (gpt-4o-mini) plus heuristics (context size, stack traces, keywords).

| Task type | Normal | High complexity | High volume |
|---|---|---|---|
| Chatbot / knowledge assistant | gpt-5.6-terra | gpt-6.1-sol | gpt-6-astra |
| Code generation | gpt-5.6-terra | gpt-6.1-sol | gpt-4o-mini (simple only) |
| Pull request review | gpt-5.6-terra | gpt-6.1-sol | gpt-5.6-terra |
| Architecture discussion | gpt-5.6-terra | gpt-6.1-sol | n/a |
| Major design review | gpt-6.1-sol | gpt-6.1-sol | n/a |
| Difficult debugging | gpt-6.1-sol | gpt-6.1-sol | n/a |
| Complex incident analysis | gpt-6.1-sol | gpt-6.1-sol | n/a |
| Fallback / cost-optimised | gpt-6-sol | - | gpt-6-sol |

Rules in order:
1. Explicit model passes through if policy allows.
2. Task type -> base model.
3. High complexity escalates; low and simple demotes.
4. Volume over threshold -> high-volume model, unless complexity is high.
5. Quota/429/5xx/missing deployment -> fallback chain (6.1-sol -> 6-sol -> 5.6-terra -> 4o-mini) with retry and circuit breaker.
6. Sub-tasks are routed independently (e.g. design review = summarise cheap + analyse 6.1-sol + format mini).

Every decision is logged to App Insights (type, complexity, volume tier, model, fallback, tokens, latency, cost).

## Cloud agent limits

- GitHub's hosted Copilot cloud agent uses GitHub-supported models. As far as we know it cannot be pointed at a custom provider such as the Azure AI Harness (re-check GitHub docs periodically). BYOK applies to the local Copilot SDK/CLI, not the hosted agent.
- Never add the Foundry key as an **Agents** secret: those are exposed to the agent as environment variables.
- Supported patterns: (a) the cloud agent uses its own GitHub models; (b) **preferred for token savings:** the cloud agent does not spend tokens on routed work. An Actions workflow watches issues and labels, and hands labelled work to the Azure Harness orchestrator, which delegates to sub-agents and sends commits/PRs through the GitHub API (see "Event-driven delegation" below); (c) a maintainer manually dispatches the same workflow when needed. Azure credentials stay in the workflow's protected environment, never in Agents secrets.
- If GitHub later adds custom providers for the cloud agent, the OpenAI-compatible provider should work unchanged.

## Squad integration (bradygaster/squad `squad.agent.md`)

Findings from the Squad Coordinator prompt:
- It is a **dispatcher**: never does domain work, spawns specialists via `create_session` (Copilot App), `task` (CLI) or `runSubagent` (VS Code). Roles come from `.squad/team.md`, `.squad/routing.md`, `.squad/casting/*`; mandatory Scribe, Ralph (work monitor), Rai, Fact Checker.
- It has **its own model selection**: per-spawn `model`, reasoning effort and context tier resolved from `.squad/config.json` (`agentReasoningEffortOverrides`, `defaultReasoningEffort`, `agentContextTierOverrides`), user directives, charter `## Model` section, then task-aware auto-selection with fallback chains (`.squad/templates/model-selection-reference.md`). VS Code `runSubagent` cannot set a per-spawn model.
- Issue flow: `squad:{member}` labels; a `sync-squad-labels` workflow labels new `squad` issues and the Lead triages. State backends: `local`, `orphan`, `two-layer`.
- The file contains **no workflow-generation instructions** itself; workflows and skills are installed by `squad init`/`squad upgrade` (into `.github/`), and Squad's templates should be reviewed before generating our own.

Alignment with this plan:
| Squad | This plan | Decision |
|---|---|---|
| Coordinator dispatches only | Orchestrator routes to sub-agents | Same pattern; the Squad Coordinator is the orchestrator and our router becomes its model layer. Do not build a second orchestrator. |
| Per-spawn `model` | Router `selectModel` | Router is exposed as the `sdlc-auto` model on the provider. Squad charters/config set `model: sdlc-auto` (or explicit overrides) and the provider picks the real deployment. |
| Reasoning effort / context tier | Not covered | Add to routing output (`reasoningEffort`, `contextTier`) and honour request values; do not switch model for these. |
| Role-based routing (`routing.md`) | Task-type routing | Map Squad roles to task types (Lead->architecture/design review, Tester->code gen, Reviewer->PR review, Ralph->high-volume, etc.); `sample-squad.json` roles gain `taskType`. Squad's per-agent override wins over router (rule 1 pass-through). |
| Fallback chains | Fallback chain + circuit breaker | Keep ours server-side so any client benefits; align model names with Squad's catalog. |
| Ralph / work monitor, issue labels | Volume tier | Ralph loops are the main source of high-volume traffic: tag them `x-sdlc-volume: high`. |
| Dispatch tool varies by client | Provider works for any client | Provider only helps clients that support BYOK/custom endpoints; VS Code `runSubagent` uses the session default. |

Squad level mapping (implemented in `samples/sample-squad.json`): every role is duplicated as **senior** (medium/high complexity, normal volume) and **junior** (low complexity, high volume). Complexity and volume feed router rules 3-4; `taskTypes` map to the routing table (`chatbot_knowledge`, `code_generation`, `pr_review`, `architecture_discussion`, `design_review`, `debugging`, `incident_analysis`). Senior high complexity -> gpt-6.1-sol / gpt-5.6-terra; junior -> gpt-6-astra / gpt-4o-mini / gpt-6-sol.

## Squad configuration: workflow calling the harness on Azure

Goal: minimise GitHub cloud agent token usage. Event-driven delegation instead of the agent asking for help: a workflow watches issues and labels and allocates the work to the Azure Harness orchestrator, which delegates and commits via the GitHub API. The cloud agent is left for work that truly needs it (or is not used at all for labelled issues).

### Event-driven delegation
1. **Trigger:** workflow on `issues` (opened, labeled), `issue_comment` (slash command or `squad` mention) and `pull_request` (labeled / review requested), plus `workflow_dispatch`. It filters by labels: `squad` (hand to Azure), `squad:{member}` (target role), `level:senior|junior`, `complexity:low|medium|high`, `type:{taskType}`, `volume:high` (set by triage or Ralph). Issues without a `squad` label are left to the cloud agent or humans.
2. **Allocation (cheap, deterministic, no LLM):** the workflow maps labels to a work item `{repo, issueOrPr, role, level, taskType, complexity, volume}` using the senior/junior mapping from `sample-squad.json`; missing labels default to senior/medium and triage by the orchestrator Lead. It authenticates to Azure with OIDC and posts the work item to the orchestrator queue/endpoint (Service Bus or HTTPS on Container Apps), then exits; no long-running job in Actions.
3. **Delegation on Azure:** the orchestrator (Squad Coordinator pattern) picks the role, splits into sub-tasks and calls the router (`sdlc-auto`) per sub-task. Junior work goes to high-volume/cheap models; senior work to normal/high models.
4. **Commits and feedback via GitHub API:** a GitHub App (credentials in Key Vault) creates branches, commits, PRs, comments and status updates; it swaps labels (`squad:in-progress`, `squad:needs-review`, `squad:done`) so the workflow and humans can see state. Least privilege: contents, pull requests, issues.
5. **Loop prevention and cost control:** ignore events from the App's own bot user; one active work item per issue (idempotency key = issue + label + sha); concurrency limit and per-item token budget; retries with back-off; failures comment on the issue and set `squad:blocked`.
6. **Human gates:** PRs only (no pushes to protected branches), required reviews, environment approval for sensitive labels (for example `type:incident_analysis` or infra changes). Audit via App Insights.
7. Reuse Squad's `sync-squad-labels`/triage workflows rather than rewriting them; the new workflow only forwards work. Squad itself, where BYOK is possible (Copilot SDK/CLI), uses `.squad/config.json` and charters set to model `sdlc-auto`.

Expected effect: the cloud agent's tokens are spent only on unlabelled or explicitly assigned issues; routine, high-volume and routed work uses Azure model deployments.

## Todos
1. routing-config: routing.json + schema.
2. router-core: classifier, rule engine, volume tracker, fallback/circuit breaker, BDD-style unit tests (needs 1).
3. foundry-deployments: Terraform `model_deployments` map in variables.tf/main.tf/outputs.tf; default stays gpt-4o-mini; verify region/quota; don't touch legacy tfstate.
4. provider-endpoint: OpenAI-compatible streaming gateway on Container Apps, Entra managed identity to Foundry, Key Vault (needs 2).
5. copilot-byok-wiring: update infra/003ConfigureBYOK.ps1 and github.md; smoke test via `foundry-byok` env (needs 4).
6. orchestrator-integration: sub-agents call router with task hints; add taskType/model to samples/sample-squad.json (needs 4).
7. observability-cost: App Insights events, cost workbook, budget alerts, cheap-fallback kill-switch (needs 4).
8. docs: update sub-agents.md "Model choices"; add azure-harness/README.md (last).
9. eval-tuning: offline eval set per task type to tune thresholds (needs 2, 3).
10. squad-model-mapping: add reasoningEffort/contextTier to routing output; map Squad roles to task types in `sample-squad.json`; document `.squad/config.json` using `sdlc-auto` (needs 2).
11. squad-dispatch-workflow: issue/label/comment-triggered workflow (plus `workflow_dispatch`) that maps labels to a work item and posts it to the orchestrator via OIDC; define the label taxonomy (`squad`, `squad:{member}`, `level:*`, `complexity:*`, `type:*`, status labels); loop prevention and idempotency; GitHub App for commits/PRs; review Squad's installed workflow templates first (needs 4, 6).
12. orchestrator-intake: orchestrator work-item intake (queue/HTTPS), role selection, GitHub App commit/PR/label-update client, status reporting (needs 4, 6).

## Assumptions
- Model names used as given; availability/quota/region (australiaeast) verified before Terraform changes.
- Router/provider in TypeScript/Node (proposed default).
- Self-hosted gateway, not APIM (can add later).
- Provider serves local SDK and Azure orchestrator only, not the GitHub-hosted cloud agent.

## Status
- Done: routing-config, router-core (18 tests), foundry-deployments (applied; 5 deployments in rg-sdlcdocs-harness-aue), provider-endpoint (live-tested), squad-model-mapping (sample-squad.json), squad-dispatch-workflow (workflow file), docs.
- Remaining: orchestrator-intake and orchestrator-integration (Container Apps hosting, GitHub App), copilot-byok-wiring, observability-cost, eval-tuning.

### Orchestrator, Container Apps, App Insights (code complete, not yet deployed)
- azure-harness/orchestrator: intake (Entra JWT), routed model calls, GitHub App client, App Insights events; 13 unit tests pass.
- Terraform: sdlc-appinsights, Log Analytics, Foundry connection, ACR, Container App; 002SetupAzure.ps1 -DeployOrchestrator creates Entra/OIDC identities, builds the image and stores outputs.
- See ai-squad.md.
