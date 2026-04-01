# Claude Local Backup Manager

A cross-platform background script that automatically backs up the `~/.claude` directory every 5 minutes.

## Supported Environments

- Windows (Git Bash)
- WSL (Ubuntu)
- macOS
- Linux

## Quick Start / Usage

```bash
./claude-backup.sh start      # Start background daemon
./claude-backup.sh stop       # Stop daemon
./claude-backup.sh status     # Check status
./claude-backup.sh run-once   # Run backup once
./claude-backup.sh list       # List snapshots
```

## How It Works

### Two-Stage Backup

1. **Mirror Synchronization (every 5 mins)**: Incremental copy `~/.claude` → `~/.claude-backups/current/`
2. **Snapshots (every 1 hour)**: Create a tar.gz archive of the mirror, retaining the last 168 snapshots.

### Sync Engine (Auto-detected)

| Priority | Engine | Environment |
|----------|--------|-------------|
| 1 | rsync | WSL, macOS, Linux |
| 2 | robocopy | Windows (Git Bash) |
| 3 | cp (incremental) | fallback |

### Daemon Management

- `nohup` + sleep loop without relying on `cron`
- Uses a PID file to track processes
- Adopts `mkdir` based locking to prevent concurrent executions
- Safe termination sequence: `SIGTERM` → wait 5 seconds → `SIGKILL`

## Backup Directory Structure

```text
~/.claude-backups/
├── current/                  # Latest mirror
├── snapshots/                # tar.gz archives by timestamp
│   ├── 20260325_043653.tar.gz
│   └── ...
├── logs/
│   └── backup.log            # Execution logs
└── claude-backup.pid         # Daemon PID file
```

## Backup Targets

All contents of `~/.claude` are backed up **except** the following excluded patterns:

| Excluded Pattern | Reason |
|------------------|--------|
| `.git` | Version control metadata |
| `cache`, `debug` | Regenerable temporary data |
| `backups`, `shell-snapshots` | Redundant backup data |
| `statsig`, `telemetry` | Analytics / telemetry data |
| `worktrees` | Git worktree temporary copies |
| `.update.lock` | Transient lock file |

This means files like `config.json`, `settings.json`, `.credentials.json`, `MEMORY.md`, `projects/`, `plans/`, `todos/`, `skills/`, and all other non-excluded content are included automatically.

## Configuration (Environment Variables)

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `CLAUDE_BACKUP_SOURCE` | `~/.claude` | Source directory |
| `CLAUDE_BACKUP_DIR` | `~/.claude-backups` | Backup storage destination |
| `CLAUDE_BACKUP_INTERVAL` | `300` | Sync interval (seconds) |
| `CLAUDE_BACKUP_SNAPSHOT_INTERVAL` | `3600` | Snapshot interval (seconds) |
| `CLAUDE_BACKUP_MAX_SNAPSHOTS` | `168` | Maximum number of snapshots to retain |

### Example: 1-minute interval, custom backup path

```bash
CLAUDE_BACKUP_INTERVAL=60 CLAUDE_BACKUP_DIR=/mnt/backup/.claude-backups ./claude-backup.sh start
```

## Known Limitations

- **Git Bash signal handling**: On some older Git Bash / MSYS2 versions, signal delivery (`SIGTERM`, `SIGHUP`) may be delayed or unreliable. The `stop` command includes a 5-second timeout with forced termination as a fallback.
- **Backup storage encryption**: The backup directory is protected with `chmod 700` (owner-only access), but files are not encrypted at rest. For sensitive environments, use an encrypted filesystem for the backup destination.

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on how to get started.

## License

This project is licensed under the [MIT License](LICENSE).
