# Samples

This folder contains a sample squad and a sample application to demonstrate the SDLCdocs workflow.

## Sample squad
- `sample-squad.json` defines roles, each as a **senior** and a **junior** member:
  - Squad leader (senior-level routing)
  - Product Owner, Project Manager, Developer, UI Developer, API Developer, DB Developer, Tester
  - **Senior**: normal and medium/high complexity work (design reviews, debugging, architecture, incidents).
  - **Junior**: high-volume, low-complexity work.
  - Each member lists `taskTypes`, `complexity` and `volume`; the top-level `routing` block defines the levels and task types. These are sent to the model router (`sdlc-auto`) as hints, see [plan.md](../plan.md).

## Sample application
- **OpenAPI 3.0 API**
  - API version 0.1: static response samples for all endpoints.
  - API version 1.0: in-memory sample database for query/response.
  - OpenAPI3 document used to generate Web UI entity TypeScript.
- **Angular web**
  - Angular app scaffolded with Angular CLI.
  - Component playground and Theme sandbox.
  - Optional Cypress setup for UI sandbox tests and screenshot capture (see commands below).

## Skills to add
- BDD skill:
  - npx add-skill https://github.com/TheBushidoCollective/han/tree/main/plugins/patterns/bdd/skills/bdd-patterns
- Precompiled BDD Manual skill:
  - npx add-skill https://github.com/xz-dev/bdd-skill
- Angular web development skills:
  - npx skills add https://github.com/angular/skills
  - npx skills add https://github.com/angular/skills/tree/main/angular-new-app
- Angular sandbox UI test:
  - npm install cypress --save-dev
  - npx skills add https://github.com/cypress-io/ai-toolkit --skill cypress-author
  - npx skills add https://github.com/cypress-io/ai-toolkit --skill cypress-explain
  - npx skills add https://github.com/cypress-io/ai-toolkit --skill cypress-tap
  - npx skills add https://github.com/cypress-io/ai-toolkit --skill cypress-cloud-cli
  - npx skills add https://github.com/cypress-io/ai-toolkit --skill cypress-docs

End of samples README.
