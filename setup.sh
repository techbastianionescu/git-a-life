#!/usr/bin/env bash
# One-command full setup: config + developer pack.
#
#   ./setup.sh          everything (config, then apps)
#   ./bootstrap.sh      config only      (fast, no elevation)
#   ./install-apps.sh   dev pack only    (slow, needs elevation)
#
# This just chains the two focused scripts so you get both possibilities:
# run them à la carte, or run the whole thing here.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> [1/2] Config + prerequisites"
bash "$REPO_DIR/bootstrap.sh"

echo
echo "==> [2/2] Developer application pack"
bash "$REPO_DIR/install-apps.sh"

echo
echo "==> Setup complete."
