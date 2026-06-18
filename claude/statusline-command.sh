#!/usr/bin/env bash
# ~/.claude/statusline-command.sh
# Claude Code status line — directory · branch · model · context · rate limits · time
#
# Design: Rosé Pine–inspired palette, mini fill-bars for budgets, ⎇ for branch.
# Separator: dim mid-dot (·) — subtle rhythm without visual noise.
# Dependency: jq + git on PATH (Windows: scoop install jq; Linux: apt install jq).

# Make jq + git findable when invoked non-interactively.
# Windows (Git Bash): prepend scoop shims + Git's bundled tools.
# Linux: prepend ~/.local/bin (where bootstrap drops the jq binary); the rest
# is already on the system PATH.
# $OSTYPE is a bash builtin — no subprocess, so this stays cheap per render.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    export PATH="$HOME/scoop/shims:/c/Program Files/Git/mingw64/bin:/c/Program Files/Git/usr/bin:/c/Program Files/Git/bin:$PATH"
else
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── Palette ───────────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

# Rosé Pine tones → nearest 256-color ANSI approximations
# Teal  (#9ccfd8) → 116   Muted rose (#ebbcba) → 217   Gold (#f6c177) → 222
# Iris  (#c4a7e7) → 183   Ghost dim  (#6e6a86) → 60
TEAL="\033[38;5;116m"
ROSE="\033[38;5;217m"
GOLD="\033[38;5;222m"
IRIS="\033[38;5;183m"
GHOST="\033[38;5;60m"

# Budget urgency colors — shared by context bar and rate-limit bars
BUDGET_OK="\033[38;5;108m"   # muted sage green — plenty of room
BUDGET_WARN="\033[38;5;179m" # amber             — getting close
BUDGET_CRIT="\033[38;5;167m" # muted red         — nearly full

# Separator: dim mid-dot with breathing room
SEP=$(printf "${GHOST}  ·  ${RESET}")

# ── Read stdin once ───────────────────────────────────────────────────────────
input=$(cat)

# ── Parse JSON ────────────────────────────────────────────────────────────────
raw_dir=$(echo "$input"   | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input"     | jq -r '.model.display_name // .model.id // ""')

# Context: prefer used_percentage, fall back to (100 - remaining_percentage)
ctx_used=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')
if [ -z "$ctx_used" ]; then
    rem=$(echo "$input"   | jq -r '.context_window.remaining_percentage // empty')
    [ -n "$rem" ] && ctx_used=$(( 100 - ${rem%%.*} ))
fi

five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')

# ── Directory: normalize slashes, collapse $HOME → ~, shorten if deep ─────────
# Windows JSON sends paths like "C:/Users/...", Git Bash $HOME is "/c/Users/...".
# Try both prefix forms so collapse works regardless of which Claude Code sends.
home_winstyle=$(echo "${USERPROFILE:-$HOME}" | sed 's|\\|/|g')
home_unixstyle=$(echo "$HOME" | sed 's|\\|/|g')
dir=$(echo "$raw_dir" | sed 's|\\|/|g' \
                      | sed "s|^${home_winstyle}|~|" \
                      | sed "s|^${home_unixstyle}|~|")

IFS='/' read -ra parts <<< "$dir"
if [ "${#parts[@]}" -gt 4 ]; then
    dir="${parts[0]}/.../${parts[-2]}/${parts[-1]}"
fi

# ── Git: branch + dirty marker ────────────────────────────────────────────────
git_dir=$(echo "$raw_dir" | sed 's|\\|/|g')
branch=$(git --no-optional-locks -C "$git_dir" branch --show-current 2>/dev/null)
dirty=""
if [ -n "$branch" ]; then
    if ! git --no-optional-locks -C "$git_dir" diff --quiet 2>/dev/null \
       || ! git --no-optional-locks -C "$git_dir" diff --quiet --cached 2>/dev/null; then
        dirty=" *"
    fi
fi

# ── Time ──────────────────────────────────────────────────────────────────────
time_now=$(date +%H:%M)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Pick urgency color from a 0-100 used percentage
budget_color() {
    local used=$1
    if   [ "$used" -lt 60 ]; then printf "%s" "$BUDGET_OK"
    elif [ "$used" -lt 85 ]; then printf "%s" "$BUDGET_WARN"
    else                          printf "%s" "$BUDGET_CRIT"
    fi
}

# 8-step vertical eighth-block — single char, scales with usage
mini_block() {
    local pct=$1
    local idx=$(( pct * 8 / 100 ))
    [ "$idx" -gt 8 ] && idx=8
    case "$idx" in
        0|1) printf "▁" ;;
        2)   printf "▂" ;;
        3)   printf "▃" ;;
        4)   printf "▄" ;;
        5)   printf "▅" ;;
        6)   printf "▆" ;;
        7)   printf "▇" ;;
        *)   printf "█" ;;
    esac
}

# Render "label ▅ 50%" with dim label and colored bar+percent
render_mini() {
    local label=$1
    local pct=$2
    [ -z "$pct" ] && return
    local used=${pct%%.*}
    local color
    color=$(budget_color "$used")
    local glyph
    glyph=$(mini_block "$used")
    printf "${DIM}%s${RESET} ${color}%s %s%%${RESET}" "$label" "$glyph" "$used"
}

# ── Context bar: 8-block fill ─────────────────────────────────────────────────
ctx_segment=""
if [ -n "$ctx_used" ]; then
    used=${ctx_used%%.*}
    [ "$used" -gt 100 ] && used=100
    filled=$(( used * 8 / 100 ))
    [ "$filled" -gt 8 ] && filled=8
    empty=$(( 8 - filled ))
    bar=""
    i=0; while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
    i=0; while [ $i -lt $empty  ]; do bar="${bar}░"; i=$(( i + 1 )); done
    bar_color=$(budget_color "$used")
    ctx_segment=$(printf "${bar_color}${bar}  %s%%${RESET}" "$used")
fi

# ── Assemble ──────────────────────────────────────────────────────────────────
out=""

# Directory — teal, bold: the anchor of the line
out+=$(printf "${TEAL}${BOLD}%s${RESET}" "$dir")

# Branch + dirty mark — rose, with gold * when uncommitted
if [ -n "$branch" ]; then
    out+="${SEP}"
    out+=$(printf "${ROSE}⎇  %s${GOLD}%s${RESET}" "$branch" "$dirty")
fi

# Model — iris, dim weight to recede behind the data
if [ -n "$model" ]; then
    out+="${SEP}"
    out+=$(printf "${DIM}${IRIS}%s${RESET}" "$model")
fi

# Context fill bar
if [ -n "$ctx_segment" ]; then
    out+="${SEP}"
    out+="$ctx_segment"
fi

# Rate limits: 5h and 7d, grouped with two-space gap (one major sep wraps them)
rate=""
if [ -n "$five_pct" ]; then
    rate+=$(render_mini "5h" "$five_pct")
fi
if [ -n "$week_pct" ]; then
    [ -n "$rate" ] && rate+="  "
    rate+=$(render_mini "7d" "$week_pct")
fi
if [ -n "$rate" ]; then
    out+="${SEP}"
    out+="$rate"
fi

# Time — ghost tone: present but not competing
out+="${SEP}"
out+=$(printf "${GHOST}%s${RESET}" "$time_now")

printf "%b\n" "$out"
