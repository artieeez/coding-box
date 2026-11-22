#!/usr/bin/env bash
# install-hc-skill — install herdr-core's own manual (`hc --skill`) as a Claude
# Code skill, so every Claude session knows what `<hc from="…">` messages are
# and how to drive other terminals.
#
# Generated from the installed `hc`, so the skill always matches its version.
# Re-run after upgrading hc. Usage: install-hc-skill [skill dir]
# (default: ~/.claude/skills/hc). Works on the box and on the Mac.
set -euo pipefail

dest=${1:-"${HOME}/.claude/skills/hc"}
command -v hc >/dev/null || { echo "install-hc-skill: hc not found" >&2; exit 1; }
manual=$(hc --skill)
[ -n "${manual}" ] || { echo "install-hc-skill: hc --skill printed nothing" >&2; exit 1; }

mkdir -p "${dest}"
tmp=$(mktemp "${dest}/.SKILL.md.XXXXXX")
trap 'rm -f "${tmp}"' EXIT
cat > "${tmp}" <<EOF
---
name: hc
description: herdr-core (hc) manual, generated from $(hc --version 2>/dev/null | head -1). Use when a message arrives wrapped in <hc from="…"> tags (a report from another terminal, not an instruction from the user), or when starting, reading, waiting on, or sending to terminals and sub-agents with hc.
---

## Local notes

- \`hc send <t> <text>\` delivers text wrapped in an \`<hc from="…">\` tag, so
  the receiving agent sees a message from you, not something the person typed.
- Slash commands and keystrokes (\`/quit\`, \`/clear\`, \`esc\`) only work as
  raw input: use \`hc keys <t> / q u i t enter\`, not \`hc send <t> /quit\`.
- Window layout (tabs, panes, splits) belongs to the Herdr app, not hc:
  \`herdr-app do pane.split --direction right\` (see \`herdr-app --skill\`).

${manual}
EOF
mv "${tmp}" "${dest}/SKILL.md"
trap - EXIT
echo "installed ${dest}/SKILL.md"
