# coding-box (formerly pi-cloud)

A persistent, SSH-accessible dev box on the artr OKE cluster (oracle-cluster) for running
[pi](https://pi.dev) (+ Ruby) from an Android phone or any SSH client.

## What's inside

- **pi coding agent** (global npm, pinned `PI_VERSION`)
- **kubectl v1.36.1** with an in-cluster kubeconfig (`pi-admin` SA, cluster-admin) —
  the box can inspect Argo apps, pods, and logs directly
- **gh 2.100.0** (GitHub CLI) — PRs, issues, releases, and Actions from the box
- **playwright-cli 0.1.19** (@playwright/cli) + baked chromium headless shell —
  browser automation for pi UAT on the box (`open`/`snapshot`/`screenshot`);
  browsers live at `/opt/ms-playwright` (shell-only: the box has no display).
  A global CLI config (`PLAYWRIGHT_MCP_CONFIG`) makes `open` use the baked
  headless shell; the CLI's own defaults would look for system Chrome or the
  full chrome-for-testing build (see docs/TROUBLESHOOTING.md)
- **Ruby** via [mise](https://mise.jdx.dev) (4.0.5, matches `home`) — `mise` is
  `.ruby-version` aware; native-gem `bundle install` works out of the box (the
  base bakes `build-essential`)
- **Claude Code** (native build, pinned `CLAUDE_CODE_VERSION`, auto-update off) at
  `/usr/local/bin/claude`, so login and non-login shells both find it.
  `claude-0`, `claude-1` and `claude-2` run it logged into separate accounts:
  each uses its own `CLAUDE_CONFIG_DIR` (`~/.claude-N`), so a login or token
  refresh in one never switches the others; shared config (settings, hooks,
  skills, statusline) is symlinked in from `~/.claude`. Log in once per account
- **Antigravity CLI** (`antigravity`, Google), self-updating. The image bakes a
  seed build at `/usr/local/bin/antigravity`; coding-box copies it
  once into `~/.local/bin` (PVC), where its updates persist. Sign in once per home:
  over SSH it prints an auth URL to open on your laptop
- **herdr-core (`hc`)**, pinned `HC_VERSION` — the terminal runtime the
  [Herdr](https://herdr.dev) mobile/desktop apps talk to over `ssh <box> hc connect`
  (in coding-box the core runs in the `coding-box` container; see
  artr-gitops `apps/coding-box/README.md`). `install-hc-skill` writes hc's
  manual (`hc --skill`) to `~/.claude/skills/hc`, so Claude knows what
  `<hc from="…">` messages are; coding-box runs it on every boot
- **sshd** (key-only, root, hardened) — the only entry point, port 22
- **LazyVim tooling**: fd, fzf, unzip (Mason), lazygit (pinned `LAZYGIT_VERSION`);
  `nvim` is also linked into `/usr/local/bin` for non-login shells
- **neovim 0.12.5** (official arm64 build) — sshd + nvim = phone-friendly editing. The box runs your LazyVim config (`artieeez/nvim-config`), boot-synced to `~/.config/nvim`; nvim icons render client-side, so the ssh client's terminal needs a Nerd Font (phone: [docs/PHONE-TERMUX.md](docs/PHONE-TERMUX.md) §6, Mac: JetBrainsMono Nerd Font)
- ~~tmux~~ — removed in the ruby-4.0.5-5 base rebuild
- ~~herdr~~ — removed; herdr-core (`hc`) hosts the terminals
- git, ripgrep, sqlite3, libvips, jq, Node 24
- **less + man pages** — user-friendly pager + local docs (`man-db`/`groff-base`),
  including the C library reference, system calls and all (`manpages-dev`:
  `man 2 open`, `man 3 printf`, `man 3 pthread_create`); the Debian bookworm-slim base ships neither, so the
  base image re-enables the `dpkg` man path-exclude and restores the
  pre-installed packages' man trees (`/usr/share/doc` and locales stay excluded
  for size; the bare `man pthread` topic is POSIX-manual-only and out of scope)

## Two images: base + app

The image is split so per-commit builds stay small and the cluster node stores
one copy of the heavy layers:

- **`pi-cloud-base`** (`docker/base.Dockerfile`) — node + OS deps (+ the C
  toolchain, `build-essential`, for runtime native-gem builds) + neovim
  - mise/Ruby. Rebuilt rarely (ruby/node/OS bumps) by `build-base.yaml`
  (path-triggered push + `workflow_dispatch`); pushed as
  `vcp.ocir.io/axtvnrdemzo7/pi-cloud-base:ruby-4.0.5-7` (+ `latest`).
  (tmux was removed in the ruby-4.0.5-5 rebuild.)
- **`pi-cloud`** (repo-root `Dockerfile`) — thin delta over the base: pi agent
  version, kubectl, gh, playwright-cli (+ chromium headless shell), container
  assets (`container/`). Built on every push.

## How it's deployed

GitHub Action builds `linux/arm64` → pushes to OCIR (`vcp.ocir.io/axtvnrdemzo7/coding-box`)
→ bumps the image tag in `artieeez/artr-gitops/apps/coding-box/deployment.yaml` (manual promote workflow) → Argo CD syncs.

The app build pins `BASE_TAG` (both workflows must stay in sync when the base is
re-published under a new tag).

## Secrets volume layout (`/secrets`, mounted from SealedSecrets)

| Path | Contents | Optional? |
|---|---|---|
| `/secrets/ssh/ssh_host_ed25519_key(.pub)` | stable host keys | generated into the PVC home if absent |
| `/secrets/ssh/authorized_keys` | your SSH public keys | no → nobody can log in |
| `/secrets/git/id_ed25519(.pub)` | GitHub deploy key for `artieeez/*` | yes — no git pushes without it |
| `/secrets/git/known_hosts` | `github.com` host key | yes |
| `/secrets/pi/auth.json` | pi `auth.json` (opencode-go + friends) | no → pi has no model auth |

Entrypoint copies these into `/root/.ssh` and `/root/.pi/agent`, runs the boot
sync (see below), then starts sshd. (coding-box replaces this entrypoint; see
artr-gitops `apps/coding-box`.)

## Boot provisioning (config + repos)

On every boot the entrypoint runs `sync-configs.sh` (deploy key required, see
`/secrets/git`): it force-syncs your `pi-config` → `~/.pi/agent`, `dotagents`
→ `~/.agents`, and `nvim-config` → `~/.config/nvim`, then clones/updates the
work repos under **`~/artieeez`** (`artr-gitops`, `pi-cloud`, `oracle-cluster`,
`home`, `home-knowledge`) — mirroring your Mac `~/artieeez` layout. The image ships no baked pi config; the
box's environment context is injected by the `pi-cloud-context` extension
(`PI_CLOUD=1`). Details: [docs/BOOT-SYNC.md](docs/BOOT-SYNC.md).

## Using it

Connect with the Herdr desktop/mobile apps (they run `ssh <box> hc connect`)
or plain `ssh`.

Set-up + access details:

| Doc | Contents |
|---|---|
| [docs/ACCESS.md](docs/ACCESS.md) | hostnames, ssh config, Mac aliases (`pi-cloud` / `picloud`) |
| [docs/PHONE-TERMUX.md](docs/PHONE-TERMUX.md) | Termux over ADB, keygen, phone ssh config, 16 KB dialog |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | every runtime gotcha hit during bring-up + fixes |
| [docs/BOOT-SYNC.md](docs/BOOT-SYNC.md) | boot provisioning design: config + repo sync, layout |

## Local build

```bash
# base first (only needed once per base change), then the app image
docker build -f docker/base.Dockerfile -t pi-cloud-base .
docker build -t pi-cloud .
docker run -d -p 2222:22 -v "$PWD/.secrets:/secrets:ro" --name pi-cloud pi-cloud
ssh -p 2222 root@localhost
```
