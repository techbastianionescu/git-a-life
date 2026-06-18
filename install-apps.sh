#!/usr/bin/env bash
# Install the developer application pack.
# Run from the repo root:  ./install-apps.sh
#
# Windows: winget (ships with Win11).  Linux: snap for GUI apps, apt for git,
# Docker *Engine* (not Desktop) and Claude Code via their official installers.
#
# Needs elevation — UAC prompts on Windows, sudo password on Linux — and a
# network connection. Docker Desktop on Windows may require a reboot. Idempotent:
# the package managers skip anything already installed.
#
# After installs, an optional account phase opens each app that needs a login and
# waits for you to sign in. It auto-skips when run non-interactively (no TTY).

# NOTE: not 'set -e' — one app failing must not abort the whole pack.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/lib/common.sh"   # provides OS, ARCH, download()

# ── Console UI ───────────────────────────────
# Colour + spinner only when stdout is a real terminal; piped/headless runs
# (e.g. driven over SSH or in CI) fall back to plain lines so logs stay readable.
if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=; C_DIM=; C_BOLD=; C_GREEN=; C_YELLOW=; C_BLUE=
fi

header() { printf '\n%s== %s ==%s\n' "${C_BOLD}${C_BLUE}" "$*" "$C_RESET"; }

# print_status NAME ok|warn|info MESSAGE
print_status() {
    local name="$1" kind="$2" msg="$3" icon color
    case "$kind" in
        ok)   icon="✓"; color="$C_GREEN"  ;;
        warn) icon="⚠"; color="$C_YELLOW" ;;
        *)    icon="•"; color="$C_DIM"    ;;
    esac
    printf '  %s%s%s  %-18s %s%s%s\n' "$color" "$icon" "$C_RESET" "$name" "$C_DIM" "$msg" "$C_RESET"
}

# spin_wait LABEL RCDIR TOTAL — animate until TOTAL ".rc" sentinels appear in
# RCDIR (each background job drops one when it finishes). Counting files, not
# waiting on PIDs, means unrelated background work (Docker, Claude, the sudo
# keep-alive) can't throw the count off. Plain line on a non-TTY.
spin_wait() {
    local label="$1" rcdir="$2" total="$3" i=0 done=0
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    [ -t 1 ] || echo "  $label ($total in parallel)..."
    while [ "$done" -lt "$total" ]; do
        done=$(( $(find "$rcdir" -name '*.rc' 2>/dev/null | wc -l) ))
        [ -t 1 ] && printf '\r  %s%s%s %s  %s[%d/%d done]%s ' \
            "$C_BLUE" "${frames[i++ % ${#frames[@]}]}" "$C_RESET" \
            "$label" "$C_DIM" "$done" "$total" "$C_RESET"
        [ "$done" -lt "$total" ] && sleep 0.2
    done
    [ -t 1 ] && printf '\r\033[K'   # wipe the spinner line; results print next
}

# ── Windows: winget ──────────────────────────
# Serial, not parallel: winget installers grab MSI/UAC locks and fail if run
# concurrently. Each shows its own status line.
install_windows() {
    header "Developer pack (Windows)"
    if ! command -v winget >/dev/null 2>&1; then
        print_status "winget" warn "not found — update App Installer from the Microsoft Store, then re-run"
        return
    fi
    # Every app with a winget id (the whole pack on Windows) comes from apps.txt.
    local name id snap classic
    while IFS='|' read -r name id snap classic; do
        [ -n "$id" ] || continue
        if winget list --id "$id" -e >/dev/null 2>&1; then
            print_status "$name" ok "already installed"
        elif winget install --id "$id" -e --silent \
                    --accept-package-agreements --accept-source-agreements >/dev/null 2>&1; then
            print_status "$name" ok "done"
        else
            print_status "$name" warn "failed — run: winget install --id $id -e"
        fi
    done < <(read_manifest "$REPO_DIR/apps.txt")
}

# Prompt for sudo once and keep the credential warm in the background for the
# whole run, so the install steps don't each stop to ask. Returns non-zero if
# the user can't elevate at all.
ensure_sudo() {
    command -v sudo >/dev/null 2>&1 || return 1
    # Already passwordless (NOPASSWD) or cached? Nothing to prompt or keep alive —
    # and importantly, don't run 'sudo -v', which demands a TTY even under NOPASSWD.
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    # A password is needed, so we must be interactive to ask for it.
    [ -t 0 ] || return 1
    echo "[apps] Requesting sudo up front (installs need root)..."
    sudo -v || return 1
    # Keep the timestamp warm so long installs don't re-prompt mid-run.
    ( while true; do sleep 50; sudo -n true 2>/dev/null || break; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

# ── Linux: snap + apt + Docker Engine ────────
install_linux() {
    header "Developer pack (Linux)"
    if ! ensure_sudo; then
        print_status "sudo" warn "can't elevate — installs need sudo. Re-run where you can."
        return
    fi
    # The Claude Code and Docker installers shell out to curl internally; minimal
    # Ubuntu ships without it. Install it once up front so both succeed.
    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get install -y curl >/dev/null 2>&1 && print_status "curl" ok "installed (needed by Claude/Docker installers)"
    fi
    install_linux_git        # quick; apt
    install_linux_gh         # GitHub CLI; apt too, so keep it serial before Docker's apt

    # Docker (big apt download) and Claude (binary download) don't touch snapd, so
    # run them in the background while the snaps install. Output is captured and
    # printed after, so it doesn't tangle with the snap spinner.
    local bg; bg="$(mktemp -d)"
    ( install_linux_claude  >"$bg/claude.out" 2>&1 ) & local claude_pid=$!
    ( install_linux_docker  >"$bg/docker.out" 2>&1 ) & local docker_pid=$!

    install_linux_snaps      # visible parallel install + spinner

    wait "$claude_pid" "$docker_pid" 2>/dev/null
    cat "$bg/claude.out" "$bg/docker.out" 2>/dev/null
    rm -rf "$bg"
}

# Snaps install in parallel: each one is launched as a background job writing to
# its own log, so downloads overlap. snapd serialises the final install steps, so
# the real win is overlapped downloads (~2-3x), not full N-way parallelism. Per-app
# logs keep failure causes (e.g. "no space left") visible.
install_linux_snaps() {
    if ! command -v snap >/dev/null 2>&1; then
        print_status "snap" warn "not found — install it first: sudo apt install -y snapd"
        return
    fi
    # Apps with a snap package come from apps.txt (the blank-snap rows, like git
    # and Docker, are skipped here and handled by their own functions).
    local tmpdir; tmpdir="$(mktemp -d)"
    local pids=() names=() logs=() name winget pkg classic
    while IFS='|' read -r name winget pkg classic; do
        [ -n "$pkg" ] || continue
        if snap list "$pkg" >/dev/null 2>&1; then
            print_status "$name" ok "already installed"
            continue
        fi
        # Each job records its exit code in a .rc sentinel so the report loop
        # reads status from there — robust no matter who reaped the PID.
        local log="$tmpdir/$pkg.log"
        (
            if [ "$classic" = "classic" ]; then
                sudo snap install "$pkg" --classic >"$log" 2>&1
            else
                sudo snap install "$pkg" >"$log" 2>&1
            fi
            echo "$?" >"$log.rc"
        ) &
        pids+=("$!"); names+=("$name"); logs+=("$log")
    done < <(read_manifest "$REPO_DIR/apps.txt")

    if [ "${#pids[@]}" -gt 0 ]; then
        spin_wait "installing ${#pids[@]} snaps" "$tmpdir" "${#pids[@]}"
        wait "${pids[@]}" 2>/dev/null   # reap (already finished); status is in the .rc files
        local i rc
        for i in "${!pids[@]}"; do
            rc="$(cat "${logs[$i]}.rc" 2>/dev/null || echo 1)"
            if [ "$rc" = "0" ]; then
                print_status "${names[$i]}" ok "done"
            else
                print_status "${names[$i]}" warn "$(tail -1 "${logs[$i]}")"
            fi
        done
    fi
    rm -rf "$tmpdir"
}

# Git Bash is Windows-only; on Linux the shell is already bash, so just install git.
install_linux_git() {
    if command -v git >/dev/null 2>&1; then
        print_status "git" ok "already installed"
        return
    fi
    local out; out="$(sudo apt install -y git 2>&1)"
    if [ $? -eq 0 ]; then
        print_status "git" ok "done"
    else
        print_status "git" warn "$(printf '%s' "$out" | tail -1)"
    fi
}

# GitHub CLI from the official apt repo. gh isn't in default Ubuntu and has no
# trustworthy snap, so we add their signed repo. Powers 'gh auth login' (the real
# GitHub authorization) in the account phase.
install_linux_gh() {
    if command -v gh >/dev/null 2>&1; then
        print_status "GitHub CLI" ok "already installed"
        return
    fi
    local key=/etc/apt/keyrings/githubcli-archive-keyring.gpg tmp=/tmp/ghkey.gpg
    if download "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$tmp" \
        && sudo install -D -m 644 "$tmp" "$key" \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=$key] https://cli.github.com/packages stable main" \
             | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
        && sudo apt-get update -qq >/dev/null 2>&1 \
        && sudo apt-get install -y gh >/dev/null 2>&1; then
        print_status "GitHub CLI" ok "done"
    else
        print_status "GitHub CLI" warn "install failed — see cli.github.com"
    fi
    rm -f "$tmp"
}

# Claude Code CLI — official native installer drops the binary in ~/.local/bin
# (already on PATH) with no sudo, and auto-updates itself afterwards.
install_linux_claude() {
    if command -v claude >/dev/null 2>&1; then
        print_status "Claude Code" ok "already installed"
        return
    fi
    local tmp out
    tmp="$(mktemp -d 2>/dev/null)" || {
        print_status "Claude Code" warn "no temp space (free disk and re-run)"
        return
    }
    if ! download "https://claude.ai/install.sh" "$tmp/claude-install.sh"; then
        print_status "Claude Code" warn "download failed — see code.claude.com/docs"
        rm -rf "$tmp"
        return
    fi
    out="$(bash "$tmp/claude-install.sh" 2>&1)"
    if [ $? -eq 0 ]; then
        print_status "Claude Code" ok "done (run 'claude' to log in)"
    else
        print_status "Claude Code" warn "$(printf '%s' "$out" | tail -1)"
    fi
    rm -rf "$tmp"
}

# Docker Engine (daemon + CLI), not Docker Desktop — the standard on Linux.
install_linux_docker() {
    if command -v docker >/dev/null 2>&1; then
        print_status "Docker Engine" ok "already installed"
        return
    fi
    local tmp out
    tmp="$(mktemp -d 2>/dev/null)" || {
        print_status "Docker Engine" warn "no temp space (free disk and re-run)"
        return
    }
    if ! download "https://get.docker.com" "$tmp/get-docker.sh"; then
        print_status "Docker Engine" warn "download failed"
        rm -rf "$tmp"
        return
    fi
    out="$(sudo sh "$tmp/get-docker.sh" 2>&1)"
    if [ $? -eq 0 ]; then
        # Let the current user run docker without sudo (takes effect next login).
        sudo usermod -aG docker "$USER" >/dev/null 2>&1 || true
        print_status "Docker Engine" ok "done — log out/in for group 'docker' to apply"
    else
        print_status "Docker Engine" warn "$(printf '%s' "$out" | tail -1)"
    fi
    rm -rf "$tmp"
}

# ── Account setup (interactive) ──────────────
# Opens each account-bound app and waits for you to finish signing in. Nothing is
# auto-confirmed. Skipped when there is no TTY (e.g. piped / headless runs).
account_setup() {
    if [ ! -t 0 ]; then
        echo "[accounts] non-interactive shell — skipping sign-in phase"
        return
    fi
    echo
    read -rp "[accounts] Set up app logins now? [y/N] " ans
    case "$ans" in
        [Yy]*) ;;
        *) echo "[accounts] skipped — run ./install-apps.sh again anytime"; return ;;
    esac

    setup_github
    account_app "Spotify"                 spotify
    account_app "Thunderbird"             thunderbird
    account_app "VS Code (Settings Sync)" code
    setup_claude_login
    setup_docker_login   # last on purpose — the one finicky CLI login
}

# Real GitHub sign-in is 'gh auth login' (browser/device flow, actually authorizes
# you). user.name/email is only commit attribution, set after. config --global on
# its own never logged anyone into anything.
setup_github() {
    command -v git >/dev/null 2>&1 || return
    echo
    echo "[accounts] >> GitHub login"
    if command -v gh >/dev/null 2>&1; then
        gh auth login || echo "[accounts]    skipped/failed — run 'gh auth login' later"
    else
        echo "[accounts]    GitHub CLI (gh) not installed — install it for a real login, or add an SSH key."
    fi
    echo "[accounts] >> Commit identity (just the name on your commits, not a login)"
    local cur_name cur_email new_name new_email
    cur_name="$(git config --global user.name  || true)"
    cur_email="$(git config --global user.email || true)"
    read -rp "[accounts]    name  [${cur_name}]: "  new_name
    read -rp "[accounts]    email [${cur_email}]: " new_email
    [ -n "$new_name" ]  && git config --global user.name  "$new_name"
    [ -n "$new_email" ] && git config --global user.email "$new_email"
}

# Launch a GUI app (best-effort) and block until the user confirms they're in.
account_app() {
    local name="$1" cmd="$2"
    echo
    echo "[accounts] >> $name — sign in, then come back here."
    open_gui "$cmd"
    read -rp "[accounts]    Press Enter once you're signed in to $name... " _
}

open_gui() {
    local cmd="$1"
    if [ "$OS" = "windows" ]; then
        cmd.exe /c start "" "$cmd" >/dev/null 2>&1 || echo "[accounts]    (couldn't auto-open — launch $cmd from the Start menu)"
    elif [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        ( "$cmd" >/dev/null 2>&1 & ) || echo "[accounts]    (couldn't auto-open — launch $cmd manually)"
    else
        echo "[accounts]    (no desktop session — open $name manually)"
    fi
}

# Claude Code login is a full-screen TUI that would hijack the terminal, so we
# point the user at it rather than launching it inline.
setup_claude_login() {
    command -v claude >/dev/null 2>&1 || return
    echo
    echo "[accounts] >> Claude Code: run 'claude' in a terminal and follow the browser login."
}

# Docker login differs: Desktop GUI on Windows, CLI 'docker login' on Linux.
# Gated with y/N so declining is a clean skip — 'docker login' otherwise blocks
# waiting for a username, forcing a Ctrl-C that would kill the run.
setup_docker_login() {
    if [ "$OS" = "windows" ]; then
        account_app "Docker Desktop" "docker desktop"
        return
    fi
    command -v docker >/dev/null 2>&1 || return
    echo
    read -rp "[accounts] Log into Docker Hub now? [y/N] " ans
    case "$ans" in
        [Yy]*) docker login || echo "[accounts]    login failed — run 'docker login' later" ;;
        *)     echo "[accounts]    skipped — run 'docker login' anytime" ;;
    esac
}

# ── Run ──────────────────────────────────────
case "$OS" in
    windows) install_windows ;;
    linux)   install_linux   ;;
    *)       echo "unsupported OS: $(uname -s)"; exit 1 ;;
esac

account_setup

printf '\n%s✓ developer pack done%s\n' "${C_BOLD}${C_GREEN}" "$C_RESET"
