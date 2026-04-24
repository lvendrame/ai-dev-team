#!/usr/bin/env bash
# AI Dev Team — Skill Installer
# https://github.com/lvendrame/ai-dev-team
#
# Usage: ./scripts/install.sh [--project-path <path>] [--force]
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

# ── Mode detection ────────────────────────────────────────────────────────────
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
  BOLD='\033[1m' DIM='\033[2m' GREEN='\033[0;32m'
  YELLOW='\033[1;33m' RED='\033[0;31m' CYAN='\033[0;36m' RESET='\033[0m'
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

# ── Checkbox selector ─────────────────────────────────────────────────────────
# Usage: results=$(checkbox_select "Title" "item one" "item two" ...)
# Prints selected items to stdout, one per line. Renders UI on stderr.
checkbox_select() {
  local title="$1"; shift
  local -a items=("$@")
  local n="${#items[@]}"
  local -a sel
  local cur=0 i

  for ((i = 0; i < n; i++)); do sel[$i]=0; done

  # Non-interactive fallback: return all items
  if [ ! -t 2 ]; then
    for ((i = 0; i < n; i++)); do printf '%s\n' "${items[$i]}"; done
    return
  fi

  local saved_stty
  saved_stty=$(stty -g 2>/dev/null || echo '')
  stty raw -echo 2>/dev/null || true
  tput civis 2>/dev/null || true

  local nlines=$((n + 3))  # title + items + hint + blank line
  for ((i = 0; i < nlines; i++)); do printf '\n' >&2; done

  _render() {
    printf '\033[%dA\r' "$nlines" >&2
    printf '\033[K\033[1m%s\033[0m\n' "$title" >&2
    for ((i = 0; i < n; i++)); do
      local box pfx
      [ "${sel[$i]}" -eq 1 ] && box='[x]' || box='[ ]'
      [ "$i" -eq "$cur" ] && pfx='❯' || pfx=' '
      printf '\033[K  %s %s %s\n' "$pfx" "$box" "${items[$i]}" >&2
    done
    printf '\033[K\033[2m  ↑↓ move  ·  Space toggle  ·  a all  ·  Enter confirm\033[0m\n' >&2
    printf '\033[K\n' >&2
  }

  _render

  while true; do
    local ch seq
    IFS= read -r -s -n1 ch 2>/dev/null || true

    if [ "$ch" = $'\x1b' ]; then
      IFS= read -r -s -n2 seq 2>/dev/null || true
      case "$seq" in
        '[A'|'OA') [ "$cur" -gt 0 ] && cur=$((cur - 1)) ;;
        '[B'|'OB') [ "$cur" -lt $((n - 1)) ] && cur=$((cur + 1)) ;;
      esac
    elif [ "$ch" = ' ' ]; then
      [ "${sel[$cur]}" -eq 1 ] && sel[$cur]=0 || sel[$cur]=1
    elif [ "$ch" = 'a' ] || [ "$ch" = 'A' ]; then
      for ((i = 0; i < n; i++)); do sel[$i]=1; done
    elif [ -z "$ch" ] || [ "$ch" = $'\r' ] || [ "$ch" = $'\n' ]; then
      break
    fi
    _render
  done

  [ -n "$saved_stty" ] && stty "$saved_stty" 2>/dev/null || true
  tput cnorm 2>/dev/null || true

  for ((i = 0; i < n; i++)); do
    [ "${sel[$i]}" -eq 1 ] && printf '%s\n' "${items[$i]}"
  done
}

# ── Remote skill fetcher ──────────────────────────────────────────────────────
fetch_skills_from_github() {
  printf "${BOLD}Fetching skills from GitHub...${RESET}\n"

  command -v curl > /dev/null 2>&1 || { printf "${RED}Error:${RESET} curl is required.\n"; exit 1; }

  local listing
  listing="$(curl -fsSL "${API_BASE}/skills")" || {
    printf "${RED}Error:${RESET} Could not reach GitHub API.\n"; exit 1
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

  [ -z "${skill_names:-}" ] && { printf "${RED}Error:${RESET} No skills found.\n"; exit 1; }

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

# ── SKILL.md parsing ──────────────────────────────────────────────────────────
get_frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="${field}:" '
    /^---/ { if (++c == 2) exit; next }
    c == 1 && index($0, f) == 1 { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$file"
}

get_body() {
  awk '/^---/ { if (++c == 2) { found=1; next } } found { print }' "$1"
}

list_skills() { find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort; }
skill_count()  { list_skills | wc -l | tr -d ' '; }
skill_names()  { list_skills | while IFS= read -r d; do basename "$d"; done | paste -sd ',' | sed 's/,/, /g'; }

# ── Overwrite guard ───────────────────────────────────────────────────────────
should_overwrite() {
  [ ! -e "$1" ] && return 0
  [ "$FORCE" -eq 1 ] && return 0
  printf "  ${YELLOW}?${RESET} '%s' already exists. Overwrite? [y/N] " "$1"
  read -r ans
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── Generic directory installer ───────────────────────────────────────────────
install_to_dir() {
  local label="$1" target_dir="$2"
  mkdir -p "$target_dir"
  printf "\n  ${BOLD}%s${RESET} → %s\n" "$label" "$target_dir"

  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name target
    name="$(basename "$skill_dir")"
    target="$target_dir/$name"

    if [ "$LOCAL_MODE" -eq 1 ] && [ -L "$target" ] && [ "$(readlink "$target")" = "$skill_dir" ]; then
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
  local do_user="$1" do_project="$2" project_path="$3"
  printf "\n${BOLD}Claude Code${RESET}\n"
  [ "$do_user" -eq 1 ]    && install_to_dir "user-level"    "$HOME/.claude/skills"
  [ "$do_project" -eq 1 ] && install_to_dir "project-level" "$project_path/.claude/skills"
}

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
  local do_user="$1" do_project="$2" project_path="$3"
  printf "\n${BOLD}GitHub Copilot${RESET}\n"
  [ "$do_user" -eq 1 ]    && install_to_dir "user-level"    "$HOME/.copilot/skills"
  [ "$do_project" -eq 1 ] && install_to_dir "project-level" "$project_path/.github/skills"
}

install_opencode() {
  local do_user="$1" do_project="$2" project_path="$3"
  printf "\n${BOLD}OpenCode${RESET}\n"
  [ "$do_user" -eq 1 ]    && install_to_dir "user-level"    "$HOME/.config/opencode/skills"
  [ "$do_project" -eq 1 ] && install_to_dir "project-level" "$project_path/.opencode/skills"
}

install_gemini() {
  local do_user="$1" do_project="$2" project_path="$3"
  printf "\n${BOLD}Gemini CLI${RESET}\n"
  [ "$do_user" -eq 1 ]    && install_to_dir "user-level"    "$HOME/.gemini/skills"
  [ "$do_project" -eq 1 ] && install_to_dir "project-level" "$project_path/.gemini/skills"
}

install_codex() {
  local do_user="$1" do_project="$2" project_path="$3"
  printf "\n${BOLD}Codex CLI${RESET}\n"
  [ "$do_user" -eq 1 ]    && install_to_dir "user-level"    "$HOME/.agents/skills"
  [ "$do_project" -eq 1 ] && install_to_dir "project-level" "$project_path/.agents/skills"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  printf "\n${BOLD}AI Dev Team — Skill Installer${RESET}\n"
  printf "${DIM}%s${RESET}\n" "$REPO_URL"
  printf "════════════════════════════════════════\n\n"
  printf "%s skills found: %s\n\n" "$(skill_count)" "$(skill_names)"

  # Step 1: Scope
  local -a scope_sel=()
  while IFS= read -r line; do scope_sel+=("$line"); done < <(checkbox_select \
    "Installation scope" \
    "User-level  — install globally (available in all projects)" \
    "Project     — install into a specific project directory")

  local do_user=0 do_project=0
  for s in "${scope_sel[@]+"${scope_sel[@]}"}"; do
    case "$s" in
      User*)    do_user=1 ;;
      Project*) do_project=1 ;;
    esac
  done

  if [ "$do_user" -eq 0 ] && [ "$do_project" -eq 0 ]; then
    printf "${YELLOW}⚠${RESET} No scope selected — defaulting to user-level.\n"
    do_user=1
  fi

  # Step 2: Project path (only when needed)
  if [ "$do_project" -eq 1 ]; then
    printf "\nProject root path [%s]: " "$PROJECT_PATH"
    read -r _path_input
    [ -n "${_path_input:-}" ] && PROJECT_PATH="$_path_input"
    if [ ! -d "$PROJECT_PATH" ]; then
      printf "${RED}Error:${RESET} Directory not found: %s\n" "$PROJECT_PATH"
      exit 1
    fi
    printf "Installing to project: %s\n" "$PROJECT_PATH"
  fi

  # Step 3: Tool selection
  local -a tool_sel=()
  while IFS= read -r line; do tool_sel+=("$line"); done < <(checkbox_select \
    "Select AI tools" \
    "Claude Code    — ~/.claude/skills/  or  .claude/skills/" \
    "Cursor IDE     — .cursor/rules/*.mdc  (project only)" \
    "GitHub Copilot — ~/.copilot/skills/  or  .github/skills/" \
    "OpenCode       — ~/.config/opencode/skills/  or  .opencode/skills/" \
    "Gemini CLI     — ~/.gemini/skills/  or  .gemini/skills/" \
    "Codex CLI      — ~/.agents/skills/  or  .agents/skills/")

  if [ "${#tool_sel[@]}" -eq 0 ]; then
    printf "${YELLOW}⚠${RESET} No tools selected. Nothing to install.\n\n"
    exit 0
  fi

  printf "\n"

  for tool in "${tool_sel[@]}"; do
    case "$tool" in
      Claude*)  install_claude_code "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Cursor*)  install_cursor      "$PROJECT_PATH" ;;
      GitHub*)  install_copilot     "$do_user" "$do_project" "$PROJECT_PATH" ;;
      OpenCode*)install_opencode    "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Gemini*)  install_gemini      "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Codex*)   install_codex       "$do_user" "$do_project" "$PROJECT_PATH" ;;
    esac
  done

  printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
}

main "$@"
