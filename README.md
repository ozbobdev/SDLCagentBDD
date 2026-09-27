# SDLCagentBDD

Document-driven software development lifecycle harness for Product Owners, Project Managers, and Developer agents (Senior, UI, API, DB).

## Purpose
Maintain two synchronized, versioned documentation streams that drive delivery:
- **Product Catalog wiki** (feature intent, boundaries, environments, history)
- **BDD wiki** (Gherkin scenarios, test mapping, acceptance behavior)

Agents help Product Owners capture change requests, create GitHub projects/issues, generate BDD specs, and keep docs synchronized with code, OpenAPI comments, tests, and screenshots.

## Primary Responsibilities
- Accept Product Owner feature requests and convert them into tracked, versioned artifacts.
- Create or update GitHub projects/issues per initiative.
- Create or update Product Catalog wiki and BDD wiki pages.
- Coordinate Developer agents to produce implementation plans and BDD-first tests.
- Maintain traceability across issue, PR, commit, OpenAPI changes, screenshots, and wiki versions.

## Standard Interaction Flow
1. **Intake**
   - Ask for GitHub project id **or** initiative name.
   - Ask for an annotated screenshot URL for UI changes.
   - Ask only essential clarifying questions: persona, acceptance criteria, environment (prod/test/dev), priority, complexity.
2. **Project and issue creation**
   - Create initiative project when no project exists or when scope/complexity warrants.
   - Create one issue per distinct feature/change request.
   - Populate issue with summary, acceptance criteria, screenshot link, suggested BDD scenarios, impacted components, priority, complexity.
3. **Documentation generation**
   - Create/update Product Catalog wiki page(s): feature details, boundaries, environment behavior, version history.
   - Create/update BDD wiki page(s): Gherkin scenarios for testers and developers.
   - Link wiki pages to issue and related pages.
4. **Developer handoff**
   - Break work into UI/API/DB/tests tasks.
   - Produce/update BDD specifications and acceptance tests **before code changes**.
   - Ensure OpenAPI3 endpoint comments/examples are updated for API changes.
5. **Test artifacts and screenshots**
   - Exercise each UI component in playground and theme test sandbox.
   - Save automated screenshots to `screenshots/`.
   - Trim captures to active component, document input options, and use unique non-datetime names.
   - Keep Product Catalog wiki image references versioned.
6. **Versioning and traceability**
   - Maintain version history for Product Catalog and BDD pages.
   - Each version references issue, PR, commit, OpenAPI change, and screenshot ids.

## Operational Rules
- Always create/update BDD specs before implementation begins.
- Always attach/reference annotated screenshots for UI work.
- Treat Product Owner acceptance language as source of truth.
- Ask minimal clarifying questions and refine scope through issue + PR comments.
- When scope is unclear, create a project and split into smaller issues.

## Required Outputs per Initiative
- GitHub project (optional, initiative-based)
- GitHub issue(s)
- Product Catalog wiki page(s) with version history
- BDD wiki page(s) with version history
- OpenAPI3 updates for API changes
- `screenshots/` artifacts referenced from docs
- PR with before/after UI screenshots when applicable

## Working Templates

### Intake Template
- Project ID (or initiative name):
- Annotated screenshot URL:
- Target persona:
- Acceptance criteria:
- Environment (prod/test/dev):
- Priority:
- Complexity:

### Issue Authoring Template
- Summary:
- Acceptance criteria:
- Annotated screenshot link:
- Suggested BDD scenarios:
- Impacted components (UI/API/DB/tests):
- Suggested priority:
- Estimated complexity:

### Traceability Record Template
- Issue:
- PR:
- Commit(s):
- Product Catalog page/version:
- BDD page/version:
- OpenAPI change:
- Screenshot refs (`screenshots/...`):

## Squad Leader Responsibilities
- Continuously improve SDLC workflow and documentation quality.
- Ensure humans and agents follow document-first lifecycle rules.
- Review and approve major Product Catalog and BDD documentation changes.

## Developer Checklist per Issue
- [ ] Update BDD wiki pages with final scenarios.
- [ ] Implement code updates with inline comments for UI modules/components/API endpoints.
- [ ] Update OpenAPI3 definitions with endpoint comments and examples.
- [ ] Add/update component tests and automated screenshot capture.
- [ ] Save screenshots under `screenshots/` and reference in Product Catalog.

## Squad CLI Examples
Run from a machine with Node.js/npm installed and GitHub Copilot CLI authenticated:
```bash
# Install the Squad CLI tooling globally
npm install -g @bradygaster/squad-cli

# Start the squad agent; --yolo enables non-interactive execution defaults
copilot --agent squad --yolo
```
