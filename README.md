# SDLCdocs

Document driven software development lifecycle repository.

## Purpose
SDLCdocs defines a document-first SDLC where Product Owners, Developer agents, and Project Managers collaborate via a Product Catalog wiki and a BDD wiki. Agents automate intake, issue creation, BDD generation, and documentation maintenance.

## Repo structure
- AGENT_PROMPT.txt
- sub-agents.md
- github.md
- agents/
  - monitor_and_fix_bugs.md
- samples/
  - README.md
  - sample-squad.json
  - sample-app/
    - openapi-v0.1.yaml
    - openapi-v1.0.yaml
    - dotnet-api/
    - angular-web/
- screenshots/

## Squad
This repo needs a Squad team leader who iterates on documentation and SDLC workflows.

Install squad CLI
- npm install -g @bradygaster/squad-cli

Start copilot agent for squad
- copilot --agent squad --yolo

## How to contribute
- Product Owners: open issues for new features using the intake template.
- Developers: follow the Developer checklist in AGENT_PROMPT.txt.
- Squad leader: review and merge PRs that update SDLC workflows.

End of README.
