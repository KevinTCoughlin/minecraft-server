#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.script-portability-test"
SERVER_DIR="${WORK_DIR}/server"
BACKUP_DIR="${WORK_DIR}/backups"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

rm -rf "$WORK_DIR"
mkdir -p "$SERVER_DIR/world" "$SERVER_DIR/parkour" "$BACKUP_DIR"
: > "$SERVER_DIR/world/level.dat"
: > "$SERVER_DIR/parkour/level.dat"
: > "$SERVER_DIR/world/data.txt"

for index in 1 2 3; do
    archive="${BACKUP_DIR}/minecraft-backup-20000101-00000${index}.tar.gz"
    tar -czf "$archive" -C "$SERVER_DIR" world
    sleep 1
done

SERVER_DIR="$SERVER_DIR" BACKUP_DIR="$BACKUP_DIR" MAX_BACKUPS=2 \
    "$ROOT_DIR/scripts/backup.sh"

backup_count=$(find "$BACKUP_DIR" -type f -name 'minecraft-backup-*.tar.gz' | wc -l | tr -d ' ')
[[ "$backup_count" == "2" ]]
# Test archives use controlled, whitespace-free names.
# shellcheck disable=SC2012
latest_backup=$(ls -1t "$BACKUP_DIR"/minecraft-backup-*.tar.gz | head -1)
tar -tzf "$latest_backup" | grep -q '^parkour/level.dat$'
tar -tzf "$latest_backup" | grep -q '^world/level.dat$'

SERVER_DIR="$SERVER_DIR" "$ROOT_DIR/scripts/update-paper.sh" --help >/dev/null

if grep -Eq 'mapfile|find .*(-printf|-maxdepth|-mindepth)|sort -V' \
    "$ROOT_DIR/scripts/backup.sh" "$ROOT_DIR/scripts/update-paper.sh"; then
    echo "GNU-only shell construct found" >&2
    exit 1
fi

grep -q 'command -v shasum' "$ROOT_DIR/scripts/update-paper.sh"
echo "Script portability checks passed"
