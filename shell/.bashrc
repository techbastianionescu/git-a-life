# User-local binaries (oh-my-posh, jq on Linux land here). Listed first so the
# prompt init below finds them.
export PATH="$HOME/.local/bin:$PATH"

# Windows (Git Bash): Node + npm globals live off the system PATH, so add them.
# On Linux these come from apt/nvm and are already present — skip.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    export PATH="$PATH:/c/Program Files/nodejs"
    export PATH="$PATH:$HOME/AppData/Roaming/npm"
fi

# cargo (cross-platform)
export PATH="$PATH:$HOME/.cargo/bin"

# oh-my-posh prompt — only if installed, so a fresh machine doesn't error every
# shell before prerequisites are in place.
if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init bash --config "$HOME/.poshthemes/night-owl.omp.json")"
fi
