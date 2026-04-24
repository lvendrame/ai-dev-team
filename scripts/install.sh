#!/usr/bin/env bash
# AI Dev Team — Skill Installer
# https://github.com/lvendrame/ai-dev-team
#
# Usage: ./scripts/install.sh [--project-path <path>] [--force]
#   --project-path  Root of the target project for project-level installs (default: $PWD)
#   --force         Overwrite existing files without prompting
#
# Can also be run without cloning the repo:
#   bash <(curl -fsSL https://raw.githubusercontent.com/lvendrame/ai-dev-team/main/scripts/install.sh)

set -euo pipefail

REPO_OWNER="lvendrame"
REPO_NAME="ai-dev-team"
REPO_BRANCH="main"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
API_BASE="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents"
GENERATED_DATE="$(date '+%Y-%m-%d')"

# ── Mode detection: local (cloned repo) vs remote (curl) ─────────────────────
# When run via bash <(curl ...), $0 is /dev/fd/N — dirname gives /dev/fd.
# In that case LOCAL_SKILLS_DIR won't be a real skills directory.
_SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
LOCAL_SKILLS_DIR="${_SCRIPT_DIR}/../skills"

if [ -d "$LOCAL_SKILLS_DIR" ] && [ -n "$(ls -A "$LOCAL_SKILLS_DIR" 2>/dev/null)" ]; then
  LOCAL_MODE=1
  SKILLS_DIR="$(cd "$LOCAL_SKILLS_DIR" && pwd)"
else
  LOCAL_MODE=0
  _TMP_ROOT="$(mktemp -d)"
  SKILLS_DIR="${_TMP_ROOT}/skills"
  trap 'rm -rf "$_TMP_ROOT"' EXIT
fi

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${RESET} %s\n" "$*"; }
err()  { printf "  ${RED}✗${RESET} %s\n" "$*"; }
info() { printf "  ${CYAN}→${RESET} %s\n" "$*"; }

# ── Arg parsing ───────────────────────────────────────────────────────────────
PROJECT_PATH="$PWD"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-path) PROJECT_PATH="$2"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    -h|--help)
      printf "Usage: %s [--project-path <path>] [--force]\n" "$0"
      exit 0 ;;
    *) printf "Unknown option: %s\n" "$1"; exit 1 ;;
  esac
done

# ── Remote skill fetcher ──────────────────────────────────────────────────────
fetch_skills_from_github() {
  printf "${BOLD}Fetching skills from GitHub...${RESET}\n"

  if ! command -v curl > /dev/null 2>&1; then
    printf "${RED}Error:${RESET} curl is required but not installed.\n"
    exit 1
  fi

  local listing
  listing="$(curl -fsSL "${API_BASE}/skills")" || {
    printf "${RED}Error:${RESET} Could not reach GitHub API. Check your internet connection.\n"
    exit 1
  }

  local skill_names
  if command -v python3 > /dev/null 2>&1; then
    skill_names="$(printf '%s' "$listing" | python3 -c "
import sys, json
for item in json.load(sys.stdin):
    if item.get('type') == 'dir':
        print(item['name'])
")"
  else
    # Fallback: extract names from the JSON without jq/python
    skill_names="$(printf '%s' "$listing" | \
      grep '"name"' | grep -v '"type"' | \
      sed 's/.*"name": *"//;s/".*//' | \
      grep '^aiteam-')"
  fi

  if [ -z "${skill_names:-}" ]; then
    printf "${RED}Error:${RESET} No skills found in the repository. The repo may be private or the API rate limit reached.\n"
    exit 1
  fi

  mkdir -p "$SKILLS_DIR"
  for name in $skill_names; do
    mkdir -p "$SKILLS_DIR/$name"
    if curl -fsSL "${RAW_BASE}/skills/${name}/SKILL.md" \
         -o "$SKILLS_DIR/$name/SKILL.md" 2>/dev/null; then
      ok "Downloaded $name"
    else
      warn "Could not download $name — skipped"
      rm -rf "$SKILLS_DIR/$name"
    fi
  done
  printf "\n"
}

# Download skills if not running from local repo
[ "$LOCAL_MODE" -eq 0 ] && fetch_skills_from_github

# ── SKILL.md parsing helpers ──────────────────────────────────────────────────

get_frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="${field}:" '
    /^---/ { if (++c == 2) exit; next }
    c == 1 && index($0, f) == 1 {
      sub(/^[^:]+:[[:space:]]*/, ""); print; exit
    }
  ' "$file"
}

get_body() {
  local file="$1"
  awk '/^---/ { if (++c == 2) { found=1; next } } found { print }' "$file"
}

# List all skill directories (sorted)
list_skills() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort
}

skill_count() {
  list_skills | wc -l | tr -d ' '
}

skill_names() {
  list_skills | while IFS= read -r d; do basename "$d"; done | paste -sd ', '
}

# ── Overwrite guard ───────────────────────────────────────────────────────────
should_overwrite() {
  local path="$1"
  if [ ! -e "$path" ]; then return 0; fi
  if [ "$FORCE" -eq 1 ]; then return 0; fi
  printf "  ${YELLOW}?${RESET} '%s' already exists. Overwrite? [y/N] " "$path"
  read -r ans
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── Install: Claude Code ──────────────────────────────────────────────────────
install_claude_code() {
  local target_dir="$HOME/.claude/skills"
  mkdir -p "$target_dir"
  printf "\n${BOLD}Claude Code${RESET} → %s\n" "$target_dir"

  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name
    name="$(basename "$skill_dir")"
    local target="$target_dir/$name"

    # In local mode, skip if the symlink already points to the right place
    if [ "$LOCAL_MODE" -eq 1 ] && [ -L "$target" ] && \
       [ "$(readlink "$target")" = "$skill_dir" ]; then
      ok "$name (symlink up to date)"
      installed=$((installed + 1))
      continue
    fi

    if should_overwrite "$target"; then
      rm -rf "$target"
      if [ "$LOCAL_MODE" -eq 1 ]; then
        # Symlink: updates propagate when the repo is pulled
        ln -s "$skill_dir" "$target"
        ok "$name → $target (symlink)"
      else
        # Copy: temp dir is cleaned up after the script exits
        mkdir -p "$target"
        cp "$skill_dir/SKILL.md" "$target/SKILL.md"
        ok "$name → $target (copy)"
      fi
      installed=$((installed + 1))
    else
      warn "$name skipped"
      skipped=$((skipped + 1))
    fi
  done < <(list_skills)

  info "$installed installed, $skipped skipped"
}

# ── Install: Cursor ───────────────────────────────────────────────────────────
install_cursor() {
  local project_path="$1"
  local rules_dir="$project_path/.cursor/rules"
  mkdir -p "$rules_dir"
  printf "\n${BOLD}Cursor IDE${RESET} → %s\n" "$rules_dir"

  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name
    name="$(basename "$skill_dir")"
    local skill_file="$skill_dir/SKILL.md"
    local out="$rules_dir/$name.mdc"

    if ! should_overwrite "$out"; then
      warn "$name.mdc skipped"
      skipped=$((skipped + 1))
      continue
    fi

    local description
    description="$(get_frontmatter_field "$skill_file" "description")"
    local body
    body="$(get_body "$skill_file")"

    printf -- '---\ndescription: %s\nglobs: \nalwaysApply: false\n---\n\n%s\n' \
      "$description" "$body" > "$out"

    ok "$name → $out"
    installed=$((installed + 1))
  done < <(list_skills)

  info "$installed installed, $skipped skipped"
}

# ── Generate combined single-file (Copilot / OpenCode / Gemini / Codex) ───────
generate_combined_file() {
  local out="$1" tool_label="$2"
  local dir
  dir="$(dirname "$out")"
  mkdir -p "$dir"

  if ! should_overwrite "$out"; then
    warn "$(basename "$out") skipped"
    return
  fi

  {
    printf '<!-- Generated by AI Dev Team installer — %s -->\n' "$REPO_URL"
    printf '<!-- Tool: %s | Generated: %s -->\n\n' "$tool_label" "$GENERATED_DATE"
    printf '# AI Dev Team Agents\n\n'
    printf 'This project uses the following AI dev team personas.\n'
    printf 'Each section describes one agent — invoke it by name when working with a compatible AI tool.\n\n'
    printf -- '---\n\n'

    while IFS= read -r skill_dir; do
      local name
      name="$(basename "$skill_dir")"
      local skill_file="$skill_dir/SKILL.md"
      local description
      description="$(get_frontmatter_field "$skill_file" "description")"
      local body
      body="$(get_body "$skill_file")"

      printf '## %s\n\n' "$name"
      printf '> %s\n\n' "$description"
      printf '%s\n\n' "$body"
      printf -- '---\n\n'
    done < <(list_skills)
  } > "$out"

  ok "$(skill_count) skills → $out"
}

# ── Install: GitHub Copilot ───────────────────────────────────────────────────
install_copilot() {
  local project_path="$1"
  printf "\n${BOLD}GitHub Copilot${RESET} → %s/.github/copilot-instructions.md\n" "$project_path"
  generate_combined_file "$project_path/.github/copilot-instructions.md" "GitHub Copilot"
}

# ── Install: OpenCode ─────────────────────────────────────────────────────────
install_opencode() {
  local scope="$1" project_path="$2"
  printf "\n${BOLD}OpenCode${RESET}\n"
  if [ "$scope" = "user" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$HOME/.config/opencode/AGENTS.md" "OpenCode"
  fi
  if [ "$scope" = "project" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$project_path/AGENTS.md" "OpenCode"
  fi
}

# ── Install: Gemini CLI ───────────────────────────────────────────────────────
install_gemini() {
  local scope="$1" project_path="$2"
  printf "\n${BOLD}Gemini CLI${RESET}\n"
  if [ "$scope" = "user" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$HOME/.gemini/GEMINI.md" "Gemini CLI"
  fi
  if [ "$scope" = "project" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$project_path/GEMINI.md" "Gemini CLI"
  fi
}

# ── Install: Codex CLI ────────────────────────────────────────────────────────
install_codex() {
  local scope="$1" project_path="$2"
  printf "\n${BOLD}Codex CLI${RESET}\n"
  if [ "$scope" = "user" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$HOME/.codex/AGENTS.md" "Codex CLI"
  fi
  if [ "$scope" = "project" ] || [ "$scope" = "both" ]; then
    generate_combined_file "$project_path/AGENTS.md" "Codex CLI"
  fi
}

# ── Scope sub-menu (user / project / both) ────────────────────────────────────
ask_scope() {
  local tool_name="$1" user_path="$2" project_path="$3"
  printf "\n  Install %s agents at:\n" "$tool_name"
  printf "    [1] User level   → %s\n" "$user_path"
  printf "    [2] Project      → %s\n" "$project_path"
  printf "    [b] Both\n"
  printf "  Selection [1]: "
  read -r scope_sel
  case "${scope_sel:-1}" in
    1)   echo "user" ;;
    2)   echo "project" ;;
    b|B) echo "both" ;;
    *)   echo "user" ;;
  esac
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main() {
  printf "\n${BOLD}AI Dev Team — Skill Installer${RESET}\n"
  printf "${DIM}%s${RESET}\n" "$REPO_URL"
  printf "════════════════════════════════════════\n\n"
  printf "%s skills found: %s\n\n" "$(skill_count)" "$(skill_names)"

  printf "${BOLD}Select AI tools to install skills for:${RESET}\n\n"
  printf "  [1] Claude Code       ${DIM}(user-level)   → ~/.claude/skills/${RESET}\n"
  printf "  [2] Cursor IDE        ${DIM}(project)      → .cursor/rules/*.mdc${RESET}\n"
  printf "  [3] GitHub Copilot    ${DIM}(project)      → .github/copilot-instructions.md${RESET}\n"
  printf "  [4] OpenCode          ${DIM}(user/project) → AGENTS.md${RESET}\n"
  printf "  [5] Gemini CLI        ${DIM}(user/project) → GEMINI.md${RESET}\n"
  printf "  [6] Codex CLI         ${DIM}(user/project) → AGENTS.md${RESET}\n"
  printf "  [a] All of the above\n\n"
  printf "Enter selection (e.g. 1,3 or a): "
  read -r raw_sel

  # Normalise selection
  if [ "${raw_sel:-}" = "a" ] || [ "${raw_sel:-}" = "A" ]; then
    selections="1 2 3 4 5 6"
  else
    selections="$(printf '%s' "$raw_sel" | tr ',' ' ')"
  fi

  # Determine if any project-level tools were selected
  need_project=0
  for s in $selections; do
    case "$s" in 2|3|4|5|6) need_project=1; break ;; esac
  done

  if [ "$need_project" -eq 1 ]; then
    printf "\nProject root path [%s]: " "$PROJECT_PATH"
    read -r user_path
    if [ -n "${user_path:-}" ]; then
      PROJECT_PATH="$user_path"
    fi
    if [ ! -d "$PROJECT_PATH" ]; then
      printf "${RED}Error:${RESET} Directory not found: %s\n" "$PROJECT_PATH"
      exit 1
    fi
    printf "Installing to project: %s\n" "$PROJECT_PATH"
  fi

  printf "\n"

  for s in $selections; do
    case "$s" in
      1) install_claude_code ;;
      2) install_cursor "$PROJECT_PATH" ;;
      3) install_copilot "$PROJECT_PATH" ;;
      4)
        scope="$(ask_scope "OpenCode" \
          "$HOME/.config/opencode/AGENTS.md" \
          "$PROJECT_PATH/AGENTS.md")"
        install_opencode "$scope" "$PROJECT_PATH"
        ;;
      5)
        scope="$(ask_scope "Gemini CLI" \
          "$HOME/.gemini/GEMINI.md" \
          "$PROJECT_PATH/GEMINI.md")"
        install_gemini "$scope" "$PROJECT_PATH"
        ;;
      6)
        scope="$(ask_scope "Codex CLI" \
          "$HOME/.codex/AGENTS.md" \
          "$PROJECT_PATH/AGENTS.md")"
        install_codex "$scope" "$PROJECT_PATH"
        ;;
      *) warn "Unknown selection '$s' — skipped" ;;
    esac
  done

  printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
}

main "$@"
