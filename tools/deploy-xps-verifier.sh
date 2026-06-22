#!/bin/bash
# deploy-xps-verifier.sh — install the XPS-9510 Ollama verifier stack
#
# Runs on the XPS 9510 itself. Idempotent. Designed to be inspected before
# running and to no-op cleanly if re-run.
#
# Usage:  sudo tools/deploy-xps-verifier.sh [--skip-emerge] [--skip-pull]
#
# What it does (each step skipped if already done):
#   1. emerge net-firewall/nftables (if not installed)
#   2. download upstream ollama binary to /usr/local
#   3. create system user 'ollama'
#   4. create /data/ml-models/ollama owned by ollama
#   5. install powercap-profile{,sh,initd}, ollama.{initd,confd},
#      nftables-ollama.{nft,start}
#   6. apply RAPL caps + start services
#   7. pull qwen2.5:3b-instruct-q4_K_M (unless --skip-pull)
#   8. health check
#
# NOTE: pulling the model is ~2GB download; --skip-pull if you'd rather
# do it manually later via `sudo -u ollama ollama pull ...`.

set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
XPS_DIR="$REPO_DIR/machines/xps-9510"
LOG_PREFIX="deploy-xps-verifier:"

SKIP_EMERGE=0
SKIP_PULL=0
for arg in "$@"; do
    case "$arg" in
        --skip-emerge) SKIP_EMERGE=1 ;;
        --skip-pull)   SKIP_PULL=1 ;;
        -h|--help)     sed -n '2,25p' "$0"; exit 0 ;;
        *)             echo "$LOG_PREFIX unknown arg: $arg" >&2; exit 2 ;;
    esac
done

log()  { echo "$LOG_PREFIX $*"; }
die()  { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "must run as root (sudo)"
[ "$(hostname)" = "xps9510" ] || die "this script is XPS-9510-specific (hostname=$(hostname))"
[ -d "$XPS_DIR" ] || die "missing $XPS_DIR — run from the repo root"

# --- 1. nftables ----------------------------------------------------------
if [ "$SKIP_EMERGE" -eq 0 ]; then
    if ! command -v nft &>/dev/null; then
        log "[1/8] emerging net-firewall/nftables"
        emerge --quiet net-firewall/nftables || die "emerge nftables failed"
    else
        log "[1/8] nftables already installed: $(nft --version | head -1)"
    fi
else
    log "[1/8] skipped (--skip-emerge)"
fi

# --- 2. ollama binary -----------------------------------------------------
# Ollama ships as .tar.zst and no longer publishes a /latest/ URL alias —
# we must use a versioned URL. Query the GitHub API for the current tag,
# fall back to a known-good pin if the API is rate-limited/unreachable.
# Note: deliberately do NOT call `ollama --version` here — it always probes
# the daemon and emits a warning when none is running. We already know the
# tag from the GitHub API, and tarball provenance is the authoritative source.
OLLAMA_PIN_FALLBACK="v0.30.10"
if [ ! -x /usr/local/bin/ollama ]; then
    command -v zstd &>/dev/null || die "zstd not installed (emerge app-arch/zstd)"
    log "[2/8] resolving latest ollama release tag"
    TAG=$(curl -fsS --max-time 8 https://api.github.com/repos/ollama/ollama/releases/latest \
        2>/dev/null | grep -oE '"tag_name":\s*"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/')
    if [ -z "$TAG" ]; then
        TAG="$OLLAMA_PIN_FALLBACK"
        log "[2/8] GitHub API unreachable — using pinned fallback $TAG"
    else
        log "[2/8] latest is $TAG"
    fi
    URL="https://github.com/ollama/ollama/releases/download/${TAG}/ollama-linux-amd64.tar.zst"
    TMPZST=$(mktemp --suffix=.tar.zst)
    trap 'rm -f "$TMPZST"' EXIT
    log "[2/8] downloading $URL"
    curl --fail --location --progress-bar \
        "$URL" -o "$TMPZST" || die "ollama download failed (URL: $URL)"
    log "[2/8] extracting to /usr/local"
    tar -C /usr/local --zstd -xf "$TMPZST" || die "tar extract failed"
    [ -x /usr/local/bin/ollama ] || die "/usr/local/bin/ollama still missing after extract"
    # Record the version we installed for future runs
    echo "$TAG" > /usr/local/share/ollama-version 2>/dev/null || true
    log "[2/8] installed ollama $TAG to /usr/local/bin/ollama"
else
    PREV_TAG=$(cat /usr/local/share/ollama-version 2>/dev/null || echo "(unknown)")
    log "[2/8] ollama binary already present (installed: $PREV_TAG)"
fi

# --- 3. ollama user -------------------------------------------------------
if ! getent passwd ollama &>/dev/null; then
    log "[3/8] creating system user 'ollama'"
    useradd --system --shell /sbin/nologin --home-dir /usr/share/ollama \
            --create-home --comment "Ollama" ollama || die "useradd failed"
    # Grant access to render/video for GPU
    usermod -a -G video,render ollama 2>/dev/null || true
else
    log "[3/8] user ollama exists (uid $(id -u ollama))"
fi

# --- 4. model storage -----------------------------------------------------
MODEL_DIR=/data/ml-models/ollama
if [ ! -d "$MODEL_DIR" ]; then
    log "[4/8] creating $MODEL_DIR"
    mkdir -p "$MODEL_DIR" || die "mkdir $MODEL_DIR failed"
fi
chown -R ollama:ollama "$MODEL_DIR"
log "[4/8] model dir: $(ls -ld "$MODEL_DIR" | awk '{print $1, $3, $4, $9}')"

# --- 5. install config + service files ------------------------------------
log "[5/8] installing config files"
install -m 0755 "$XPS_DIR/powercap-profile.sh"    /usr/local/sbin/powercap-profile
install -m 0755 "$XPS_DIR/powercap-profile.initd" /etc/init.d/powercap-profile
install -m 0755 "$XPS_DIR/ollama.initd"           /etc/init.d/ollama
install -m 0644 "$XPS_DIR/ollama.confd"           /etc/conf.d/ollama
mkdir -p /etc/nftables
install -m 0644 "$XPS_DIR/nftables-ollama.nft"    /etc/nftables/ollama.nft
install -m 0755 "$XPS_DIR/nftables-ollama.start"  /etc/local.d/nftables-ollama.start

# --- 6. enable + start services ------------------------------------------
log "[6/8] enabling + starting services"
rc-update add powercap-profile default 2>/dev/null || true
rc-update add ollama default            2>/dev/null || true
rc-update add local default             2>/dev/null || true
rc-service powercap-profile start || die "powercap-profile failed to start"
rc-service ollama          restart || die "ollama failed to start"
# Apply firewall now (local.d only runs on next boot)
/etc/local.d/nftables-ollama.start || die "nftables ruleset failed to apply"

# Wait for ollama API to come up
log "[6/8] waiting for ollama API on :11434"
for i in $(seq 1 20); do
    if curl -fsS --max-time 1 http://localhost:11434/api/tags &>/dev/null; then
        log "[6/8] ollama API live after ${i}s"
        break
    fi
    sleep 1
    [ "$i" -eq 20 ] && die "ollama API did not come up within 20s — check /var/log/ollama.log"
done

# --- 7. model pull --------------------------------------------------------
MODEL=qwen2.5:3b-instruct-q4_K_M
if [ "$SKIP_PULL" -eq 0 ]; then
    if curl -fsS http://localhost:11434/api/tags | grep -q "$MODEL"; then
        log "[7/8] model $MODEL already pulled"
    else
        log "[7/8] pulling $MODEL (~2GB, may take a few minutes)"
        sudo -u ollama OLLAMA_MODELS="$MODEL_DIR" \
            /usr/local/bin/ollama pull "$MODEL" || die "model pull failed"
    fi
else
    log "[7/8] skipped (--skip-pull) — run later: sudo -u ollama ollama pull $MODEL"
fi

# --- 8. health check ------------------------------------------------------
log "[8/8] health check"
echo ""
echo "=== Service status ==="
rc-service powercap-profile status
rc-service ollama status
echo ""
echo "=== RAPL ==="
/usr/local/sbin/powercap-profile show
echo ""
echo "=== Ollama tags ==="
curl -fsS http://localhost:11434/api/tags | jq -r '.models[]?.name // "(no models loaded)"'
echo ""
echo "=== Firewall ==="
nft list table inet ollama_fw 2>/dev/null | grep -E 'set|elements|tcp dport' || echo "(table not loaded — check /var/log/nftables-ollama.log)"
echo ""
log "DONE — verifier should be reachable from T5810/asrock at http://10.0.1.51:11434"
