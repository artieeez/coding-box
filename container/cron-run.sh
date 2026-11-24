#!/bin/sh
# cron-run — the `cron` sidecar's command (artr-gitops apps/coding-box):
# supercronic on $CRONTAB_FILE (default ~/.crontab), which the `crontab`
# shim edits. The file must exist before supercronic starts; -inotify
# reloads it on every change, so `crontab -` takes effect without a restart.
set -eu
file=${CRONTAB_FILE:-$HOME/.crontab}
[ -e "$file" ] || : >"$file"
exec supercronic -inotify -passthrough-logs "$file"
