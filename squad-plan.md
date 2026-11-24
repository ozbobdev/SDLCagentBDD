# Plan: local Squad setup and collaboration

## Goal and scope

Produce a guide for a developer's local PC using Squad, VS Code, SquadUI and an Anthropic API key with `ozbobdev/SDLCagentBDD`. Start with one machine; plan two-machine coordination and mixed model providers as later phases. This is a plan, not an installed or validated configuration. Record the OS, versions, account permissions and results during the pilot because provider and host capabilities can change.

The existing [local repository workflow](./README.md#local-repository-workflow) uses Copilot CLI and Squad CLI. [samples/sample-squad.json](./samples/sample-squad.json) is a source of role ideas, not a confirmed Squad import format. The existing [Foundry and cloud-agent guidance](./github.md) remains separate from this local setup.

## Phase 1 — one PC and one repository

1. **Check prerequisites and access.** Document Windows/macOS/Linux differences as needed. Install Git, Node.js/npm (Squad's npm installation requires Node.js 22.5 or later), GitHub CLI, GitHub Copilot CLI and VS Code with GitHub Copilot Chat. Install [SquadUI](https://marketplace.visualstudio.com/items?itemName=csharpfritz.squadui) (its README specifies VS Code 1.85 or later). Confirm repository access, Copilot entitlement and policy, an Anthropic account with a tool-capable Claude model and API key, network access and a spending limit. Authenticate `gh` and Copilot CLI independently; verify with `gh auth status` and a harmless Copilot session without displaying tokens.
2. **Prepare the checkout.** Clone `https://github.com/ozbobdev/SDLCagentBDD.git` using the user's normal Git authentication, open the repository folder in VS Code, and create a working branch. Review the working tree before initialization. Install Squad using `npm install -g @bradygaster/squad-cli`, run `squad init` from the repository root, and inspect the generated changes before committing any of them. Confirm `.squad/team.md` exists. Use the sample roles to define a small lead, developer and tester team in Squad's supported format; do not overwrite existing team state or assume the JSON can be imported.
3. **Configure Claude for a local CLI pilot.** Follow GitHub's [Copilot CLI provider instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-llm-models) for an `anthropic` provider and a Claude model available to the account, then restart the CLI and select that provider/model. Confirm tool calling and streaming work with a harmless task. The documented `providers.json` stores credentials in plaintext; keep it outside the checkout with user-only permissions, never commit or share it, and do not assume JSON expands environment variables. Prefer a supported secret-backed option if the installed version offers one. Do not paste the key into chat, terminal history, logs, screenshots or issues. Rotate it if exposed. Record only the provider/model identifier and outcome, not the credential.
4. **Exercise VS Code and SquadUI.** In Copilot Chat, select the Squad agent and run a read-only task, such as summarizing the sample app. Open the SquadUI sidebar and dashboard and check that the roster, decisions and activity correspond to the initialized team. **Compatibility gate:** current Squad documents `.squad/`, whereas SquadUI's README describes `.ai-team/`. Check the installed versions and verify actual support before relying on the extension; do not create divergent copies or migrate/overwrite state just to make the view appear. If unsupported, document the limitation and use Squad's supported local view/CLI until compatibility is resolved.
5. **Validate and document.** Compare a CLI session explicitly using Anthropic with a VS Code session, recording which host and provider actually served each. A Claude model offered by Copilot is not proof that the Anthropic API key was used; CLI BYOK configuration does not by itself configure VS Code or the hosted cloud agent. Review generated files and logs for secrets and personal data; commit only approved team configuration and documentation through a PR. Document safe cleanup and key rotation.

**Exit criteria:** a fresh checkout can follow the guide, initialize a usable team, complete a harmless repository task and demonstrate the intended Anthropic-backed CLI call. The VS Code/SquadUI result and any compatibility limitation are recorded rather than assumed.

## Phase 2 — two machines and task-complexity routing

1. Set up two independent checkouts and authenticated users using phase 1; agree on the same Squad version, roster, file ownership and which sanitized `.squad/` files may be shared. Keep credentials and machine-local state out of Git. Assign distinct members and non-overlapping tasks to the two machines.
2. Start with **asynchronous GitHub issues/PRs plus reviewed Git commits** as the message and handoff channel. Each handoff identifies the issue, sender/member, recipient, task, branch/commit, status and expected response; never include keys or sensitive prompts. Push the approved state on a branch, have the other machine fetch and review it, acknowledge in the issue, and return a result by PR. Agree how conflicts and concurrent edits are resolved, who merges, and how to recover from an offline or stale checkout. Git and SquadUI file watching do not provide live delivery, locking or guaranteed ordering across machines.
3. Evaluate [Squad distributed mesh](https://github.github.io/squad/docs/features/distributed-mesh/) only if this handoff is insufficient: compare its documented git-synced remote state with the same-repo scenario and validate access, data exposure, refresh, conflict handling and failure recovery before adoption. It is not assumed to be a real-time message queue. If automated watchers are later needed, evaluate [multi-machine work claims](https://github.github.io/squad/docs/scenarios/multi-machine-watch/), including host ref permissions, lease recovery and possible duplicate execution. Avoid exposed endpoints or automatic remote execution without a separate security review.
4. Define a reviewable routing policy, then test it against actual model availability and budgets:

   | Task complexity | Example in this repo | Starting policy |
   | --- | --- | --- |
   | Low | summarize docs or triage an issue | fast, lower-cost model |
   | Medium | implement a scoped sample-app change and tests | standard coding-capable model |
   | High | architecture, security-sensitive changes or cross-component review | premium reasoning model and human review |

   Record the task, selected member, host, model/provider, reason, cost/latency and result. Start with manual selection; evaluate Squad's [model selection](https://github.github.io/squad/docs/features/model-selection/) and per-agent overrides on the actual CLI version before automating. In VS Code, Squad documents one session model for all agents; do not promise per-agent selection there. Escalate ambiguous or failed tasks to a human or stronger available model, not an unrestricted autonomous retry.
5. Run a two-machine drill: machine A publishes a sanitized task and state, machine B fetches, acknowledges, completes its distinct task and returns a PR; A reviews and merges. Repeat with conflicting edits and an offline/reconnect case. Verify delivery, ownership, no lost changes, no secrets and an auditable decision trail.

**Exit criteria:** the drill demonstrates a reproducible handoff and recovery path; model choices and limitations are measured rather than inferred.

## Phase 3 — mixed providers

Create and validate a provider/host compatibility matrix before promising that individual members can use different providers concurrently:

| Provider | Planned path | Validation and boundary |
| --- | --- | --- |
| Anthropic Claude | Local Copilot CLI Anthropic BYOK from phase 1 | Verify the selected model and direct provider billing; keep the key local. |
| Microsoft Foundry | Evaluate the supported Azure provider/model deployment in the local CLI or a separate [Copilot SDK BYOK](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/byok) process; see [github.md](./github.md). | Verify endpoint, deployment, permissions, model capabilities and billing. A Foundry Prompt Agent or SDK configuration does not automatically configure Squad, VS Code or the hosted cloud agent. |
| GitHub Copilot subscription | Use GitHub-provided models available to the signed-in account. | Verify the actual plan, policy, model picker, quotas and premium-request charges; do not assume a “max” subscription enables every model or provider. |

For each intended member-to-model mapping, verify whether the chosen host supports the provider-qualified model and per-agent routing, including simultaneous mixed-provider sessions. Test one harmless task per provider, then a coordinated task with distinct members; record observed selection and billing without secrets. If unsupported, use separate explicitly selected sessions or manual handoffs and document the limitation; do not silently substitute a provider. Set budgets, permissions, retention and escalation rules before production use.

**Exit criteria:** each supported path has an independently verified smoke test, documented credentials/entitlements and an explicit fallback; unsupported combinations remain open decisions.

## References and decisions to resolve

- [Squad quick start](https://github.github.io/squad/docs/get-started/five-minute-start/), [CLI reference](https://github.github.io/squad/docs/reference/cli/) and [migration](https://github.github.io/squad/docs/get-started/migration/).
- [SquadUI README](https://github.com/csharpfritz/SquadUI#readme) for installation and its documented state directory.
- [Copilot CLI setup](https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started) and [provider configuration](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-llm-models).
- Confirm the target PC OS, approved models and budgets, participants, shared-state retention policy, and whether asynchronous handoffs meet the desired messaging latency before implementing later phases.
