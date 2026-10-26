#!/bin/bash
# ============================================================================
# migrate-package-env.sh — single-file /etc/portage/package.env -> directory
# ============================================================================
#
#     tools/migrate-package-env.sh              # DRY RUN — show the plan
#     sudo tools/migrate-package-env.sh --apply
#     sudo tools/migrate-package-env.sh --revert
#
# WHY
#
# Portage accepts /etc/portage/package.env as either a single file or a
# directory of files. Both work. The problem is that this repo now has TWO
# tools writing package.env entries, and on a single-file host they collide:
#
#   tools/deploy-portage.sh          deploys machines/<m>/package.env from the
#                                    repo — it OVERWRITES its destination
#   tools/update-system.sh           PORTAGE_WORKAROUNDS appends and later
#                                    removes entries as versions move
#
# On a directory host each owns a separate file (00-notmpfs, 90-workarounds)
# and they never touch each other. On a single-file host they are the same
# file, so deploying the repo copy silently deletes whatever the registry
# installed — on asrock-b550 that is the freerdp ffmpeg CFLAGS fix, which
# would then not come back until the next fetch.
#
# Rather than teach one tool to merge into a file the other owns — which is
# how you get two half-merges and a file nobody can reason about — move the
# machine to the layout where ownership is unambiguous.
#
# Observed layouts, 2026-08-28:  xps-9510 directory, precision-t5810 file,
# asrock-b550 file.
#
# WHAT IT DOES
#
#   /etc/portage/package.env  (file)
#       -> /etc/portage/package.env/00-notmpfs      everything else
#       -> /etc/portage/package.env/90-workarounds  registry-owned lines
#
# Registry-owned means the line references an env file named in
# update-system.sh's PORTAGE_WORKAROUNDS. Those lines are split out so the
# registry can keep removing them on upgrade without touching 00-notmpfs, and
# so deploy-portage can own 00-notmpfs without touching them.
#
# Portage reads the directory's files in sorted order, so 00- before 90- keeps
# the existing precedence. Nothing about which entries apply changes.
# ============================================================================

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PKGENV="${PKGENV:-/etc/portage/package.env}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/kernel-update/config-backups}"
MODE="dryrun"

ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
info() { echo "         $*"; }
fail() { echo "  [FAIL] $*"; }

case "${1:-}" in
    --apply)  MODE="apply" ;;
    --revert) MODE="revert" ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "") ;;
    *) echo "Unknown option: $1"; exit 2 ;;
esac

# ============================================================================
echo "=== 1. Current layout ==="
# ============================================================================
# --revert must survive this check: after a successful migration the path IS a
# directory, so an unconditional early exit here made the undo path unreachable
# exactly when it was needed.
if [[ -d "$PKGENV" && "$MODE" != "revert" ]]; then
    ok "$PKGENV is already a directory — nothing to migrate"
    info "contents: $(ls -1 "$PKGENV" | tr '\n' ' ')"
    exit 0
fi
if [[ -d "$PKGENV" && "$MODE" == "revert" ]]; then
    info "$PKGENV is a directory — reverting to the single-file backup"
fi
if [[ ! -e "$PKGENV" && "$MODE" != "revert" ]]; then
    warn "$PKGENV does not exist at all — nothing to migrate"
    exit 0
fi
[[ -f "$PKGENV" ]] && ok "$PKGENV is a single file ($(grep -cve '^\s*$' "$PKGENV") non-blank lines)"

# ============================================================================
if [[ "$MODE" == "revert" ]]; then
    echo "=== Revert ==="
    [[ $EUID -ne 0 ]] && { fail "run with sudo"; exit 1; }
    newest=$(ls -1t "$BACKUP_DIR"/package.env.*.bak 2>/dev/null | head -1)
    [[ -z "$newest" ]] && { fail "no backup found in $BACKUP_DIR"; exit 1; }
    rm -rf "$PKGENV"
    cp -a "$newest" "$PKGENV"
    ok "restored single-file $PKGENV from $(basename "$newest")"
    exit 0
fi

# ============================================================================
echo
echo "=== 2. Classify lines ==="
# ============================================================================
# Read the registry rather than hardcoding its env-file names, so adding a
# workaround in update-system.sh cannot silently strand a line in the wrong
# file here. If that file is unreadable the registry looks EMPTY, every line
# classifies as deploy-portage's, and the workaround entry ends up in a file
# deploy-portage will overwrite — a silent loss. Refuse instead.
US="$REPO_ROOT/tools/update-system.sh"
if [[ ! -r "$US" ]]; then
    fail "cannot read $US — refusing to classify without the registry."
    info "Run this from a checkout of the repo; an empty registry here would"
    info "put workaround lines in the file deploy-portage overwrites."
    exit 2
fi
mapfile -t WA_ENVS < <(
    sed -n '/^declare -A PORTAGE_WORKAROUNDS=(/,/^)/p' "$US" \
      | grep -v '^[[:space:]]*#' \
      | grep -oE '"[^"]*\|[^"]*"' | cut -d'"' -f2 | cut -d'|' -f1 \
      | xargs -r -n1 basename | sed 's/^portage_env_//'
)
if [[ ${#WA_ENVS[@]} -eq 0 ]]; then
    info "no PORTAGE_WORKAROUNDS entries — everything goes to 00-notmpfs"
else
    info "registry-owned env files: ${WA_ENVS[*]}"
fi

WA_LINES=""
KEEP_LINES=""
while IFS= read -r line; do
    matched=false
    for e in "${WA_ENVS[@]}"; do
        [[ -n "$e" && "$line" == *"$e"* ]] && matched=true && break
    done
    if $matched; then WA_LINES+="$line"$'\n'; else KEEP_LINES+="$line"$'\n'; fi
done < "$PKGENV"

echo
echo "  --- would become 00-notmpfs (deploy-portage owns) ---"
printf '%s' "$KEEP_LINES" | sed 's/^/  /'
echo
echo "  --- would become 90-workarounds (update-system registry owns) ---"
if [[ -n "$WA_LINES" ]]; then printf '%s' "$WA_LINES" | sed 's/^/  /'; else echo "  (none)"; fi

# ============================================================================
echo
if [[ "$MODE" == "dryrun" ]]; then
    echo "=== DRY RUN — nothing changed ==="
    info "Apply with:  sudo $0 --apply"
    exit 0
fi

echo "=== 3. Apply ==="
# ============================================================================
[[ $EUID -ne 0 ]] && { fail "run with sudo"; exit 1; }
mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
cp -a "$PKGENV" "$BACKUP_DIR/package.env.${STAMP}.bak"
ok "original backed up to $BACKUP_DIR/package.env.${STAMP}.bak"

TMP="${PKGENV}.migrating.$$"
mkdir -p "$TMP"
printf '%s' "$KEEP_LINES" > "$TMP/00-notmpfs"
[[ -n "$WA_LINES" ]] && printf '%s' "$WA_LINES" > "$TMP/90-workarounds"
chmod 644 "$TMP"/*
rm -f "$PKGENV"
mv "$TMP" "$PKGENV"
ok "migrated to directory layout"

# ============================================================================
echo
echo "=== 4. Verify ==="
# ============================================================================
F=0
[[ -d "$PKGENV" ]] && ok "$PKGENV is a directory" || { fail "not a directory"; F=1; }
for f in "$PKGENV"/*; do info "  $(basename "$f"): $(grep -cve '^\s*$' "$f") entries"; done

# The point of the migration is that the same atoms still resolve to the same
# env files. Prove it rather than asserting it.
BEFORE=$(sort "$BACKUP_DIR/package.env.${STAMP}.bak" | grep -vE '^\s*(#|$)')
AFTER=$(cat "$PKGENV"/* | sort | grep -vE '^\s*(#|$)')
if [[ "$BEFORE" == "$AFTER" ]]; then
    ok "every directive preserved — before and after are identical"
else
    fail "directive set changed:"
    diff <(echo "$BEFORE") <(echo "$AFTER") | sed 's/^/         /'
    F=$((F+1))
fi

echo
[[ $F -eq 0 ]] && echo "=== DONE ===" || echo "=== $F PROBLEM(S) — undo with: sudo $0 --revert ==="
exit $F
