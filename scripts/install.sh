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

# ── Mode detection: local (cloned repo) vs remote (curl) ─────────────────────
# When run via bash <(curl ...), $0 is /dev/fd/N — dirname gives /dev/fd.
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
    printf "${RED}Error:${RESET} curl is required but not installed.\n"; exit 1
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
    skill_names="$(printf '%s' "$listing" | \
      grep '"name"' | grep -v '"type"' | \
      sed 's/.*"name": *"//;s/".*//' | grep '^aiteam-')"
  fi

  if [ -z "${skill_names:-}" ]; then
    printf "${RED}Error:${RESET} No skills found in the repository.\n"; exit 1
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
  awk '/^---/ { if (++c == 2) { found=1; next } } found { print }' "$1"
}

list_skills() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort
}

skill_count() {
  list_skills | wc -l | tr -d ' '
}

skill_names() {
  # Use single-char delimiter for BSD paste (macOS), then add spaces with sed
  list_skills | while IFS= read -r d; do basename "$d"; done | paste -sd ',' | sed 's/,/, /g'
}

# ── Overwrite guard ───────────────────────────────────────────────────────────
should_overwrite() {
  local path="$1"
  [ ! -e "$path" ] && return 0
  [ "$FORCE" -eq 1 ] && return 0
  printf "  ${YELLOW}?${RESET} '%s' already exists. Overwrite? [y/N] " "$path"
  read -r ans
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── Scope menu ────────────────────────────────────────────────────────────────
# Prompts go to stderr so they remain visible when the result is captured via $()
ask_scope() {
  local tool_name="$1" user_path="$2" project_path="$3"
  printf "\n  Install %s skills at:\n" "$tool_name" >&2
  printf "    [1] User level  → %s\n" "$user_path" >&2
  printf "    [2] Project     → %s\n" "$project_path" >&2
  printf "    [b] Both\n" >&2
  printf "  Selection [1]: " >&2
  read -r scope_sel
  case "${scope_sel:-1}" in
    1)   echo "user" ;;
    2)   echo "project" ;;
    b|B) echo "both" ;;
    *)   echo "user" ;;
  esac
}

# ── Generic installer: copy/symlink skill dirs into a target directory ─────────
install_to_dir() {
  local label="$1" target_dir="$2"
  mkdir -p "$target_dir"
  printf "\n  ${BOLD}%s${RESET} → %s\n" "$label" "$target_dir"

  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name target
    name="$(basename "$skill_dir")"
    target="$target_dir/$name"

    # Local mode: skip if symlink already points to the right place
    if [ "$LOCAL_MODE" -eq 1 ] && [ -L "$target" ] && \
       [ "$(readlink "$target")" = "$skill_dir" ]; then
      ok "$name (symlink up to date)"
      installed=$((installed + 1))
      continue
    fi

    if should_overwrite "$target"; then
      rm -rf "$target"
      if [ "$LOCAL_MODE" -eq 1 ]; then
        ln -s "$skill_dir" "$target"
        ok "$name → $target (symlink)"
      else
        cp -r "$skill_dir" "$target"
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

# ── Tool installers ───────────────────────────────────────────────────────────

install_claude_code() {
  local project_path="$1" scope
  scope="$(ask_scope "Claude Code" \
    "$HOME/.claude/skills" "$project_path/.claude/skills")"
  printf "\n${BOLD}Claude Code${RESET}\n"
  { [ "$scope" = "user" ]    || [ "$scope" = "both" ]; } && \
    install_to_dir "user-level"    "$HOME/.claude/skills"
  { [ "$scope" = "project" ] || [ "$scope" = "both" ]; } && \
    install_to_dir "project-level" "$project_path/.claude/skills"
}

# Cursor is project-only; skills become individual .mdc files
install_cursor() {
  local project_path="$1"
  local rules_dir="$project_path/.cursor/rules"
  mkdir -p "$rules_dir"
  printf "\n${BOLD}Cursor IDE${RESET} → %s\n" "$rules_dir"

  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name out description body
    name="$(basename "$skill_dir")"
    out="$rules_dir/$name.mdc"

    if ! should_overwrite "$out"; then
      warn "$name.mdc skipped"; skipped=$((skipped + 1)); continue
    fi

    description="$(get_frontmatter_field "$skill_dir/SKILL.md" "description")"
    body="$(get_body "$skill_dir/SKILL.md")"

    printf -- '---\ndescription: %s\nglobs: \nalwaysApply: false\n---\n\n%s\n' \
      "$description" "$body" > "$out"

    ok "$name → $out"
    installed=$((installed + 1))
  done < <(list_skills)

  info "$installed installed, $skipped skipped"
}

install_copilot() {
  local project_path="$1" scope
  scope="$(ask_scope "GitHub Copilot" \
    "$HOME/.copilot/skills" "$project_path/.github/skills")"
  printf "\n${BOLD}GitHub Copilot${RESET}\n"
  { [ "$scope" = "user" ]    || [ "$scope" = "both" ]; } && \
    install_to_dir "user-level"    "$HOME/.copilot/skills"
  { [ "$scope" = "project" ] || [ "$scope" = "both" ]; } && \
    install_to_dir "project-level" "$project_path/.github/skills"
}

install_opencode() {
  local project_path="$1" scope
  scope="$(ask_scope "OpenCode" \
    "$HOME/.config/opencode/skills" "$project_path/.opencode/skills")"
  printf "\n${BOLD}OpenCode${RESET}\n"
  { [ "$scope" = "user" ]    || [ "$scope" = "both" ]; } && \
    install_to_dir "user-level"    "$HOME/.config/opencode/skills"
  { [ "$scope" = "project" ] || [ "$scope" = "both" ]; } && \
    install_to_dir "project-level" "$project_path/.opencode/skills"
}

install_gemini() {
  local project_path="$1" scope
  scope="$(ask_scope "Gemini CLI" \
    "$HOME/.gemini/skills" "$project_path/.gemini/skills")"
  printf "\n${BOLD}Gemini CLI${RESET}\n"
  { [ "$scope" = "user" ]    || [ "$scope" = "both" ]; } && \
    install_to_dir "user-level"    "$HOME/.gemini/skills"
  { [ "$scope" = "project" ] || [ "$scope" = "both" ]; } && \
    install_to_dir "project-level" "$project_path/.gemini/skills"
}

install_codex() {
  local project_path="$1" scope
  scope="$(ask_scope "Codex CLI" \
    "$HOME/.agents/skills" "$project_path/.agents/skills")"
  printf "\n${BOLD}Codex CLI${RESET}\n"
  { [ "$scope" = "user" ]    || [ "$scope" = "both" ]; } && \
    install_to_dir "user-level"    "$HOME/.agents/skills"
  { [ "$scope" = "project" ] || [ "$scope" = "both" ]; } && \
    install_to_dir "project-level" "$project_path/.agents/skills"
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main() {
  printf "\n${BOLD}AI Dev Team — Skill Installer${RESET}\n"
  printf "${DIM}%s${RESET}\n" "$REPO_URL"
  printf "════════════════════════════════════════\n\n"
  printf "%s skills found: %s\n\n" "$(skill_count)" "$(skill_names)"

  printf "${BOLD}Select AI tools to install skills for:${RESET}\n\n"
  printf "  [1] Claude Code    ${DIM}(user/project) → ~/.claude/skills/  or  .claude/skills/${RESET}\n"
  printf "  [2] Cursor IDE     ${DIM}(project)      → .cursor/rules/*.mdc${RESET}\n"
  printf "  [3] GitHub Copilot ${DIM}(user/project) → ~/.copilot/skills/ or  .github/skills/${RESET}\n"
  printf "  [4] OpenCode       ${DIM}(user/project) → ~/.config/opencode/skills/ or .opencode/skills/${RESET}\n"
  printf "  [5] Gemini CLI     ${DIM}(user/project) → ~/.gemini/skills/  or  .gemini/skills/${RESET}\n"
  printf "  [6] Codex CLI      ${DIM}(user/project) → ~/.agents/skills/  or  .agents/skills/${RESET}\n"
  printf "  [a] All of the above\n\n"
  printf "Enter selection (e.g. 1,3 or a): "
  read -r raw_sel

  if [ "${raw_sel:-}" = "a" ] || [ "${raw_sel:-}" = "A" ]; then
    selections="1 2 3 4 5 6"
  else
    selections="$(printf '%s' "$raw_sel" | tr ',' ' ')"
  fi

  # All tools support at least project scope, so always ask for project path
  printf "\nProject root path [%s]: " "$PROJECT_PATH"
  read -r user_path_input
  if [ -n "${user_path_input:-}" ]; then
    PROJECT_PATH="$user_path_input"
  fi
  if [ ! -d "$PROJECT_PATH" ]; then
    printf "${RED}Error:${RESET} Directory not found: %s\n" "$PROJECT_PATH"
    exit 1
  fi

  printf "\n"

  for s in $selections; do
    case "$s" in
      1) install_claude_code "$PROJECT_PATH" ;;
      2) install_cursor      "$PROJECT_PATH" ;;
      3) install_copilot     "$PROJECT_PATH" ;;
      4) install_opencode    "$PROJECT_PATH" ;;
      5) install_gemini      "$PROJECT_PATH" ;;
      6) install_codex       "$PROJECT_PATH" ;;
      *) warn "Unknown selection '$s' — skipped" ;;
    esac
  done

  printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
}

main "$@"
