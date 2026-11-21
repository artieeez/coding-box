#!/usr/bin/env bash
# pi-cloud entrypoint: assemble sealed secrets into ~/.ssh and ~/.pi/agent,
# run the boot sync, then sshd.
set -euo pipefail

HOME_DIR=/root
SSH_DIR=${HOME_DIR}/.ssh
PI_DIR=${HOME_DIR}/.pi/agent
SECRETS_DIR=/secrets

log() { echo "[entrypoint] $*"; }
die() { log "FATAL: $*"; exit 1; }

mkdir -p "${SSH_DIR}" "${PI_DIR}"
# /root is the NFS PVC mount root (often 777); sshd StrictModes refuses key
# auth when the home dir is group/world-writable.
chmod 700 "${HOME_DIR}"
chmod 700 "${SSH_DIR}"

# ---------------------------------------------------------------------------
# /root is the PVC mount: image files baked under /root are shadowed at
# runtime, so seed the PVC home from /opt copies when missing (kubeconfig).
# ---------------------------------------------------------------------------
if [ -f /opt/pi-cloud-kubeconfig.yaml ]; then
  mkdir -p "${HOME_DIR}/.kube"
  if [ ! -f "${HOME_DIR}/.kube/config" ]; then
    cp /opt/pi-cloud-kubeconfig.yaml "${HOME_DIR}/.kube/config"
    chmod 600 "${HOME_DIR}/.kube/config"
    log "seeded in-cluster kubeconfig"
  fi
fi

# ---------------------------------------------------------------------------
# SSH host keys — sealed for stability across restarts (phone known_hosts).
# Fallback: generate into the persistent home once.
# ---------------------------------------------------------------------------
if [ -f "${SECRETS_DIR}/ssh/ssh_host_ed25519_key" ]; then
  cp "${SECRETS_DIR}/ssh/ssh_host_ed25519_key" "${SSH_DIR}/ssh_host_ed25519_key"
  cp "${SECRETS_DIR}/ssh/ssh_host_ed25519_key.pub" "${SSH_DIR}/ssh_host_ed25519_key.pub" 2>/dev/null || true
else
  [ -f "${SSH_DIR}/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N "" -f "${SSH_DIR}/ssh_host_ed25519_key"
fi
chmod 600 "${SSH_DIR}/ssh_host_ed25519_key"

# ---------------------------------------------------------------------------
# Authorized keys — sealed. Empty file == no way in; keep the pod alive so
# kubectl exec can still rescue, but say so loudly.
# ---------------------------------------------------------------------------
if [ -f "${SECRETS_DIR}/ssh/authorized_keys" ]; then
  cp "${SECRETS_DIR}/ssh/authorized_keys" "${SSH_DIR}/authorized_keys"
else
  log "WARNING: no sealed authorized_keys — sshd will accept nobody."
  : > "${SSH_DIR}/authorized_keys"
fi
chmod 600 "${SSH_DIR}/authorized_keys"

# ---------------------------------------------------------------------------
# Git credentials (deploy key) + known_hosts
# ---------------------------------------------------------------------------
if [ -d "${SECRETS_DIR}/git" ]; then
  cp "${SECRETS_DIR}/git/id_ed25519" "${SSH_DIR}/id_ed25519" 2>/dev/null || true
  cp "${SECRETS_DIR}/git/id_ed25519.pub" "${SSH_DIR}/id_ed25519.pub" 2>/dev/null || true
  cp "${SECRETS_DIR}/git/known_hosts" "${SSH_DIR}/known_hosts" 2>/dev/null || true
  chmod 600 "${SSH_DIR}/id_ed25519"
  chmod 644 "${SSH_DIR}/id_ed25519.pub" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Boot provisioning: sync pi-config -> ~/.pi/agent, dotagents -> ~/.agents and
# the work repos into ~/artieeez (docs/BOOT-SYNC.md). Non-fatal: on failure the
# box still boots on sealed auth + pi built-in defaults.
# ---------------------------------------------------------------------------
/usr/local/bin/sync-configs.sh || log "boot sync failed (continuing)"

# ---------------------------------------------------------------------------
# pi model auth: overlay the sealed auth.json onto ~/.pi/agent/auth.json. The
# file is gitignored in pi-config so the boot sync never touches it; this merge
# deliberately runs AFTER sync.
# ---------------------------------------------------------------------------
if [ -f "${SECRETS_DIR}/pi/auth.json" ]; then
  if [ -f "${PI_DIR}/auth.json" ]; then
    tmp=$(mktemp)
    jq -s '.[0] * .[1]' "${PI_DIR}/auth.json" "${SECRETS_DIR}/pi/auth.json" > "${tmp}"
    mv "${tmp}" "${PI_DIR}/auth.json"
  else
    cp "${SECRETS_DIR}/pi/auth.json" "${PI_DIR}/auth.json"
  fi
  chmod 600 "${PI_DIR}/auth.json"
fi

# ---------------------------------------------------------------------------
# Repos live on the PVC under ~/artieeez (mirrors the Mac layout); guarantee it
# exists for clones.
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/artieeez"

log "starting sshd (key-only auth)"
# sshd runs as a CHILD, not via exec: entrypoint stays pid 1 and reaps it.
/usr/sbin/sshd -D -e &
SSHD_PID=$!
trap 'kill "${SSHD_PID}" 2>/dev/null || true' TERM INT
while kill -0 "${SSHD_PID}" 2>/dev/null; do
  sleep 5
done
wait "${SSHD_PID}" 2>/dev/null || true
log "sshd exited — container terminating"
exit 0