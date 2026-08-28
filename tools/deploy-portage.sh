#!/bin/bash
# ============================================================================
# deploy-portage.sh — sync tracked portage config from this repo into /etc
# ============================================================================
#
#     tools/deploy-portage.sh                    # DRY RUN — diff repo vs live
#     sudo tools/deploy-portage.sh --apply       # write the files shown above
#     sudo tools/deploy-portage.sh --apply shared   # write only that one pair
#     sudo tools/deploy-portage.sh --revert       # restore the newest backup
#     tools/deploy-portage.sh --machine xps-9510  # override auto-detection
#
# WHY THIS IS NOT A COPY LOOP
#
# The obvious implementation — cp every machines/<m>/package.* into
# /etc/portage/ — is wrong on this repo, and the xps-9510 shows why. Three
# different destination shapes are in use at once:
#
#   shared/package.use             -> /etc/portage/package.use/shared     1:1
#   machines/xps-9510/package.use  -> /etc/portage/package.use/xps9510    1:1
#   shared/package.accept_keywords -> no 'shared' file exists live; its
#                                     contents were hand-merged into the
#                                     per-machine file and into 'custom'
#   shared/package.license         -> same, merged into 'custom'
#
# So for two of the four there is no destination this script can infer, and
# picking one would either create a duplicate-definition file or silently drop
# whatever a human merged by hand. Portage does not error on a contradiction
# between two files in package.use/ — the last one read wins — so a bad guess
# here is a USE flag that quietly changes on the next --changed-use rebuild.
#
# This script therefore only touches pairs that ALREADY EXIST on both sides,
# reports the rest, and refuses to invent a destination. Adding a new mapping
# is a deliberate one-line edit to PAIRS below, made once you have decided
# where the file belongs.
#
# DRY RUN IS THE DEFAULT, for the same reason: /etc/portage files accumulate
# live-only entries (autounmask output, one-off workarounds) that are not in
# the repo. You want to read that diff before overwriting it, every time.
# ============================================================================

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BACKUP_DIR="/var/lib/kernel-update/config-backups"
MODE="dryrun"
MACHINE_OVERRIDE=""
ONLY=""

ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
info() { echo "         $*"; }
fail() { echo "  [FAIL] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   MODE="apply" ;;
        --revert)  MODE="revert" ;;
        --machine) MACHINE_OVERRIDE="${2:-}"; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)        echo "Unknown option: $1"; exit 2 ;;
        *)         ONLY="$1" ;;
    esac
    shift
done

# ============================================================================
echo "=== 1. Machine detection ==="
# ============================================================================

# Hostnames in this fleet drop the dash that the machine directory uses
# (xps9510 vs machines/xps-9510, beelink-minis vs beelink-minis). Comparing
# both sides with dashes stripped covers that without a lookup table that
# would then need keeping in sync with update-system.sh's MACHINES registry.
#
# NOTE: tools/update-system.sh's registry records this machine's hostname as
# "xps-9510", which does not match the actual hostname "xps9510" — its
# hostname match therefore misses and it detects via the DMI fallback instead.
# Harmless today, but it means that registry field is untested. Worth fixing
# there separately.
MACHINE=""
if [[ -n "$MACHINE_OVERRIDE" ]]; then
    MACHINE="$MACHINE_OVERRIDE"
    [[ -d "$REPO_ROOT/machines/$MACHINE" ]] || { fail "No such machine dir: machines/$MACHINE"; exit 2; }
else
    HOST=$(hostname)
    HOST_N="${HOST//-/}"
    for d in "$REPO_ROOT"/machines/*/; do
        name=$(basename "$d")
        if [[ "${name//-/}" == "$HOST_N" ]]; then MACHINE="$name"; break; fi
    done
fi

if [[ -z "$MACHINE" ]]; then
    fail "Could not match hostname '$(hostname)' to a machines/ directory."
    info "Pass it explicitly:  $0 --machine <name>"
    info "Available: $(cd "$REPO_ROOT/machines" && echo */ | tr -d '/')"
    exit 2
fi
ok "machine: $MACHINE (hostname $(hostname))"

# ============================================================================
# Mapping table: <repo path>|<live path>
# ============================================================================
# Only 1:1 pairs belong here. If a repo file's contents were hand-merged into
# a differently-named live file, leave it out — the drift report below will
# list it as unmapped rather than pretend it is deployed.
LIVE_NAME="$(hostname)"
PAIRS=(
    "shared/package.use|/etc/portage/package.use/shared"
    "machines/$MACHINE/package.use|/etc/portage/package.use/$LIVE_NAME"
    "machines/$MACHINE/package.accept_keywords|/etc/portage/package.accept_keywords/$LIVE_NAME"
    # package.env destination is NOT the hostname. The live file is 00-notmpfs
    # -- numbered so it sorts before cross-i686-elf and 90-workarounds, which
    # portage reads in order. Mapping this to $LIVE_NAME warned about a file
    # that should not exist while ignoring the one that does.
    "machines/$MACHINE/package.env|/etc/portage/package.env/00-notmpfs"
)
# Tracked in the repo but with no inferable destination — reported, never written.
UNMAPPED=(
    "shared/package.accept_keywords"
    "shared/package.license"
)

# ============================================================================
if [[ "$MODE" == "revert" ]]; then
    echo "=== Revert ==="
    [[ $EUID -ne 0 ]] && { fail "run with sudo"; exit 1; }
    n=0
    for pair in "${PAIRS[@]}"; do
        live="${pair#*|}"
        newest=$(ls -1t "$BACKUP_DIR/$(basename "$live")".*.bak 2>/dev/null | head -1)
        if [[ -n "$newest" ]]; then
            cp -a "$newest" "$live"
            ok "$live <- $(basename "$newest")"
            n=$((n+1))
        fi
    done
    [[ $n -eq 0 ]] && info "no backups found in $BACKUP_DIR"
    exit 0
fi

# ============================================================================
echo
echo "=== 2. Drift: repo vs live ==="
# ============================================================================
CHANGED=()
for pair in "${PAIRS[@]}"; do
    repo="$REPO_ROOT/${pair%%|*}"
    live="${pair#*|}"
    label=$(basename "$live")

    [[ -n "$ONLY" && "$label" != "$ONLY" ]] && continue

    if [[ ! -f "$repo" ]]; then
        info "$(basename "$repo") — not tracked for this machine, skipped"
        continue
    fi
    if [[ ! -f "$live" ]]; then
        # A missing destination is exactly the guess this script refuses to
        # make: creating it may shadow settings that live elsewhere today.
        warn "$live does not exist — NOT creating it."
        info "If that is genuinely where ${pair%%|*} belongs, create it once by"
        info "hand, then this script will keep it in sync."
        continue
    fi
    if diff -q "$repo" "$live" >/dev/null 2>&1; then
        ok "$label — in sync"
    else
        echo
        echo "  --- drift: $label ---"
        diff -u "$live" "$repo" | sed 's/^/  /'
        echo
        CHANGED+=("$repo|$live")
    fi
done

if [[ ${#UNMAPPED[@]} -gt 0 && -z "$ONLY" ]]; then
    echo
    for u in "${UNMAPPED[@]}"; do
        info "unmapped (no 1:1 destination): $u"
    done
fi

# ============================================================================
echo
if [[ ${#CHANGED[@]} -eq 0 ]]; then
    echo "=== Nothing to do — repo and live agree ==="
    exit 0
fi

if [[ "$MODE" == "dryrun" ]]; then
    echo "=== DRY RUN — ${#CHANGED[@]} file(s) would change ==="
    info "Read the diffs above. The '+' lines are what the repo would install."
    info "Apply with:  sudo $0 --apply"
    exit 0
fi

echo "=== 3. Apply ==="
# ============================================================================
[[ $EUID -ne 0 ]] && { fail "run with sudo"; exit 1; }
mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
for pair in "${CHANGED[@]}"; do
    repo="${pair%%|*}"; live="${pair#*|}"
    cp -a "$live" "$BACKUP_DIR/$(basename "$live").${STAMP}.bak"
    install -m 644 "$repo" "$live"
    ok "$(basename "$live") — written (backup .${STAMP}.bak)"
done

# ============================================================================
echo
echo "=== 4. Verify ==="
# ============================================================================
F=0
for pair in "${CHANGED[@]}"; do
    repo="${pair%%|*}"; live="${pair#*|}"
    if diff -q "$repo" "$live" >/dev/null 2>&1; then
        ok "$(basename "$live") — matches repo"
    else
        fail "$(basename "$live") — still differs"; F=$((F+1))
    fi
done

# A USE change only takes effect on a rebuild. Say so with real numbers rather
# than leaving the reader to wonder whether anything still needs emerging.
if command -v emerge >/dev/null 2>&1; then
    echo
    info "Checking whether any installed package now needs a USE rebuild..."
    PKGS=$(emerge -p --changed-use --deep @world 2>/dev/null | grep -c '^\[ebuild' || true)
    if [[ "$PKGS" -gt 0 ]]; then
        warn "$PKGS package(s) would rebuild for changed USE flags."
        info "Review with:  emerge -pv --changed-use --deep @world"
    else
        ok "no rebuilds needed — installed packages already match these flags"
    fi
fi

echo
[[ $F -eq 0 ]] && echo "=== DONE ===" || echo "=== $F PROBLEM(S) — undo with: sudo $0 --revert ==="
exit $F
