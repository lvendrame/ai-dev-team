#!/usr/bin/env bash
# AI Dev Team — Skill Installer
# https://github.com/lvendrame/ai-dev-team
#
# Usage: ./scripts/install.sh [--project-path <path>] [--force]
#
# Run without cloning the repo:
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
      printf "Usage: %s [--project-path <path>] [--force]\n" "$0"; exit 0 ;;
    *) printf "Unknown option: %s\n" "$1"; exit 1 ;;
  esac
done

# ── Skill listing helpers ─────────────────────────────────────────────────────
list_skills()  { find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | sort; }
skill_count()  { list_skills | wc -l | tr -d ' '; }
skill_names()  {
  list_skills | while IFS= read -r d; do basename "$d"; done | \
    awk 'NR==1{r=$0;next}{r=r", "$0}END{if(r!="")print r}'
}

remote_skill_count() { printf '%s' "$REMOTE_SKILL_NAMES" | awk 'NF' | wc -l | tr -d ' '; }
remote_skill_names() {
  printf '%s' "$REMOTE_SKILL_NAMES" | awk 'NF' | \
    awk 'NR==1{r=$0;next}{r=r", "$0}END{print r}'
}

REMOTE_SKILL_NAMES=""

# ── GitHub helpers ────────────────────────────────────────────────────────────
_parse_dir_names() {
  if command -v python3 > /dev/null 2>&1; then
    python3 -c "
import sys, json
for item in json.load(sys.stdin):
    if item.get('type') == 'dir':
        print(item['name'])
"
  else
    grep '"name"' | grep -v '"type"' | sed 's/.*"name": *"//;s/".*//'
  fi
}

fetch_skill_listing() {
  printf "Connecting to GitHub..." >&2
  local listing
  listing="$(curl -fsSL "${API_BASE}/skills" 2>/dev/null)" || {
    printf "\r${RED}Error:${RESET} Could not reach GitHub API.\n"; exit 1
  }
  REMOTE_SKILL_NAMES="$(printf '%s' "$listing" | _parse_dir_names)"
  printf "\r\033[K"
}

fetch_skills_from_github() {
  printf "${BOLD}Downloading skill files...${RESET}\n"
  mkdir -p "$SKILLS_DIR"
  for name in $REMOTE_SKILL_NAMES; do
    mkdir -p "$SKILLS_DIR/$name"
    if curl -fsSL "${RAW_BASE}/skills/${name}/SKILL.md" \
         -o "$SKILLS_DIR/$name/SKILL.md" 2>/dev/null; then
      ok "$name"
    else
      warn "$name — download failed, skipped"
      rm -rf "$SKILLS_DIR/$name"
    fi
  done
  printf "\n"
}

# ── Checkbox selector ─────────────────────────────────────────────────────────
# Populates the global _CHECKBOX_RESULT array.
# Runs in the CURRENT shell (not a subshell) so the top-level Ctrl+C trap works.
#
# stty settings used:
#   -icanon   char-by-char input (no line buffering)
#   -echo     suppress input echo
#   min 1     read returns after ≥1 char is available  ← required for arrows
#   time 0    no timeout
#   (opost stays ON → \n translates to \r\n, cursor returns to col 0)
#   Do NOT use `stty raw`  — disables opost, breaks newline/cursor
#   Do NOT use `stty cbreak` — does not set min/time on all platforms
#
# Cursor strategy: tput sc/rc (save/restore) instead of counting lines.
# Line clearing: \r (col 0) + tput el (erase to end of line).
# Key reading: plain `read` without -s; stty -echo already suppresses echo.
#   `read -s` calls tcsetattr internally and can reset -icanon mid-sequence.
#
_CHECKBOX_RESULT=()
_SAVED_STTY=''

checkbox_select() {
  local title="$1"; shift
  local -a items=("$@")
  local n="${#items[@]}"
  local -a sel
  local cur=0 i

  for ((i = 0; i < n; i++)); do sel[$i]=0; done
  _CHECKBOX_RESULT=()

  if [ ! -t 2 ]; then
    _CHECKBOX_RESULT=("${items[@]}")
    return
  fi

  _SAVED_STTY=$(stty -g 2>/dev/null || echo '')
  stty -icanon -echo min 1 time 0 isig 2>/dev/null || true
  tput civis 2>/dev/null || true

  local nlines=$((n + 2))  # title + items + hint

  # Reserve space then save cursor at the top of that area.
  # tput sc/rc (save/restore cursor) avoids line-counting — reliable even
  # when lines wrap.
  for ((i = 0; i < nlines; i++)); do printf '\n' >&2; done
  printf '\033[%dA\r' "$nlines" >&2
  tput sc >&2 2>/dev/null

  _render() {
    tput rc >&2 2>/dev/null        # restore to saved position
    printf '\r' >&2                # col 0
    tput el >&2 2>/dev/null        # erase to end of line
    printf '\033[1m%s\033[0m\n' "$title" >&2
    for ((i = 0; i < n; i++)); do
      local box pfx
      [ "${sel[$i]}" -eq 1 ] && box='[x]' || box='[ ]'
      [ "$i" -eq "$cur" ] && pfx='❯' || pfx=' '
      printf '\r' >&2; tput el >&2 2>/dev/null
      printf '  %s %s %s\n' "$pfx" "$box" "${items[$i]}" >&2
    done
    printf '\r' >&2; tput el >&2 2>/dev/null
    printf '\033[2m  ↑↓ move · Space toggle · a=all · Enter confirm\033[0m\n' >&2
  }

  _render

  while true; do
    local ch b1 b2
    IFS= read -r -n1 ch 2>/dev/null || true

    case "$ch" in
      $'\x1b')
        # -t 1 (integer) works on bash 3.2+; fractional -t 0.1 is bash 4+ only.
        # With min 1 time 0, [A/[B arrive immediately after ESC — no real wait.
        # A bare ESC waits up to 1 s then returns empty (b1='', b2='').
        IFS= read -r -n1 -t 1 b1 2>/dev/null || b1=''
        IFS= read -r -n1 -t 1 b2 2>/dev/null || b2=''
        case "${b1}${b2}" in
          '[A'|'OA') [ "$cur" -gt 0 ] && cur=$((cur - 1)) ;;
          '[B'|'OB') [ "$cur" -lt $((n - 1)) ] && cur=$((cur + 1)) ;;
        esac
        ;;
      ' ')
        [ "${sel[$cur]}" -eq 1 ] && sel[$cur]=0 || sel[$cur]=1
        ;;
      'a'|'A')
        for ((i = 0; i < n; i++)); do sel[$i]=1; done
        ;;
      ''|$'\r'|$'\n')
        break
        ;;
    esac
    _render
  done

  printf '\033[%dB\n' "$nlines" >&2
  [ -n "$_SAVED_STTY" ] && stty "$_SAVED_STTY" 2>/dev/null || true
  _SAVED_STTY=''
  tput cnorm 2>/dev/null || true

  for ((i = 0; i < n; i++)); do
    [ "${sel[$i]}" -eq 1 ] && _CHECKBOX_RESULT+=("${items[$i]}")
  done
}

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
      ok "$name (symlink up to date)"; installed=$((installed + 1)); continue
    fi

    if should_overwrite "$target"; then
      rm -rf "$target"
      if [ "$LOCAL_MODE" -eq 1 ]; then
        ln -s "$skill_dir" "$target"; ok "$name (symlink)"
      else
        cp -r "$skill_dir" "$target"; ok "$name (copy)"
      fi
      installed=$((installed + 1))
    else
      warn "$name skipped"; skipped=$((skipped + 1))
    fi
  done < <(list_skills)

  info "$installed installed, $skipped skipped"
}

# ── Tool installers ───────────────────────────────────────────────────────────
install_claude_code() {
  printf "\n${BOLD}Claude Code${RESET}\n"
  [ "$1" -eq 1 ] && install_to_dir "user-level"    "$HOME/.claude/skills"
  [ "$2" -eq 1 ] && install_to_dir "project-level" "$3/.claude/skills"
}

install_cursor() {
  local rules_dir="$1/.cursor/rules"
  mkdir -p "$rules_dir"
  printf "\n${BOLD}Cursor IDE${RESET} → %s\n" "$rules_dir"
  local installed=0 skipped=0
  while IFS= read -r skill_dir; do
    local name out description body
    name="$(basename "$skill_dir")"
    out="$rules_dir/$name.mdc"
    if ! should_overwrite "$out"; then warn "$name.mdc skipped"; skipped=$((skipped+1)); continue; fi
    description="$(awk -v f='description:' '/^---/{if(++c==2)exit;next} c==1&&index($0,f)==1{sub(/^[^:]+:[[:space:]]*/,"");print;exit}' "$skill_dir/SKILL.md")"
    body="$(awk '/^---/{if(++c==2){found=1;next}} found{print}' "$skill_dir/SKILL.md")"
    printf -- '---\ndescription: %s\nglobs: \nalwaysApply: false\n---\n\n%s\n' "$description" "$body" > "$out"
    ok "$name"; installed=$((installed+1))
  done < <(list_skills)
  info "$installed installed, $skipped skipped"
}

install_copilot() {
  printf "\n${BOLD}GitHub Copilot${RESET}\n"
  [ "$1" -eq 1 ] && install_to_dir "user-level"    "$HOME/.copilot/skills"
  [ "$2" -eq 1 ] && install_to_dir "project-level" "$3/.github/skills"
}

install_opencode() {
  printf "\n${BOLD}OpenCode${RESET}\n"
  [ "$1" -eq 1 ] && install_to_dir "user-level"    "$HOME/.config/opencode/skills"
  [ "$2" -eq 1 ] && install_to_dir "project-level" "$3/.opencode/skills"
}

install_gemini() {
  printf "\n${BOLD}Gemini CLI${RESET}\n"
  [ "$1" -eq 1 ] && install_to_dir "user-level"    "$HOME/.gemini/skills"
  [ "$2" -eq 1 ] && install_to_dir "project-level" "$3/.gemini/skills"
}

install_codex() {
  printf "\n${BOLD}Codex CLI${RESET}\n"
  [ "$1" -eq 1 ] && install_to_dir "user-level"    "$HOME/.agents/skills"
  [ "$2" -eq 1 ] && install_to_dir "project-level" "$3/.agents/skills"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  # Top-level Ctrl+C / kill handler.
  # Because checkbox_select runs in the CURRENT shell (not a subshell),
  # this single trap covers all interactive phases.
  _cleanup() {
    [ -n "${_SAVED_STTY:-}" ] && stty "$_SAVED_STTY" 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf '\n\n' >&2
    exit 130
  }
  trap '_cleanup' INT TERM

  # Fetch skill listing (names only, no downloads) for the header display
  if [ "$LOCAL_MODE" -eq 0 ]; then
    fetch_skill_listing
    _count="$(remote_skill_count)"
    _names="$(remote_skill_names)"
  else
    _count="$(skill_count)"
    _names="$(skill_names)"
  fi

  printf "\n${BOLD}AI Dev Team — Skill Installer${RESET}\n"
  printf "${DIM}%s${RESET}\n" "$REPO_URL"
  printf "════════════════════════════════════════\n"
  printf "%s skills: %s\n" "$_count" "$_names"

  # ── Step 1: Scope ───────────────────────────────────────────────────────────
  checkbox_select "Where to install:" \
    "User-level  — install globally (available in all projects)" \
    "Project     — install into a specific project directory"

  local do_user=0 do_project=0
  for s in "${_CHECKBOX_RESULT[@]+"${_CHECKBOX_RESULT[@]}"}"; do
    case "$s" in User*) do_user=1 ;; Project*) do_project=1 ;; esac
  done

  if [ "$do_user" -eq 0 ] && [ "$do_project" -eq 0 ]; then
    printf "${YELLOW}⚠${RESET}  No scope selected — defaulting to user-level.\n"
    do_user=1
  fi

  # ── Step 2: Project path (only if project scope selected) ───────────────────
  if [ "$do_project" -eq 1 ]; then
    printf "Project root path [%s]: " "$PROJECT_PATH"
    read -r _pi
    [ -n "${_pi:-}" ] && PROJECT_PATH="$_pi"
    if [ ! -d "$PROJECT_PATH" ]; then
      printf "${RED}Error:${RESET} Directory not found: %s\n" "$PROJECT_PATH"; exit 1
    fi
    printf "Project: %s\n" "$PROJECT_PATH"
  fi

  # ── Step 3: Tool selection ───────────────────────────────────────────────────
  checkbox_select "Select AI tools:" \
    "Claude Code     ~/.claude/skills/" \
    "Cursor IDE      .cursor/rules/*.mdc  (project only)" \
    "GitHub Copilot  ~/.copilot/skills/" \
    "OpenCode        ~/.config/opencode/skills/" \
    "Gemini CLI      ~/.gemini/skills/" \
    "Codex CLI       ~/.agents/skills/"

  if [ "${#_CHECKBOX_RESULT[@]}" -eq 0 ]; then
    printf "${YELLOW}⚠${RESET}  No tools selected. Nothing to install.\n\n"; exit 0
  fi

  # ── Download skill files now (remote mode only) ─────────────────────────────
  if [ "$LOCAL_MODE" -eq 0 ]; then
    fetch_skills_from_github
  fi

  printf "\n"

  # ── Install ──────────────────────────────────────────────────────────────────
  for tool in "${_CHECKBOX_RESULT[@]}"; do
    case "$tool" in
      Claude*)  install_claude_code "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Cursor*)  install_cursor      "$PROJECT_PATH" ;;
      GitHub*)  install_copilot     "$do_user" "$do_project" "$PROJECT_PATH" ;;
      OpenCode*)install_opencode    "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Gemini*)  install_gemini      "$do_user" "$do_project" "$PROJECT_PATH" ;;
      Codex*)   install_codex       "$do_user" "$do_project" "$PROJECT_PATH" ;;
    esac
  done

  trap - INT TERM
  printf "\n${GREEN}${BOLD}Done.${RESET}\n\n"
}

main "$@"
