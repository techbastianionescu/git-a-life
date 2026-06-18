#!/usr/bin/env bash
# Bootstrap git-a-life on a machine.
# Run from the repo root:  ./bootstrap.sh
#
# 1. Copies config files from this repo into the locations the tools expect.
# 2. Installs the prompt prerequisites (oh-my-posh, jq, Nerd Font) if missing.
#
# Idempotent — safe to re-run. Existing files are backed up with a timestamp;
# prerequisites already present are left untouched. No elevation needed: on
# Linux everything lands in ~/.local (user space); on Windows it uses scoop.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/lib/common.sh"   # provides OS, ARCH, download()

CLAUDE_HOME="$HOME/.claude"
POSH_THEMES_DIR="$HOME/.poshthemes"
LOCAL_BIN="$HOME/.local/bin"           # where Linux static binaries land

echo "[bootstrap] Source: $REPO_DIR"
echo "[bootstrap] Targets: $CLAUDE_HOME, $POSH_THEMES_DIR, $HOME"
echo

mkdir -p "$CLAUDE_HOME/skills/doc"
mkdir -p "$POSH_THEMES_DIR"

# ── File install helpers ─────────────────────
backup_if_exists() {
    local target="$1"
    if [ -f "$target" ]; then
        local backup="${target}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$target" "$backup"
        echo "[bootstrap]   backed up existing -> $(basename "$backup")"
    fi
}

install_file() {
    local src="$1"
    local dst="$2"
    if [ ! -f "$src" ]; then
        echo "[bootstrap] SKIP (missing source): $src"
        return
    fi
    # True idempotency: identical file -> no copy, no backup litter.
    if cmp -s "$src" "$dst"; then
        echo "[bootstrap] unchanged: $dst"
        return
    fi
    backup_if_exists "$dst"
    cp "$src" "$dst"
    echo "[bootstrap] installed: $dst"
}

# ── Claude Code ──────────────────────────────
install_file "$REPO_DIR/claude/CLAUDE.md"             "$CLAUDE_HOME/CLAUDE.md"
install_file "$REPO_DIR/claude/settings.json"         "$CLAUDE_HOME/settings.json"
install_file "$REPO_DIR/claude/statusline-command.sh" "$CLAUDE_HOME/statusline-command.sh"
install_file "$REPO_DIR/claude/skills/doc/SKILL.md"   "$CLAUDE_HOME/skills/doc/SKILL.md"

# ── Shell ────────────────────────────────────
install_file "$REPO_DIR/shell/.bashrc"                "$HOME/.bashrc"
# .minttyrc configures the Git Bash (mintty) window — Windows only.
if [ "$OS" = "windows" ]; then
    install_file "$REPO_DIR/shell/.minttyrc"          "$HOME/.minttyrc"
fi

# ── Oh My Posh (custom theme) ────────────────
install_file "$REPO_DIR/oh-my-posh/themes/night-owl.omp.json" \
             "$POSH_THEMES_DIR/night-owl.omp.json"

# ── Prerequisite installs ────────────────────
# Strategy per tool: present -> skip; missing -> install; install fails -> warn
# with the manual command. Windows installs via scoop; Linux pulls static
# binaries into ~/.local/bin so nothing needs root or extra package deps.

ensure_oh_my_posh() {
    if command -v oh-my-posh >/dev/null 2>&1; then
        echo "[prereq] oh-my-posh  ✓ already present"
        return
    fi
    if [ "$OS" = "windows" ]; then
        if command -v scoop >/dev/null 2>&1; then
            scoop install oh-my-posh >/dev/null 2>&1 \
                && echo "[prereq] oh-my-posh  ↓ installed (scoop)" \
                || echo "[prereq] oh-my-posh  ⚠ install failed — run: scoop install oh-my-posh"
        else
            echo "[prereq] oh-my-posh  ⚠ needs scoop first, then: scoop install oh-my-posh"
        fi
        return
    fi
    mkdir -p "$LOCAL_BIN"
    if download "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-$ARCH" "$LOCAL_BIN/oh-my-posh"; then
        chmod +x "$LOCAL_BIN/oh-my-posh"
        echo "[prereq] oh-my-posh  ↓ installed (~/.local/bin)"
    else
        echo "[prereq] oh-my-posh  ⚠ download failed — get posh-linux-$ARCH into ~/.local/bin"
    fi
}

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        echo "[prereq] jq          ✓ already present"
        return
    fi
    if [ "$OS" = "windows" ]; then
        if command -v scoop >/dev/null 2>&1; then
            scoop install jq >/dev/null 2>&1 \
                && echo "[prereq] jq          ↓ installed (scoop)" \
                || echo "[prereq] jq          ⚠ install failed — run: scoop install jq"
        else
            echo "[prereq] jq          ⚠ needs scoop first, then: scoop install jq"
        fi
        return
    fi
    mkdir -p "$LOCAL_BIN"
    if download "https://github.com/jqlang/jq/releases/latest/download/jq-linux-$ARCH" "$LOCAL_BIN/jq"; then
        chmod +x "$LOCAL_BIN/jq"
        echo "[prereq] jq          ↓ installed (~/.local/bin)"
    else
        echo "[prereq] jq          ⚠ download failed — get jq-linux-$ARCH into ~/.local/bin"
    fi
}

# True/false: is a JetBrainsMono Nerd Font already present? Lookup is per-OS.
font_installed() {
    if [ "$OS" = "windows" ]; then
        for font_dir in "$HOME/AppData/Local/Microsoft/Windows/Fonts" "/c/Windows/Fonts"; do
            if [ -d "$font_dir" ] && find "$font_dir" -iname "*JetBrainsMono*Nerd*" 2>/dev/null | grep -q .; then
                return 0
            fi
        done
        return 1
    fi
    command -v fc-list >/dev/null 2>&1 && fc-list | grep -qi "JetBrainsMono"
}

# Extract only the core JetBrainsMono Nerd Font variants (regular + mono) from
# the zip straight into DEST — the full set is ~200MB of weights/styles a
# terminal or editor never uses. unzip does selective extraction natively;
# python3 is the fallback (minimal Ubuntu has python3 but often not unzip).
# Returns non-zero if neither tool exists or extraction fails (e.g. out of disk).
extract_core_fonts() {
    local zip="$1" dest="$2"
    local pats=("JetBrainsMonoNerdFont-*.ttf" "JetBrainsMonoNerdFontMono-*.ttf")
    mkdir -p "$dest"
    if command -v unzip >/dev/null 2>&1; then
        unzip -oqj "$zip" "${pats[@]}" -d "$dest" 2>/dev/null
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        FONT_DEST="$dest" python3 - "$zip" <<'PY' 2>/dev/null
import os, sys, zipfile, fnmatch
dest = os.environ["FONT_DEST"]
pats = ("JetBrainsMonoNerdFont-*.ttf", "JetBrainsMonoNerdFontMono-*.ttf")
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        base = os.path.basename(name)
        if base and any(fnmatch.fnmatch(base, p) for p in pats):
            with z.open(name) as src, open(os.path.join(dest, base), "wb") as out:
                out.write(src.read())
PY
        return
    fi
    return 1
}

ensure_font() {
    if font_installed; then
        echo "[prereq] Nerd Font   ✓ already present"
        return
    fi
    if [ "$OS" = "windows" ]; then
        if command -v scoop >/dev/null 2>&1; then
            scoop bucket add nerd-fonts >/dev/null 2>&1 || true
            scoop install JetBrainsMono-NF >/dev/null 2>&1 \
                && echo "[prereq] Nerd Font   ↓ installed (scoop)" \
                || echo "[prereq] Nerd Font   ⚠ install failed — run: scoop install JetBrainsMono-NF"
        else
            echo "[prereq] Nerd Font   ⚠ needs scoop first, then: scoop bucket add nerd-fonts; scoop install JetBrainsMono-NF"
        fi
        return
    fi
    # Linux: download the zip, extract the core variants into the user font dir,
    # refresh the cache. Every step is guarded so a failure (e.g. out of disk)
    # warns instead of aborting the whole bootstrap.
    local fonts_dir="$HOME/.local/share/fonts" tmp count
    tmp="$(mktemp -d)"
    if ! download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" "$tmp/JBM.zip"; then
        echo "[prereq] Nerd Font   ⚠ download failed — install manually (see README)"
        rm -rf "$tmp"
        return
    fi
    if ! extract_core_fonts "$tmp/JBM.zip" "$fonts_dir"; then
        echo "[prereq] Nerd Font   ⚠ couldn't extract (need unzip or python3, or out of disk)"
        rm -rf "$tmp"
        return
    fi
    rm -rf "$tmp"
    count="$(find "$fonts_dir" -name 'JetBrainsMono*NerdFont*.ttf' 2>/dev/null | wc -l)"
    if [ "$count" -eq 0 ]; then
        echo "[prereq] Nerd Font   ⚠ no files extracted (out of disk?) — free space and re-run"
        return
    fi
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1
    fi
    echo "[prereq] Nerd Font   ↓ installed ($count files) — set your terminal font to 'JetBrainsMono Nerd Font'"
}

echo
echo "[bootstrap] Prerequisites:"
ensure_oh_my_posh
ensure_jq
ensure_font

echo
echo "[bootstrap] Done. Restart Claude Code and open a new terminal to apply."
