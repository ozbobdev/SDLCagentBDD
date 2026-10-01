name: monitor_and_fix_bugs
description: >
  Sweeps a running site with a visible Playwright browser. For anything broken it
  screenshots the failure, files a GitHub issue, fixes the root cause, and opens a
  PR - with before/after screenshots attached to both. Use when someone says
  "check my site", "monitor for bugs", "find and fix errors on the site".

Preflight
- Ensure the site is already running. Do not start or stop the user's server.
- Use a gh client that supports PR attachments if attaching images to PRs.

Workflow
1. Crawl the site with Playwright.
2. For each failure:
   - Capture screenshot evidence.
   - Create a GitHub issue with reproduction steps and attach the screenshot.
   - Attempt an automated fix if safe and deterministic.
   - Open a PR with before/after screenshots and link to the issue.
3. Close the loop by re-running tests and attaching proof of fix.

Example GH PR create command
- Use the gh CLI to create PRs and attach images:
  gh pr create --title "Fix: <short description>" --body "Fixes #<issue>" --attach "evidence/after.png#After screenshot"

End of monitor_and_fix_bugs agent doc.
