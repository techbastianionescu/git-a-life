#!/usr/bin/env bash
# Shared helpers sourced by bootstrap.sh, install-apps.sh and setup.sh.
# Keeps OS/arch detection and the download primitive in one place.

# ── Platform + CPU arch ──────────────────────
# Drives both branch logic and which prebuilt binary to fetch.
case "$(uname -s)" in
    Linux*)               OS="linux"   ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    *)                    OS="unknown" ;;
esac
case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)             ARCH="amd64" ;;   # best-effort default
esac

# ── download URL DEST ────────────────────────
# Uses whichever of curl/wget exists (minimal Ubuntu ships wget, not curl).
# Returns non-zero if neither is available so callers can fall back to a warning.
download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        return 1
    fi
}

# ── read_manifest FILE ───────────────────────
# Emit the data lines of a pipe-delimited manifest, skipping comments and blanks.
# Callers parse with: while IFS='|' read -r col1 col2 ...; do ... done < <(read_manifest f)
read_manifest() {
    grep -vE '^[[:space:]]*(#|$)' "$1"
}
