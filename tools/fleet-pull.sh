#!/bin/bash
# ============================================================================
# fleet-pull.sh — bring every reachable machine's checkout up to origin/main
# ============================================================================
#
#     tools/fleet-pull.sh              # pull every reachable target
#     tools/fleet-pull.sh --check      # report only, pull nothing
#     tools/fleet-pull.sh asrock       # one target
#
# Needs no root anywhere: `git pull` is an unprivileged operation, so this is
# the one fleet-wide action that can be driven end to end over ssh. The
# privileged half of any change — deploy-portage --apply, migrate-package-env
# --apply, update-system — still has to be run by hand on each box.
#
# SAFETY
#
#   --ff-only          never creates a merge commit; a diverged checkout is
#                      reported and skipped rather than silently merged
#   dirty tree         skipped, with the modified files listed. Local edits on
#                      a machine are usually drift worth reading before it is
#                      buried under a pull.
#   unreachable host   reported, not an error. Half this fleet is powered off
#                      at any given time and that is normal.
#
# NOT REACHABLE IS NOT THE SAME AS DOWN
#
# This fleet spans several sites on different subnets. Machines at a remote
# site are typically powered on and perfectly healthy, just not routable from
# the local one without a VPN. Only one machine in the list is normally powered
# off.
#
# The summary line therefore says "not reachable from here", never "down". A
# sweep that reports healthy machines as dead is a sweep people learn to
# ignore, and this one is meant to be run on every push.
#
# TARGETS ARE SSH ALIASES, NOT MACHINE NAMES
#
# There are three naming schemes in play — repo directories (asrock-b550),
# real hostnames (asrock-b550, xps9510) and /etc/hosts aliases (Asrock,
# T5810) — and only the aliases resolve from the xps-9510 today. The canonical
# repo names do not, so this table maps one to the other explicitly rather
# than pretending they agree. Fixing that properly means DHCP reservations and
# real DNS; see shared/fleet-sweep-checklist.md.
# ============================================================================

set -uo pipefail

REPO_PATH="${REPO_PATH:-ai/gentoo-machines}"
# Public repo — usable as a keyless read-only fallback, see header.
HTTPS_URL="https://github.com/cdnwetzel/gentoo-machines.git"
MODE="pull"

# ssh-target|repo machine name|where it lives
TARGETS=(
    "asrock|asrock-b550|local subnet"
    "t5810|precision-t5810|local subnet"
    "beelink-minis|beelink-minis|remote site - VPN required"
    "opti3090|optiplex-3090|remote site - VPN required"
    "surface-pro-6|surface-pro-6|local, normally powered off"
    "nuc11|nuc11|not installed - runs another distro today"
)

ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
info() { echo "         $*"; }
skip() { echo "  [SKIP] $*"; }

ONLY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check" ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "Unknown option: $1"; exit 2 ;;
        *)  ONLY="$1" ;;
    esac
    shift
done

LOCAL_HEAD=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --short HEAD 2>/dev/null)
echo "=== Local HEAD: ${LOCAL_HEAD:-unknown} ==="
echo

REACHED=0; PULLED=0; SKIPPED=0; DOWN=0
for entry in "${TARGETS[@]}"; do
    target="${entry%%|*}"; rest="${entry#*|}"
    machine="${rest%%|*}"; where="${rest#*|}"
    [[ -n "$ONLY" && "$target" != "$ONLY" && "$machine" != "$ONLY" ]] && continue

    printf '%-16s ' "$target"

    # BatchMode so a host that would prompt for a password fails fast instead
    # of hanging the whole sweep waiting on stdin nobody is watching.
    if ! out=$(timeout 25 ssh -o BatchMode=yes -o ConnectTimeout=6 "$target" "
        cd ~/${REPO_PATH} 2>/dev/null || { echo 'NOREPO'; exit 0; }
        d=\$(git status --porcelain)
        if [[ -n \"\$d\" ]]; then echo 'DIRTY'; echo \"\$d\"; exit 0; fi
        if [[ '$MODE' == 'check' ]]; then
            git fetch -q origin 2>/dev/null || git fetch -q '$HTTPS_URL' main 2>/dev/null
            r=\$(git rev-parse --short origin/main 2>/dev/null || git rev-parse --short FETCH_HEAD)
            echo \"CHECK \$(git rev-parse --short HEAD) \$r\"
            exit 0
        fi
        if git pull --ff-only -q 2>/dev/null; then
            echo \"PULLED \$(git rev-parse --short HEAD)\"
        elif git pull --ff-only -q '$HTTPS_URL' main 2>/dev/null; then
            echo \"PULLEDHTTPS \$(git rev-parse --short HEAD)\"
        else
            echo 'DIVERGED'
        fi
    " 2>/dev/null); then
        echo "not reachable from here  [${where}]"; DOWN=$((DOWN+1)); continue
    fi
    REACHED=$((REACHED+1))

    case "$out" in
        NOREPO*)   echo; warn "no checkout at ~/${REPO_PATH}"; SKIPPED=$((SKIPPED+1)) ;;
        DIRTY*)    echo; warn "local changes — not pulling. Read them first:"
                   echo "$out" | tail -n +2 | sed 's/^/           /'; SKIPPED=$((SKIPPED+1)) ;;
        DIVERGED*) echo; warn "diverged from origin/main — needs a human"; SKIPPED=$((SKIPPED+1)) ;;
        CHECK*)    read -r _ head remote <<< "$out"
                   if [[ "$head" == "$remote" ]]; then echo "up to date ($head)"
                   else echo "BEHIND — local $head, origin $remote"; fi ;;
        PULLEDHTTPS*) read -r _ head <<< "$out"
                   echo "-> $head (via https — no deploy key on this host)"
                   PULLED=$((PULLED+1)) ;;
        PULLED*)   read -r _ head <<< "$out"
                   if [[ "$head" == "$LOCAL_HEAD" ]]; then echo "-> $head (matches here)"
                   else echo "-> $head"; fi
                   PULLED=$((PULLED+1)) ;;
        *)         echo; warn "unexpected: $out"; SKIPPED=$((SKIPPED+1)) ;;
    esac
done

echo
echo "=== ${REACHED} reachable, ${PULLED} pulled, ${SKIPPED} skipped, ${DOWN} not reachable ==="
[[ $DOWN -gt 0 ]] && info "Not reachable != down. Remote-site machines need the VPN, not a power button."
[[ $SKIPPED -gt 0 ]] && info "Skipped machines need a look before they will pull."
exit 0
