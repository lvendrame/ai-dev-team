# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository contains Claude Code skills that act as dev-team personas (e.g., architect, frontend engineer, backend engineer, QA, DevOps). Each skill is a markdown file that, when invoked via the Skill tool, causes Claude to adopt that persona and assist with work relevant to that role.

## Repository Structure

Skills live in `skills/<name>/SKILL.md` at the project root — this directory is the deliverable. Supporting shell scripts go in `scripts/` (e.g., `install.sh` symlinks skills into `~/.agents/skills/` so Claude Code picks them up). Any shared prompts or persona definitions referenced across multiple skills should live in a dedicated `personas/` directory.

## Naming Convention

All skills in this repo are prefixed with `aiteam-` (e.g., `aiteam-product-owner`) to namespace them and avoid collisions with other installed skills. The directory name, `name` frontmatter field, and slash command must all match exactly.

## Skill File Conventions

Each skill lives in `skills/<name>/SKILL.md`. The file starts with a YAML frontmatter block followed by the prompt body:

```markdown
---
name: aiteam-<role>
description: <one-line description used by Claude to decide when to invoke this skill>
user-invocable: true
argument-hint: "[optional args]"
---

<prompt body>
```

- The `description` field is shown in `/help` and used by the model to auto-select skills — make it specific and action-oriented.
- Persona instructions in the body should define: role identity, decision-making style, what the persona produces, and what it defers to other personas.
- Structure the body with `##` phase headings and numbered steps. End each phase with an explicit instruction to wait for user input or proceed.

## Persona Design Principles

- Each persona should have a clear, non-overlapping responsibility boundary.
- Personas should explicitly name which other personas they hand off to (e.g., the architect defers implementation details to the backend or frontend persona).
- Output format expectations (e.g., "produce a design doc", "produce a PR description", "produce test cases") belong in the skill body, not in CLAUDE.md.
- Avoid duplicating guidance across persona files — shared context belongs in a common `personas/base.md` fragment that individual skills can reference.

## project-hub/ Artifacts

The `project-hub/` directory is the shared knowledge base written and read by skills at runtime (not committed to this repo — it lives in the target project). Key files:

| File | Written by | Read by | Purpose |
|------|-----------|---------|---------|
| `project-hub/Project.md` | `aiteam-project-manager` | All agents | Project charter: vision, goals, stakeholders, scope, team, constraints |
| `project-hub/architecture.md` | `aiteam-architect`, `aiteam-observability-engineer` | `aiteam-architect`, `aiteam-qa-engineer`, `aiteam-observability-engineer` | Architecture decisions, ADRs, and observability strategy |
| `project-hub/tasks/*.md` | `aiteam-product-owner` | `aiteam-architect`, `aiteam-qa-engineer`, `aiteam-uiux-engineer`, `aiteam-observability-engineer` | Individual feature tasks in user story format |
| `project-hub/design-system/` | `aiteam-uiux-engineer` | `aiteam-uiux-engineer` | CSS tokens, component library, HTML showcase, and written guide |
| `project-hub/prototypes/<task>/` | `aiteam-uiux-engineer` | — | HTML/CSS screen prototypes per task |
| `project-hub/tasks/*.md` (status) | `aiteam-backend-engineer` | — | Updates `## Implementation Status` and frontmatter when backend is done |

Recommended invocation order for a new project:
1. `aiteam-project-manager` — define the project charter
2. `aiteam-architect` — define system architecture
3. `aiteam-observability-engineer` — add observability strategy to architecture
4. `aiteam-uiux-engineer` — build the design system
5. `aiteam-product-owner` — write feature tasks
6. Per task: `aiteam-architect <task>` → `aiteam-qa-engineer <task>` → `aiteam-observability-engineer <task>` → `aiteam-backend-engineer <task>` → `aiteam-frontend-engineer <task>` → `aiteam-uiux-engineer <task>`

## Scripts

Shell scripts in `scripts/` automate skill installation, validation, or scaffolding. Convention:

- `scripts/install.sh` — symlinks or copies skill files to the active Claude config directory.
- `scripts/validate.sh` — checks that all skill files have required frontmatter fields.
- Scripts must be POSIX-compatible (no bash-isms unless the shebang explicitly invokes bash).
