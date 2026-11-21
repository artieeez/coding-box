# syntax=docker/dockerfile:1
# check=error=true

# coding-box — thin APP image over the stable base.
# Hosts Claude Code and pi in herdr-core terminals; deployed as the
# coding-box pod (artr-gitops apps/coding-box).
#
# The heavy, rarely-changing content (node + OS deps, mise + Ruby) lives
# in docker/base.Dockerfile (pi-cloud-base). This image carries only the
# per-commit bits: pi agent version, kubectl, gh, playwright-cli, and container
# assets — so every push builds a small delta instead of re-baking a ~1.1GB
# toolchain.
#
# Build args: BASE_IMAGE defaults to the local base image name so
#   docker build -f docker/base.Dockerfile -t pi-cloud-base .
#   docker build -t pi-cloud .
# just works; CI passes the registry path + pinned tag (build-push-ocir.yaml).

ARG BASE_IMAGE=pi-cloud-base
ARG BASE_TAG=latest

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG PI_VERSION=1.6.0
ARG KUBECTL_VERSION=1.36.6
# herdr-core (`hc`): the terminal runtime the Herdr mobile/desktop apps reach
# over `ssh <box> hc connect`. Tarball sha256 from
# https://releases.herdr.dev/core/<version>/manifest.json (linux-aarch64).
ARG HC_VERSION=0.1.21
ARG HC_SHA256=e844a2bfab48a226097679d076bc83042fe57fccef5387ef802e5b24e78b529a
# Claude Code native build. sha256 = .platforms["linux-arm64"].checksum of
# https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
ARG CLAUDE_CODE_VERSION=2.1.325
ARG CLAUDE_CODE_SHA256=7b6e484b1989a5a14a4b354709ccc8672518a3ec5b9ccd7981fc6254327fde67
# Antigravity CLI (Google; `antigravity`, self-updating). Seed build; URL + sha512 from
# https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json
ARG ANTIGRAVITY_VERSION=1.5.13
ARG ANTIGRAVITY_URL=https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13-5999302598852608/linux-arm/cli_linux_arm64.tar.gz
ARG ANTIGRAVITY_SHA512=dccea2eb455099f5175f0c87cc47b38fcefe4cb0cb44dea3927469bb4bbf68ac3c0b30fc04affb24c17e90959386a93c3785e8e4b8b1a3338ca4e4d57b80057b
ARG GH_VERSION=2.102.0
# lazygit (LazyVim's <leader>gg), pinned; verified against the release checksums.
ARG LAZYGIT_VERSION=0.66.3
# @playwright/cli (browser automation CLI for pi UAT); its chromium headless
# shell is baked at image build — see the install-browser RUN below.
ARG PLAYWRIGHT_CLI_VERSION=0.1.22
# markdownlint-cli2 (pinned, npm): agents lint markdown per repo AGENTS.md.
ARG MARKDOWNLINT_CLI2_VERSION=0.23.2

# python3 + file: everyday agent tooling (edit scripts, type sniffing).
RUN apt-get update && \
    apt-get install --no-install-recommends -y python3 file && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# markdownlint-cli2 for agents running in coding-box.
RUN npm install -g "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"

# pi coding agent (pinned; --ignore-scripts per upstream docs)
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

# kubectl, pinned to the cluster server version (check: kubectl version -o json)
# sha256 sidecar = https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256
RUN cd /tmp && \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl" && \
    curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl kubectl.sha256

# LazyVim tooling (artieeez/nvim-config, same as the Mac): fd + fzf for the
# pickers, unzip for Mason's LSP downloads. Debian names fd `fdfind`. nvim is
# also linked into /usr/local/bin: non-login shells (`ssh box cmd`, herdr-core
# terminals) don't get /opt/nvim/bin from profile.d.
RUN apt-get update && \
    apt-get install --no-install-recommends -y fd-find fzf unzip && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    ln -s /opt/nvim/bin/nvim /usr/local/bin/nvim

# herdr-core (pinned, checksum-verified). In /usr/local/bin so the non-login
# `ssh box hc connect` the Herdr app runs finds it on sshd's default PATH.
RUN cd /tmp && \
    curl -fsSLo hc.tar.gz "https://releases.herdr.dev/core/${HC_VERSION}/herdr-core-linux-aarch64.tar.gz" && \
    echo "${HC_SHA256}  hc.tar.gz" | sha256sum -c - && \
    mkdir hc && tar -xzf hc.tar.gz -C hc && \
    install -m 0755 hc/herdr-core /usr/local/bin/herdr-core && \
    ln -s herdr-core /usr/local/bin/hc && \
    rm -rf hc hc.tar.gz && \
    hc --version

# Claude Code (pinned native binary, checksum-verified). Baked outside the PVC
# home so every shell (login or not, sshd or hc terminal) finds it.
# Never self-updates: DISABLE_AUTOUPDATER=1 (also set by the deployment).
ENV DISABLE_AUTOUPDATER=1
RUN cd /tmp && \
    curl -fsSLo claude "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-arm64/claude" && \
    echo "${CLAUDE_CODE_SHA256}  claude" | sha256sum -c - && \
    install -m 0755 claude /usr/local/bin/claude && \
    rm -f claude && \
    claude --version

# Antigravity CLI (sha512-verified). This baked copy is a SEED: it self-updates,
# which needs a user-writable path, so deployments copy it once into the
# home's ~/.local/bin (coding-box setup init) and it updates itself there.
RUN cd /tmp && \
    curl -fsSLo ag.tar.gz "${ANTIGRAVITY_URL}" && \
    echo "${ANTIGRAVITY_SHA512}  ag.tar.gz" | sha512sum -c - && \
    tar -xzf ag.tar.gz antigravity && \
    install -m 0755 antigravity /usr/local/bin/antigravity && \
    rm -f antigravity ag.tar.gz && \
    test "$(HOME=/tmp antigravity --version)" = "${ANTIGRAVITY_VERSION}"

# lazygit (pinned) — verified against the release checksums file.
RUN cd /tmp && \
    curl -fsSLO "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz" && \
    curl -fsSLO "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/checksums.txt" && \
    grep " lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz\$" checksums.txt | sha256sum -c - && \
    tar -xzf "lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz" lazygit && \
    install -m 0755 lazygit /usr/local/bin/lazygit && \
    rm -f lazygit "lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz" checksums.txt

# gh (GitHub CLI, pinned) — verified against the release checksums file, which
# carries one line per asset; grep the arm64 tarball line and sha256sum -c it.
RUN cd /tmp && \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_arm64.tar.gz" && \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" && \
    grep "gh_${GH_VERSION}_linux_arm64.tar.gz\$" "gh_${GH_VERSION}_checksums.txt" | sha256sum -c - && \
    tar -xzf "gh_${GH_VERSION}_linux_arm64.tar.gz" && \
    install -m 0755 "gh_${GH_VERSION}_linux_arm64/bin/gh" /usr/local/bin/gh && \
    rm -rf "gh_${GH_VERSION}_linux_arm64" "gh_${GH_VERSION}_linux_arm64.tar.gz" "gh_${GH_VERSION}_checksums.txt"

# playwright-cli (pinned, npm) — browser automation for pi UAT on the box.
# The npm package is small; the chromium headless shell (~110MB download) is
# the heavy part. Browsers bake under /opt, NOT the default ~/.cache under
# /root: /root is the PVC mount and shadows image content at runtime, so a
# browser baked there would vanish on first boot. PLAYWRIGHT_BROWSERS_PATH is
# exported here (the entrypoint inherits it) and re-exported in profile.d for
# sshd sessions, which reset the container env.
#
# Headless shell only, via PLAYWRIGHT_MCP_CONFIG: with no config the CLI
# forces channel 'chrome' (system Google Chrome at /opt/google/chrome/chrome),
# and `--browser chromium` forces channel 'chrome-for-testing' (the full
# chromium build) — neither is baked here. The global config shipped below
# pins browserName=chromium with NO channel, so playwright launches its
# chromium headless shell build — the one baked by --only-shell — and the box
# has no display anyway. chromiumSandbox:false because the container runs as
# root. Validated on the box: `playwright-cli open <url>` then snapshot/close
# work end-to-end with only chromium_headless_shell-1243 present.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PLAYWRIGHT_MCP_CONFIG=/opt/pi-cloud-playwright-cli.config.json
COPY container/playwright-cli.config.json /opt/pi-cloud-playwright-cli.config.json
RUN npm install -g "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" && \
    playwright-cli install-browser chromium --only-shell --with-deps && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# In-cluster kubeconfig (ServiceAccount-based, see docs). Baked OUTSIDE /root:
# /root is the PVC mount at runtime and shadows image content — the entrypoint
# seeds /root/.kube/config from here when absent.
COPY container/kubeconfig.yaml /opt/pi-cloud-kubeconfig.yaml

# Container assets
COPY container/sshd_config /etc/ssh/sshd_config.d/10-pi-cloud.conf
COPY container/profile.d/pi-cloud.sh /etc/profile.d/pi-cloud.sh
COPY container/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY container/sync-configs.sh /usr/local/bin/sync-configs.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sync-configs.sh && \
    ln -s /usr/local/bin/entrypoint.sh /entrypoint

# Non-root runtime for coding-box (artr-gitops apps/coding-box),
# which runs this image as UID/GID 10000 (user arturwebber, HOME=/home/arturwebber,
# the PVC mount; -M: not created in the image):
# - a real passwd entry (sshd, whoami, git need one)
# - mise shims writable, so `bundle install` can reshim gem executables
#   (Ruby itself stays root-owned; gems go to GEM_HOME/BUNDLE_PATH on the PVC)
# - TMPDIR set (Debian leaves it unset; agents write "$TMPDIR/x")
# - a WORKDIR that UID 10000 can stat (git fails in /root)
RUN groupadd -g 10000 arturwebber && \
    useradd -u 10000 -g 10000 -d /home/arturwebber -M -s /bin/bash \
      -c "Artur Webber (coding-box)" arturwebber && \
    chown -R 10000:10000 /opt/mise/shims
ENV TMPDIR=/tmp

# Default user stays root (the legacy entrypoint expects it); Kubernetes sets
# runAsUser: 10000 for coding-box.
USER root
WORKDIR /tmp

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]