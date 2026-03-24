#!/usr/bin/env bash
# claude-backup.sh — Cross-platform background backup for ~/.claude
# Supports: Windows (Git Bash), WSL (Ubuntu), macOS, Linux
# Usage: claude-backup.sh {start|stop|status|run-once|list}

# Note: -e (errexit) is intentionally omitted. This script uses explicit error
# checking throughout, and many code paths rely on non-zero exit codes from
# robocopy (exit codes 0-7 = success), bash arithmetic ((var++)), and
# intentional || true guards in the daemon loop.
set -uo pipefail
umask 077

# ─── Defaults (override via environment variables) ────────────────────────────
CLAUDE_BACKUP_SOURCE="${CLAUDE_BACKUP_SOURCE:-$HOME/.claude}"
CLAUDE_BACKUP_DIR="${CLAUDE_BACKUP_DIR:-$HOME/.claude-backups}"
CLAUDE_BACKUP_INTERVAL="${CLAUDE_BACKUP_INTERVAL:-300}"
CLAUDE_BACKUP_SNAPSHOT_INTERVAL="${CLAUDE_BACKUP_SNAPSHOT_INTERVAL:-3600}"
CLAUDE_BACKUP_MAX_SNAPSHOTS="${CLAUDE_BACKUP_MAX_SNAPSHOTS:-48}"

# ─── Input validation ────────────────────────────────────────────────────────
validate_positive_int() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
        echo "ERROR: $name must be a positive integer, got: '$value'" >&2
        exit 1
    fi
}

validate_positive_int "CLAUDE_BACKUP_INTERVAL" "$CLAUDE_BACKUP_INTERVAL"
validate_positive_int "CLAUDE_BACKUP_SNAPSHOT_INTERVAL" "$CLAUDE_BACKUP_SNAPSHOT_INTERVAL"
validate_positive_int "CLAUDE_BACKUP_MAX_SNAPSHOTS" "$CLAUDE_BACKUP_MAX_SNAPSHOTS"

validate_path() {
    local name="$1" value="$2"
    if [[ -z "$value" ]]; then
        echo "ERROR: $name must not be empty" >&2
        exit 1
    fi
    if [[ "$value" == *$'\n'* ]] || [[ "$value" == *$'\r'* ]]; then
        echo "ERROR: $name contains invalid characters" >&2
        exit 1
    fi
}

validate_path "CLAUDE_BACKUP_SOURCE" "$CLAUDE_BACKUP_SOURCE"
validate_path "CLAUDE_BACKUP_DIR" "$CLAUDE_BACKUP_DIR"

# ─── Derived paths ────────────────────────────────────────────────────────────
MIRROR_DIR="$CLAUDE_BACKUP_DIR/current"
SNAPSHOT_DIR="$CLAUDE_BACKUP_DIR/snapshots"
LOG_DIR="$CLAUDE_BACKUP_DIR/logs"
LOG_FILE="$LOG_DIR/backup.log"
PID_FILE="$CLAUDE_BACKUP_DIR/claude-backup.pid"
LOCK_DIR="$CLAUDE_BACKUP_DIR/.lock"

# ─── Exclude patterns ────────────────────────────────────────────────────────
EXCLUDE_PATTERNS=(
    ".git"
    "cache"
    "debug"
    "backups"
    "shell-snapshots"
    "statsig"
    "telemetry"
    ".update.lock"
    "worktrees"
)

# ─── Platform detection ──────────────────────────────────────────────────────
PLATFORM=""
HAS_RSYNC=false
HAS_ROBOCOPY=false

detect_platform() {
    case "$OSTYPE" in
        msys*|cygwin*|MSYS*|CYGWIN*)
            PLATFORM="gitbash"
            ;;
        darwin*)
            PLATFORM="macos"
            ;;
        *)
            if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
    esac

    if command -v rsync &>/dev/null; then
        HAS_RSYNC=true
    fi
    if command -v robocopy &>/dev/null; then
        HAS_ROBOCOPY=true
    fi
}

# ─── Utility functions ───────────────────────────────────────────────────────
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" >> "$LOG_FILE" 2>/dev/null
}

get_mtime() {
    if [[ "$PLATFORM" == "macos" ]]; then
        stat -f %m "$1" 2>/dev/null
    else
        stat -c %Y "$1" 2>/dev/null
    fi
}

get_size() {
    if [[ "$PLATFORM" == "macos" ]]; then
        stat -f %z "$1" 2>/dev/null
    else
        stat -c %s "$1" 2>/dev/null
    fi
}

rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(get_size "$LOG_FILE")
        if [[ -n "$size" ]] && (( size > 10485760 )); then  # 10MB
            mv "$LOG_FILE" "$LOG_FILE.1"
            log "Log rotated"
        fi
    fi
}

# ─── Lock functions (mkdir-based, cross-platform) ────────────────────────────
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi
    # Check for stale lock
    local lock_pid
    lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        return 1  # Lock held by a live process
    fi
    # Stale lock — reclaim
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        return 0
    fi
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

# ─── Backup: rsync-based sync ───────────────────────────────────────────────
sync_with_rsync() {
    local src="$1" dst="$2"
    local -a exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=("--exclude=$pattern")
    done

    rsync -a --delete "${exclude_args[@]}" "$src/" "$dst/" 2>&1
}

# ─── Backup: robocopy-based sync (Windows native, fast) ─────────────────────
sync_with_robocopy() {
    local src="$1" dst="$2"

    # Convert Git Bash paths to Windows paths
    local win_src win_dst
    win_src=$(cygpath -w "$src")
    win_dst=$(cygpath -w "$dst")

    # Build exclude lists: files vs directories
    local -a xd_args=()
    local -a xf_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        case "$pattern" in
            *.lock|*.tmp|*.log)  # Known file extensions
                xf_args+=("$pattern")
                ;;
            *)  # Everything else is a directory
                xd_args+=("$pattern")
                ;;
        esac
    done

    # /MIR = mirror (sync + delete), /NFL /NDL /NJH /NJS = quiet output
    # /R:1 /W:1 = retry once, wait 1s (avoid hanging on locked files)
    # MSYS_NO_PATHCONV=1 prevents Git Bash from converting /flags to paths
    local -a cmd=(robocopy "$win_src" "$win_dst" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS)
    if (( ${#xd_args[@]} > 0 )); then
        cmd+=(/XD "${xd_args[@]}")
    fi
    if (( ${#xf_args[@]} > 0 )); then
        cmd+=(/XF "${xf_args[@]}")
    fi

    local output rc
    output=$(MSYS_NO_PATHCONV=1 "${cmd[@]}" 2>&1) || true
    rc=$?

    # Robocopy exit codes: 0-7 = success, 8+ = error
    if (( rc >= 8 )); then
        echo "ERROR: robocopy failed (rc=$rc): $output"
        return 1
    fi
    echo "$output"
    return 0
}

# ─── Backup: cp-based incremental sync (final fallback) ─────────────────────
should_exclude() {
    local rel_path="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        case "$rel_path" in
            "$pattern"|"$pattern/"*)
                return 0
                ;;
        esac
    done
    return 1
}

sync_with_cp() {
    local src="$1" dst="$2"
    local copied=0 deleted=0 skipped=0

    # Phase 1: Copy new and changed files
    while IFS= read -r -d '' src_file; do
        local rel_path="${src_file#$src/}"
        should_exclude "$rel_path" && continue

        local dst_file="$dst/$rel_path"

        if [[ ! -f "$dst_file" ]]; then
            mkdir -p "$(dirname "$dst_file")"
            cp -p "$src_file" "$dst_file" 2>/dev/null && ((copied++)) || true
        else
            local src_mt dst_mt src_sz dst_sz
            src_mt=$(get_mtime "$src_file")
            dst_mt=$(get_mtime "$dst_file")
            src_sz=$(get_size "$src_file")
            dst_sz=$(get_size "$dst_file")
            if [[ "$src_mt" != "$dst_mt" || "$src_sz" != "$dst_sz" ]]; then
                cp -p "$src_file" "$dst_file" 2>/dev/null && ((copied++)) || true
            else
                ((skipped++))
            fi
        fi
    done < <(find "$src" -type f -print0 2>/dev/null)

    # Phase 2: Remove files in destination that no longer exist in source
    if [[ -d "$dst" ]]; then
        while IFS= read -r -d '' dst_file; do
            local rel_path="${dst_file#$dst/}"
            if [[ ! -e "$src/$rel_path" ]]; then
                rm -f "$dst_file" && ((deleted++)) || true
            fi
        done < <(find "$dst" -type f -print0 2>/dev/null)
        find "$dst" -type d -empty -delete 2>/dev/null || true
    fi

    echo "copied=$copied deleted=$deleted skipped=$skipped"
}

# ─── Backup: main sync function ─────────────────────────────────────────────
sync_mirror() {
    local src="$CLAUDE_BACKUP_SOURCE"
    local dst="$MIRROR_DIR"

    if [[ ! -d "$src" ]]; then
        log "ERROR: Source directory not found: $src"
        return 1
    fi

    mkdir -p "$dst"

    local start_time result method
    start_time=$(date +%s)

    if [[ "$HAS_RSYNC" == true ]]; then
        method="rsync"
        result=$(sync_with_rsync "$src" "$dst" 2>&1)
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            log "ERROR: rsync failed (rc=$rc): $result"
            return 1
        fi
    elif [[ "$HAS_ROBOCOPY" == true ]]; then
        method="robocopy"
        result=$(sync_with_robocopy "$src" "$dst" 2>&1)
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            log "ERROR: robocopy failed: $result"
            return 1
        fi
    else
        method="cp"
        result=$(sync_with_cp "$src" "$dst" 2>&1)
    fi

    local elapsed=$(( $(date +%s) - start_time ))
    log "Mirror sync ($method) completed in ${elapsed}s${result:+ — $result}"
    return 0
}

# ─── Snapshot functions ──────────────────────────────────────────────────────
get_snapshot_files() {
    local -n _result=$1
    _result=()
    shopt -s nullglob
    _result=("$SNAPSHOT_DIR"/*.tar.gz)
    shopt -u nullglob
}

get_latest_snapshot_time() {
    local -a snaps
    get_snapshot_files snaps
    if (( ${#snaps[@]} > 0 )); then
        # Filenames are YYYYMMDD_HHMMSS.tar.gz, so lexicographic sort = chronological
        local latest="${snaps[-1]}"
        get_mtime "$latest"
    else
        echo "0"
    fi
}

maybe_create_snapshot() {
    local now last_time elapsed
    now=$(date +%s)
    last_time=$(get_latest_snapshot_time)
    elapsed=$((now - last_time))

    if (( elapsed >= CLAUDE_BACKUP_SNAPSHOT_INTERVAL )); then
        create_snapshot
    fi
}

create_snapshot() {
    shopt -s nullglob dotglob
    local -a mirror_contents=("$MIRROR_DIR"/*)
    shopt -u nullglob dotglob
    if [[ ! -d "$MIRROR_DIR" ]] || (( ${#mirror_contents[@]} == 0 )); then
        log "WARN: Mirror directory empty, skipping snapshot"
        return 1
    fi

    mkdir -p "$SNAPSHOT_DIR"
    local name
    name="$(date +%Y%m%d_%H%M%S).tar.gz"
    local snap_path="$SNAPSHOT_DIR/$name"

    if tar -czf "$snap_path" -C "$MIRROR_DIR" . 2>/dev/null; then
        chmod 600 "$snap_path"
        local size
        size=$(get_size "$snap_path")
        log "Snapshot created: $name ($(( size / 1024 ))KB)"
        return 0
    else
        log "ERROR: Failed to create snapshot"
        rm -f "$snap_path"
        return 1
    fi
}

cleanup_snapshots() {
    local -a snaps
    get_snapshot_files snaps
    local count=${#snaps[@]}
    if (( count > CLAUDE_BACKUP_MAX_SNAPSHOTS )); then
        local to_delete=$((count - CLAUDE_BACKUP_MAX_SNAPSHOTS))
        local i
        for (( i = 0; i < to_delete; i++ )); do
            rm -f "${snaps[$i]}"
            log "Deleted old snapshot: $(basename "${snaps[$i]}")"
        done
    fi
}

# ─── Daemon ──────────────────────────────────────────────────────────────────
daemon_cleanup() {
    release_lock
    rm -f "$PID_FILE"
    log "Daemon stopped (PID $$)"
    exit 0
}

daemon_loop() {
    log "Daemon started (PID $$, interval=${CLAUDE_BACKUP_INTERVAL}s, platform=$PLATFORM)"
    trap daemon_cleanup SIGTERM SIGINT SIGHUP

    while true; do
        rotate_log

        if acquire_lock; then
            sync_mirror || true
            maybe_create_snapshot || true
            cleanup_snapshots || true
            release_lock
        else
            log "WARN: Could not acquire lock, skipping this cycle"
        fi

        sleep "$CLAUDE_BACKUP_INTERVAL" &
        wait $! 2>/dev/null || true  # Allow trap to interrupt sleep
    done
}

# ─── Process management helpers ──────────────────────────────────────────────
is_daemon_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
        # Stale PID file
        rm -f "$PID_FILE"
    fi
    return 1
}

# ─── Commands ────────────────────────────────────────────────────────────────
cmd_start() {
    local pid
    if pid=$(is_daemon_running); then
        echo "Backup daemon is already running (PID $pid)"
        return 1
    fi

    if [[ ! -d "$CLAUDE_BACKUP_SOURCE" ]]; then
        echo "ERROR: Source directory not found: $CLAUDE_BACKUP_SOURCE"
        return 1
    fi

    # Create directory structure
    mkdir -p "$MIRROR_DIR" "$SNAPSHOT_DIR" "$LOG_DIR"
    chmod 700 "$CLAUDE_BACKUP_DIR"

    echo "Running initial backup..."
    log "=== Backup service starting ==="

    if sync_mirror; then
        echo "Initial backup completed."
    else
        echo "WARNING: Initial backup had errors. Check $LOG_FILE"
    fi

    # Launch daemon in background
    CLAUDE_BACKUP_DAEMON_INTERNAL=1 nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"

    # Verify it started
    sleep 1
    if kill -0 "$daemon_pid" 2>/dev/null; then
        echo "Backup daemon started (PID $daemon_pid)"
        echo "  Source:   $CLAUDE_BACKUP_SOURCE"
        echo "  Backup:   $CLAUDE_BACKUP_DIR"
        echo "  Interval: ${CLAUDE_BACKUP_INTERVAL}s"
        echo "  Log:      $LOG_FILE"
    else
        rm -f "$PID_FILE"
        echo "ERROR: Daemon failed to start. Check $LOG_FILE"
        return 1
    fi
}

cmd_stop() {
    local pid
    if ! pid=$(is_daemon_running); then
        echo "Backup daemon is not running."
        return 1
    fi

    echo "Stopping backup daemon (PID $pid)..."
    kill -TERM "$pid" 2>/dev/null

    # Wait up to 5 seconds
    local waited=0
    while (( waited < 5 )); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE"
            echo "Daemon stopped."
            return 0
        fi
        sleep 1
        ((waited++))
    done

    # Force kill
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    release_lock
    echo "Daemon force-stopped."
}

cmd_status() {
    local pid
    if pid=$(is_daemon_running); then
        echo "Status:   RUNNING (PID $pid)"
    else
        echo "Status:   STOPPED"
    fi

    echo "Platform: $PLATFORM (rsync: $HAS_RSYNC, robocopy: $HAS_ROBOCOPY)"
    echo "Source:   $CLAUDE_BACKUP_SOURCE"
    echo "Backup:   $CLAUDE_BACKUP_DIR"
    echo "Interval: ${CLAUDE_BACKUP_INTERVAL}s"

    # Last backup time
    if [[ -d "$MIRROR_DIR" ]]; then
        local mirror_mtime
        mirror_mtime=$(get_mtime "$MIRROR_DIR")
        if [[ -n "$mirror_mtime" ]] && (( mirror_mtime > 0 )); then
            if [[ "$PLATFORM" == "macos" ]]; then
                echo "Last backup: $(date -r "$mirror_mtime" '+%Y-%m-%d %H:%M:%S')"
            else
                echo "Last backup: $(date -d "@$mirror_mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
            fi
        fi
    else
        echo "Last backup: never"
    fi

    # Snapshot count
    local snap_count=0
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        local -a snaps
        get_snapshot_files snaps
        snap_count=${#snaps[@]}
    fi
    echo "Snapshots: $snap_count"

    # Disk usage
    if [[ -d "$CLAUDE_BACKUP_DIR" ]]; then
        local du_output
        du_output=$(du -sh "$CLAUDE_BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "Disk used: ${du_output:-unknown}"
    fi
}

cmd_run_once() {
    if [[ ! -d "$CLAUDE_BACKUP_SOURCE" ]]; then
        echo "ERROR: Source directory not found: $CLAUDE_BACKUP_SOURCE"
        return 1
    fi

    mkdir -p "$MIRROR_DIR" "$SNAPSHOT_DIR" "$LOG_DIR"
    chmod 700 "$CLAUDE_BACKUP_DIR"

    if ! acquire_lock; then
        echo "ERROR: Could not acquire lock. Is another backup running?"
        return 1
    fi

    echo "Running backup..."
    if sync_mirror; then
        echo "Mirror sync completed."
    else
        echo "ERROR: Mirror sync failed."
        release_lock
        return 1
    fi

    maybe_create_snapshot && echo "Snapshot check done." || true
    cleanup_snapshots

    release_lock
    echo "Backup completed."
}

cmd_list() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        echo "No snapshots found."
        return 0
    fi

    local -a snaps
    get_snapshot_files snaps
    local count=${#snaps[@]}
    if (( count == 0 )); then
        echo "No snapshots found."
        return 0
    fi

    echo "Available snapshots ($count):"
    echo "──────────────────────────────────────────"
    local f
    for f in "${snaps[@]}"; do
        local name size
        name=$(basename "$f")
        size=$(get_size "$f")
        if [[ -n "$size" ]]; then
            printf "  %-28s %sKB\n" "$name" "$((size / 1024))"
        else
            printf "  %s\n" "$name"
        fi
    done
}

cmd_usage() {
    cat <<'EOF'
Usage: claude-backup.sh <command>

Commands:
  start      Start the background backup daemon
  stop       Stop the backup daemon
  status     Show backup status
  run-once   Run a single backup (no daemon)
  list       List available snapshots

Environment variables:
  CLAUDE_BACKUP_SOURCE              Source directory (default: ~/.claude)
  CLAUDE_BACKUP_DIR                 Backup directory (default: ~/.claude-backups)
  CLAUDE_BACKUP_INTERVAL            Sync interval in seconds (default: 300)
  CLAUDE_BACKUP_SNAPSHOT_INTERVAL   Snapshot interval in seconds (default: 3600)
  CLAUDE_BACKUP_MAX_SNAPSHOTS       Max snapshots to keep (default: 48)
EOF
}

# ─── Main ────────────────────────────────────────────────────────────────────
detect_platform

case "${1:-}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    run-once)
        cmd_run_once
        ;;
    list)
        cmd_list
        ;;
    _daemon)
        # Internal: invoked by 'start' command via nohup. Not intended for direct use.
        if [[ -z "${CLAUDE_BACKUP_DAEMON_INTERNAL:-}" ]]; then
            echo "ERROR: _daemon is an internal command. Use 'start' instead." >&2
            exit 1
        fi
        daemon_loop
        ;;
    *)
        cmd_usage
        exit 1
        ;;
esac
