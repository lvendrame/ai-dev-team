# AI Dev Team

![Agents](https://img.shields.io/badge/agents-8-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Works with](https://img.shields.io/badge/works%20with-Claude%20Code%20%7C%20Cursor%20%7C%20Copilot%20%7C%20Gemini%20%7C%20OpenCode%20%7C%20Codex-purple)

A collection of AI agent personas that bring a complete software development team to your editor. Each agent adopts a specific role — from defining the project charter to writing tested, production-ready code — and collaborates through a shared `project-hub/` knowledge base in your repository.

Agents are built for **Claude Code** and can be adapted for Cursor, GitHub Copilot, OpenCode, Gemini CLI, and Codex CLI via the installer.

---

## Agents

### Project Manager — `/aiteam-project-manager`

Creates or updates `project-hub/Project.md` — the project charter. Runs a conversational interview to capture the project name, vision, goals and success metrics, stakeholders, scope (in and out), team, timeline, constraints, risks, and asset references.

### Software Architect — `/aiteam-architect`

**Without a task argument:** Interviews you about architecture style, frontend/backend stack, database, infrastructure, and integrations. Produces or updates `project-hub/architecture.md` with all architectural decisions as ADRs.

**With a task path:** Reads the task and the architecture document, appends a `## Technical Design` section (affected components, API changes, data model changes, infrastructure changes), and proposes new ADRs if the task introduces novel architectural decisions.

### Observability Engineer — `/aiteam-observability-engineer`

**Without a task argument:** Interviews you about your observability tooling and SLO targets, then appends a `## Observability & Measuring` section to `project-hub/architecture.md` — covering the telemetry stack (logs, metrics, traces), RED/USE methods, structured log format, SLO table, alerting strategy, required dashboards, and instrumentation guidelines.

**With a task path:** Reads the task and the architecture's observability strategy, then appends a `## Observability` section to the task with specific metric names, log events, trace spans, SLIs, alert conditions, dashboard panels, and at least three early warning signals.

### UI/UX Engineer — `/aiteam-uiux-engineer`

**Without a task argument:** Interviews you about brand colors, screen targets, light/dark theme, and visual style. Generates a complete design system in `project-hub/design-system/` — five files: `reset.css`, `tokens.css` (9-step color scales, spacing, typography), `components.css` (layout, buttons, forms, cards, badges, navigation, alerts), `index.html` (living component showcase), and `DesignSystemGuide.md`.

**With a task path:** Analyses the user story and acceptance criteria, identifies all screens and states, and generates responsive HTML/CSS prototypes in `project-hub/prototypes/<task-slug>/` using the design system. Writes a `## Prototypes` reference table back into the task file.

### Product Owner — `/aiteam-product-owner`

Takes a feature idea (as an argument or through a short interview), asks for supporting documentation, does web research, and writes a user story task file to `project-hub/tasks/YYYY-MM-DD-<title>.md` following the Scrum user story format (user story, context, acceptance criteria, out of scope, references).

### QA Engineer — `/aiteam-qa-engineer <task>`

Reads a task file and enriches its `## Acceptance Criteria` section with four organised groups — Functional Happy Path, Functional Error & Negative Cases, Edge Cases, and Non-Functional (with measurable thresholds). Also adds a `## Test Plan` section covering test strategy, test types, test data requirements, environment requirements, risk areas, and out-of-scope boundaries.

### Backend Engineer — `/aiteam-backend-engineer <task>`

Reads the task, architecture, and existing codebase; presents a file-by-file implementation plan; then implements the backend following strict TDD:

1. Scaffolds Clean Architecture (`domain/` → `application/` → `infrastructure/`)
2. Implements the correlation ID layer (request-scoped context, HTTP middleware, structured logger)
3. Writes all tests from the acceptance criteria first (Red phase)
4. Implements code in dependency order to make tests pass (Green phase)
5. Refactors for DRY, SRP, and DIP compliance
6. Runs tests → lint → build → coverage; coverage must be ≥ 90% for files, functions, and branches
7. Marks the task as backend-implemented

### Frontend Engineer — `/aiteam-frontend-engineer <task>`

Reads the task, architecture, design system, and the task's HTML/CSS prototypes as a visual specification; presents a component-by-component implementation plan; then implements the frontend following strict TDD:

1. Scaffolds the component architecture (`shared/` → `features/` → `pages/`, `hooks/`, `services/`)
2. Implements the correlation ID interceptor (outbound request header, inbound response header capture, error formatter)
3. Writes all tests from the acceptance criteria first using the testing library's semantic queries (Red phase)
4. Implements services → shared components → hooks → feature components → pages (Green phase)
5. Refactors for DRY, SRP, and accessibility compliance
6. Runs tests → lint → build/type-check → coverage; coverage must be ≥ 90% for files, functions, and branches
7. Marks the task as frontend-implemented

---

## How Agents Collaborate

Agents read from and write to a `project-hub/` directory in your project. This directory is the shared knowledge base — create it at your project root.

```
project-hub/
  Project.md              ← project charter (written by project-manager)
  architecture.md         ← architecture + ADRs + observability strategy
  design-system/          ← CSS tokens, components, showcase, guide
  tasks/
    YYYY-MM-DD-feature.md ← one file per feature, enriched by each agent
  prototypes/
    <task-slug>/          ← HTML/CSS screens for each task
```

### Recommended workflow

**Project setup (once):**

1. `/aiteam-project-manager` — define the project charter
2. `/aiteam-architect` — define system architecture
3. `/aiteam-observability-engineer` — add observability strategy to the architecture
4. `/aiteam-uiux-engineer` — build the design system

**Per feature:**

5. `/aiteam-product-owner` — write the feature task
6. `/aiteam-architect <task>` — add Technical Design
7. `/aiteam-qa-engineer <task>` — enrich Acceptance Criteria and add Test Plan
8. `/aiteam-observability-engineer <task>` — add Observability section
9. `/aiteam-uiux-engineer <task>` — generate HTML/CSS prototypes
10. `/aiteam-backend-engineer <task>` — implement and test the backend
11. `/aiteam-frontend-engineer <task>` — implement and test the frontend

---

## Installation

### Quick install (no git clone required)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lvendrame/ai-dev-team/main/scripts/install.sh)
```

An interactive menu appears — select one or more AI tools. The script downloads the agent files from GitHub and installs them to the correct location automatically.

**Requirements:** `curl`, `bash` (pre-installed on macOS and most Linux distributions). `python3` is used when available to parse the GitHub API response; if absent, a `grep`-based fallback is used.

### Install from cloned repo

```bash
git clone https://github.com/lvendrame/ai-dev-team.git
cd ai-dev-team
./scripts/install.sh
```

When run from within the cloned repo, Claude Code skills are installed as **symlinks** — a `git pull` automatically updates the installed agents without re-running the installer.

### Installer options

| Option | Description |
|--------|-------------|
| `--project-path <path>` | Root of the target project for project-level installs (default: current directory) |
| `--force` | Overwrite existing files without prompting |

### Supported AI tools

| Tool | Install location | Format |
|------|-----------------|--------|
| Claude Code | `~/.claude/skills/<name>/` | Directory with `SKILL.md` |
| Cursor IDE | `.cursor/rules/<name>.mdc` | MDC file with Cursor frontmatter |
| GitHub Copilot | `.github/copilot-instructions.md` | Single Markdown file |
| OpenCode | `AGENTS.md` or `~/.config/opencode/AGENTS.md` | Single Markdown file |
| Gemini CLI | `GEMINI.md` or `~/.gemini/GEMINI.md` | Single Markdown file |
| Codex CLI | `AGENTS.md` or `~/.codex/AGENTS.md` | Single Markdown file |

---

## License

MIT
