#!/usr/bin/env bash
# claude-0 / claude-1 / claude-2: run Claude Code logged into a separate account.
#
# Claude Code keeps one login per config dir (.credentials.json + .claude.json),
# shared by every `claude` on the box, so /login in one session (or a token
# refresh by an older session) switches all of them. Each claude-N uses its own
# CLAUDE_CONFIG_DIR=~/.claude-N, so each holds its own login; log in once per
# account. Plain `claude` keeps using ~/.claude.
#
# The shared, versioned config (settings, hooks, skills, statusline, ...) is
# symlinked in from ~/.claude on every launch; login, history, projects
# (transcripts + memory) and caches stay separate per account. An entry the
# account dir already has as a real file or dir is left alone.
set -euo pipefail

name=$(basename "$0")
n=${name#claude-}
case "$n" in
  ''|*[!0-9]*) echo "$name: run as claude-<N> (e.g. claude-0)" >&2; exit 2 ;;
esac

base="${HOME}/.claude"
dir="${HOME}/.claude-${n}"
mkdir -p "$dir"

for f in settings.json statusline.sh CLAUDE.md keybindings.json commands hooks bin skills agents; do
  [ -e "${base}/${f}" ] || continue
  if [ -L "${dir}/${f}" ] || [ ! -e "${dir}/${f}" ]; then
    ln -sfn "${base}/${f}" "${dir}/${f}"
  fi
done

export CLAUDE_CONFIG_DIR="$dir"
exec /usr/local/bin/claude "$@"
