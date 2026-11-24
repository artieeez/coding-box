#!/bin/sh
# crontab — a minimal `crontab` for the box, backed by supercronic.
#
# The box runs as UID 10000, and Debian's cron daemon needs root, so the
# schedule runs under supercronic (the `cron` sidecar in artr-gitops
# apps/coding-box), which reads ONE file: $CRONTAB_FILE (default
# ~/.crontab, on the PVC home). This shim gives tools that expect the
# classic interface (`ork fabrica batida instalar` runs `crontab -l` and
# `crontab -`) the same file. Supercronic re-reads it on change (-inotify).
#
#   crontab -l          print the crontab ("no crontab for USER", exit 1, if none)
#   crontab - | FILE    install from stdin / FILE (validated by supercronic -test)
#   crontab -e          edit with $VISUAL / $EDITOR / nvim
#   crontab -r          remove every entry (the file stays, empty)
set -eu

file=${CRONTAB_FILE:-$HOME/.crontab}
user=$(id -un 2>/dev/null || id -u)

usage() {
  echo "usage: crontab [-l | -r | -e | - | FILE]  (user crontabs only; -u is unsupported)" >&2
  exit 1
}

# Validate, then replace atomically (same directory) so supercronic never
# reads a half-written file.
install_from() {
  tmp=$(mktemp "$file.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  cat "$1" >"$tmp"
  if ! out=$(supercronic -test "$tmp" 2>&1); then
    echo "crontab: invalid crontab, not installed:" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  trap - EXIT
}

[ $# -eq 1 ] || usage
case $1 in
  -l)
    [ -e "$file" ] || { echo "no crontab for $user" >&2; exit 1; }
    cat "$file"
    ;;
  -r)
    [ -e "$file" ] || { echo "no crontab for $user" >&2; exit 1; }
    # Empty it rather than delete it: supercronic keeps watching the file.
    : >"$file"
    ;;
  -e)
    edit=$(mktemp "${TMPDIR:-/tmp}/crontab.XXXXXX")
    [ -e "$file" ] && cat "$file" >"$edit"
    ${VISUAL:-${EDITOR:-nvim}} "$edit"
    install_from "$edit"
    rm -f "$edit"
    ;;
  -) install_from /dev/stdin ;;
  -*) usage ;;
  *) [ -r "$1" ] || { echo "crontab: cannot read $1" >&2; exit 1; }
     install_from "$1" ;;
esac
