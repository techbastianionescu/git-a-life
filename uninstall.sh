#!/usr/bin/env bash
# Undo what setup.sh / bootstrap.sh installed.
# Run from the repo root:  ./uninstall.sh
#
# Restores any config file that had a backup from install time, otherwise removes
# it. Removes the prompt prerequisites. The developer apps come off only if you
# say yes; they're general software you may want to keep. The repo itself is left
# alone (delete it with: rm -rf ~/git-a-life).

set -uo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/lib/common.sh"   # provides OS

CLAUDE_HOME="$HOME/.claude"

# Put a file back the way it was: newest backup wins, else just delete it.
restore_or_remove() {
    local target="$1" newest
    newest="$(ls -t "$target".bak.* 2>/dev/null | head -1 || true)"
    if [ -n "$newest" ]; then
        mv -f "$newest" "$target"
        echo "  restored $target (from backup)"
    elif [ -e "$target" ]; then
        rm -f "$target"
        echo "  removed  $target"
    fi
}

# ponytail: one check for the only risky branch (it touches user files).
if [ "${1:-}" = "--self-test" ]; then
    d="$(mktemp -d)"; echo live >"$d/f"; echo saved >"$d/f.bak.1"
    restore_or_remove "$d/f"; [ "$(cat "$d/f")" = saved ] || { echo FAIL-restore; exit 1; }
    restore_or_remove "$d/f"; [ ! -e "$d/f" ]            || { echo FAIL-remove;  exit 1; }
    rm -rf "$d"; echo self-test-ok; exit 0
fi

# Reads the same apps.txt that install-apps.sh uses, so the two never drift.
remove_apps() {
    local name winget snap classic
    if [ "$OS" = "windows" ]; then
        command -v winget >/dev/null 2>&1 || { echo "  winget missing, skipped apps"; return; }
        while IFS='|' read -r name winget snap classic; do
            [ -n "$winget" ] || continue
            winget uninstall --id "$winget" -e >/dev/null 2>&1 && echo "  removed $name"
        done < <(read_manifest "$REPO_DIR/apps.txt")
    else
        local snaps=()
        while IFS='|' read -r name winget snap classic; do
            [ -n "$snap" ] && snaps+=("$snap")
        done < <(read_manifest "$REPO_DIR/apps.txt")
        [ "${#snaps[@]}" -gt 0 ] && sudo snap remove --purge "${snaps[@]}" 2>/dev/null
        # Docker Engine + the group setup added, GitHub CLI + its apt repo, Claude.
        sudo apt-get remove -y docker-ce docker-ce-cli containerd.io \
             docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
        sudo gpasswd -d "$USER" docker >/dev/null 2>&1 || true
        sudo apt-get remove -y gh >/dev/null 2>&1
        sudo rm -f /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/githubcli-archive-keyring.gpg
        rm -f "$HOME/.local/bin/claude"; rm -rf "$HOME/.local/share/claude"
        echo "  removed snaps, Docker Engine, GitHub CLI, Claude Code"
        echo "  kept git + curl (base tools; removing them would break the system)"
    fi
}

echo "[uninstall] Config files:"
restore_or_remove "$CLAUDE_HOME/CLAUDE.md"
restore_or_remove "$CLAUDE_HOME/settings.json"
restore_or_remove "$CLAUDE_HOME/statusline-command.sh"
restore_or_remove "$CLAUDE_HOME/skills/doc/SKILL.md"
restore_or_remove "$HOME/.bashrc"
restore_or_remove "$HOME/.minttyrc"
rm -f "$HOME/.poshthemes/night-owl.omp.json" && echo "  removed  night-owl theme"

echo "[uninstall] Prompt prerequisites:"
if [ "$OS" = "windows" ]; then
    command -v scoop >/dev/null 2>&1 && scoop uninstall oh-my-posh jq JetBrainsMono-NF >/dev/null 2>&1
    echo "  removed oh-my-posh, jq, font (scoop)"
else
    rm -f "$HOME/.local/bin/oh-my-posh" "$HOME/.local/bin/jq"
    rm -f "$HOME/.local/share/fonts/"JetBrainsMono*NerdFont*.ttf
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1
    echo "  removed oh-my-posh, jq, JetBrainsMono fonts"
fi

read -rp "[uninstall] Also remove the developer apps (VS Code, Docker, Spotify…)? [y/N] " ans
case "$ans" in
    [Yy]*) echo "[uninstall] Developer apps:"; remove_apps ;;
    *)     echo "[uninstall] kept the apps." ;;
esac

echo
echo "[uninstall] Done. The ~/git-a-life repo is untouched (rm -rf ~/git-a-life to remove it)."

# This shell still has the (now-deleted) oh-my-posh prompt hooked and would spam
# "no such file" on every keypress. A child script can't un-hook its parent, so
# we close the terminal on request (SIGHUP to the parent shell); reopening one
# starts clean. Interactive only, so script/SSH runs are unaffected.
if [ -t 0 ]; then
    echo
    read -rp "[uninstall] Press Enter to close this terminal (reopen one for a clean shell)... " _
    kill -HUP "$PPID" 2>/dev/null
fi
