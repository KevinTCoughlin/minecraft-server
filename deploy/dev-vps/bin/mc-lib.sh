# SPDX-License-Identifier: MIT
# shellcheck shell=bash
# Shared helpers for mc-server-update, mc-plugin-update and mc-backup.
# Sourced, not executed. Runs as the rootless user (mc).

# --- Active world (see mc-world). One world runs at a time; every job that
# sources this file acts on the active one. Per-world settings live in
# ~/.config/mc-world/<name>.env; no state file means "dev".
MC_STATE_DIR="${MC_STATE_DIR:-${HOME}/.local/state/mc-world}"
MC_WORLD_CONF="${MC_WORLD_CONF:-${HOME}/.config/mc-world}"

mc_active_world() {
    local w
    w=$(cat "${MC_STATE_DIR}/active" 2>/dev/null || true)
    [[ "${w}" =~ ^[a-z0-9-]+$ && -f "${MC_WORLD_CONF}/${w}.env" ]] && echo "${w}" || echo dev
}

# mc_load_world NAME [--reset]: set MC_WORLD, MC_UNIT, MC_DATA, ... from NAME's
# env file. --reset forgets the previous world's values first (swap); without
# it exported MC_* overrides win (tests).
mc_load_world() {
    MC_WORLD=$1
    if [[ "${2:-}" == "--reset" ]]; then
        unset MC_UNIT MC_QUADLET MC_DATA MC_BACKUP_DIR MC_BACKUP_EXCLUDES MC_CHUNKY MC_UPDATES MC_WORLD_DESC
    fi
    # shellcheck disable=SC1090
    [[ -f "${MC_WORLD_CONF}/${MC_WORLD}.env" ]] && source "${MC_WORLD_CONF}/${MC_WORLD}.env"
    return 0
}

# Jobs that only make sense for one world call: mc_require_feature MC_UPDATES
mc_require_feature() {
    local var=$1 quiet=${2:-}
    if [[ "${!var:-0}" != 1 ]]; then
        [[ -n "${quiet}" ]] || log "skipping: not applicable to the active world (${MC_WORLD}); it only runs for worlds with ${var}=1"
        exit 0
    fi
}

mc_load_world "${MC_WORLD:-$(mc_active_world)}"

MC_UNIT="${MC_UNIT:-minecraft-dev.service}"
MC_QUADLET="${MC_QUADLET:-${HOME}/.config/containers/systemd/minecraft-dev.container}"
MC_DATA="${MC_DATA:-${HOME}/minecraft-dev/data}"
MC_BACKUP_DIR="${MC_BACKUP_DIR:-${HOME}/backups/minecraft}"
MC_BIN="${MC_BIN:-${HOME}/.local/bin}"
MC_LOCK="${MC_LOCK:-${HOME}/.local/state/minecraft-dev/maintenance.lock}"
MC_START="${MC_UPDATE_START:-0415}"
MC_DEADLINE="${MC_UPDATE_DEADLINE:-0755}"
MC_HEALTH_TRIES="${MC_HEALTH_TRIES:-36}"
MC_HEALTH_SLEEP="${MC_HEALTH_SLEEP:-5}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

log() { printf '%s %s\n' "$(date '+%F %T %Z')" "$*"; }

mc_lock() {
    mkdir -p "$(dirname "${MC_LOCK}")"
    exec 9>>"${MC_LOCK}"
    if ! flock -n 9; then
        log "another maintenance job holds ${MC_LOCK}; exiting"
        exit 0
    fi
}

hhmm_min() { echo $((10#${1:0:2} * 60 + 10#${1:2:2})); }

in_window() {
    local now
    now=$(hhmm_min "$(TZ=America/Los_Angeles date +%H%M)")
    (( now >= $(hhmm_min "${MC_START}") && now <= $(hhmm_min "${MC_DEADLINE}") ))
}

# 0 = idle (humans=0); 1 = busy or unknown.
mc_idle() {
    local out n
    if ! out=$("${MC_BIN}/mc-players" 2>/dev/null); then
        log "player count unknown (${out:-no answer}); treating as busy"
        return 1
    fi
    n=${out#humans=}
    if (( n > 0 )); then
        log "${n} player(s) online; not touching the server"
        return 1
    fi
    log "humans=0"
    return 0
}

mc_running() { systemctl --user is-active --quiet "${MC_UNIT}"; }

# Restart and wait for: unit active (Notify=healthy), RCON answering, and
# "Done (" in a latest.log written after the restart began.
mc_restart_healthy() {
    local since i
    since=$(date +%s)
    if ! systemctl --user restart "${MC_UNIT}"; then
        log "systemctl restart ${MC_UNIT} failed"
        return 1
    fi
    for ((i = 1; i <= MC_HEALTH_TRIES; i++)); do
        if mc_running && "${MC_BIN}/mc-players" >/dev/null 2>&1 \
            && [[ -f "${MC_DATA}/logs/latest.log" ]] \
            && (( $(stat -c %Y "${MC_DATA}/logs/latest.log") >= since )) \
            && grep -q 'Done (.*)! For help' "${MC_DATA}/logs/latest.log"; then
            log "healthy: unit active, RCON answers, log shows Done"
            return 0
        fi
        sleep "${MC_HEALTH_SLEEP}"
    done
    log "not healthy after $((MC_HEALTH_TRIES * MC_HEALTH_SLEEP))s"
    return 1
}
