# Security Audit Report — Claude Local Backup Manager

> Audit date: 2026-03-25
> Auditor: Claude Opus 4.6 (automated security persona)
> Scope: Full codebase, git history, configuration, documentation
> Overall Assessment: **SAFE for public release with minor fixes applied**

---

## 1. Executive Summary

A comprehensive security audit was performed on the Claude Local Backup Manager project prior to publication as an open-source public repository. The audit covered source code analysis, git history inspection, configuration file review, and documentation completeness.

The project demonstrates strong security practices overall. Several issues ranging from medium to informational severity were identified and remediated during this audit.

---

## 2. Project Overview

- **Main artifact**: `claude-backup.sh` (603 lines, single bash script)
- **Purpose**: Background daemon that backs up `~/.claude` directory
- **Platforms**: Windows (Git Bash), WSL, macOS, Linux
- **Sync engines**: rsync / robocopy / cp (auto-detected)
- **Snapshot format**: tar.gz archives with timestamp naming
- **License**: MIT
- **Dependencies**: None (standard OS utilities only)

---

## 3. Findings

### 3.1 [MEDIUM] Arithmetic injection via environment variables

**File**: `claude-backup.sh:11-13`
**Status**: REMEDIATED

Environment variables `CLAUDE_BACKUP_INTERVAL`, `CLAUDE_BACKUP_SNAPSHOT_INTERVAL`, and `CLAUDE_BACKUP_MAX_SNAPSHOTS` were used in bash `(( ))` arithmetic contexts without validation. Bash arithmetic evaluation performs recursive variable expansion — a malicious value like `a[$(rm -rf /)]` would execute the embedded command during arithmetic evaluation.

**Remediation**: Added `validate_positive_int()` function with regex-based validation (`^[0-9]+$`) that runs before any arithmetic context. The regex check uses `[[ =~ ]]` (string operation, no arithmetic evaluation), preventing injection.

**Verification**:
```
$ CLAUDE_BACKUP_INTERVAL='a[$(touch /tmp/pwned)]' ./claude-backup.sh status
ERROR: CLAUDE_BACKUP_INTERVAL must be a positive integer, got: 'a[$(touch /tmp/pwned)]'
# /tmp/pwned was NOT created
```

---

### 3.2 [MEDIUM] File permissions — missing `umask 077`

**File**: `claude-backup.sh:6`
**Status**: REMEDIATED

PID file, lock directory PID file, and log files were created with default umask permissions. On shared systems with permissive umask (e.g., 022), these files could be world-readable, exposing process information and backup activity logs.

**Remediation**: Added `umask 077` immediately after `set -uo pipefail`. All files and directories created by the script are now owner-only (600 for files, 700 for directories).

---

### 3.3 [LOW] `_daemon` internal command exposed to users

**File**: `claude-backup.sh:595-597`
**Status**: REMEDIATED

The `_daemon` case in the main switch was accessible to users via `./claude-backup.sh _daemon`. Direct invocation would start the daemon loop in the foreground without PID file management, causing inconsistent state with the `status` and `stop` commands.

**Remediation**: Added environment variable guard (`CLAUDE_BACKUP_DAEMON_INTERNAL`). The `cmd_start` function sets this variable when launching the daemon via `nohup`, and the `_daemon` handler rejects invocations without it.

**Verification**:
```
$ ./claude-backup.sh _daemon
ERROR: _daemon is an internal command. Use 'start' instead.
```

---

### 3.4 [LOW] Path validation missing

**File**: `claude-backup.sh:14-15`
**Status**: REMEDIATED

`CLAUDE_BACKUP_SOURCE` and `CLAUDE_BACKUP_DIR` were not validated for empty values or embedded newlines/carriage returns, which could cause unexpected behavior in file operations.

**Remediation**: Added `validate_path()` function that rejects empty values and paths containing newline or carriage return characters.

---

### 3.5 [INFO] Missing rationale for `set -uo pipefail` (no `-e`)

**File**: `claude-backup.sh:6`
**Status**: REMEDIATED

The absence of `-e` (errexit) is intentional but was undocumented. Multiple code paths depend on non-zero exit codes:
- robocopy returns exit codes 0-7 for success
- `((var++))` returns 1 when var was 0 (falsy pre-increment)
- Daemon loop uses `|| true` guards extensively

**Remediation**: Added multi-line comment explaining the design decision for future contributors and auditors.

---

### 3.6 [INFO] `ls` output parsing

**File**: `claude-backup.sh` (6 instances across snapshot functions)
**Status**: REMEDIATED

Parsing `ls` output is fragile with filenames containing spaces or newlines. While safe in this codebase (filenames are script-generated `YYYYMMDD_HHMMSS.tar.gz`), it triggers ShellCheck warnings and represents a defensive coding concern.

**Remediation**: Replaced all `ls` parsing with `shopt -s nullglob` glob arrays. Extracted a shared `get_snapshot_files()` helper function using bash nameref (`local -n`) for reuse across `get_latest_snapshot_time()`, `cleanup_snapshots()`, `cmd_status()`, and `cmd_list()`.

---

### 3.7 [INFO] Signal handling on Git Bash

**File**: `claude-backup.sh:347`
**Status**: DOCUMENTED

`trap daemon_cleanup SIGTERM SIGINT SIGHUP` may not work reliably on all Git Bash / MSYS2 versions. The `stop` command already includes a 5-second timeout with `SIGKILL` fallback.

**Remediation**: Added "Known Limitations" section to README.md documenting this behavior.

---

## 4. Clean Findings (No Action Required)

### 4.1 `.claude/settings.local.json` — NOT tracked in git

The file exists locally and contains user-specific paths (`/c/Users/tech/...`, `C:\\Users\\tech\\...`), but:
- `.gitignore` properly excludes `.claude/` directory
- `git ls-files .claude/` returns empty (never committed)
- `git log --all --full-history -- ".claude/"` returns no results

Added a warning in `CONTRIBUTING.md` to never force-add files under `.claude/`.

### 4.2 Git history — clean

- Only 2 commits on master branch
- No secrets, credentials, API keys, or PII in tracked files
- No deleted sensitive files in history
- No suspicious binary files or large objects
- Remote uses HTTPS protocol (secure)

### 4.3 No hardcoded secrets

Comprehensive pattern search for `password`, `secret`, `token`, `key`, `credential`, `api` found zero matches in source code. All paths use environment variable expansion (`$HOME`).

### 4.4 Variable quoting — safe

All variables throughout the script are properly double-quoted. No command injection vectors via arguments. Array syntax used for command construction (robocopy, rsync).

### 4.5 No dangerous code patterns

- No `eval` or backtick execution
- No dynamic code generation
- `$()` command substitution used throughout (modern, safe)
- No use of `exec` with user-controlled input

### 4.6 Lock mechanism — sound

`mkdir`-based atomic locking is POSIX-compliant and cross-platform safe. Stale lock detection via `kill -0` with proper reclamation. No race conditions identified.

### 4.7 `.gitignore` — comprehensive

Properly excludes: `.env*`, `.claude/`, `*.pid`, `*.log`, OS files, editor/IDE directories.

### 4.8 Documentation — complete

All required open-source files present: README.md, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, LICENSE (MIT), GitHub issue/PR templates.

---

## 5. Positive Security Practices Observed

| Practice | Details |
|----------|---------|
| No external dependencies | Uses only standard OS utilities (rsync, robocopy, cp, tar) |
| Proper file permissions | `chmod 700` on backup directory, `chmod 600` on snapshots |
| Atomic locking | `mkdir`-based cross-platform lock prevents concurrent operations |
| Graceful shutdown | SIGTERM -> 5s wait -> SIGKILL sequence |
| Log rotation | 10MB limit prevents disk exhaustion |
| PID management | Stale PID detection and cleanup |
| Defensive shell options | `set -uo pipefail` catches undefined variables and pipeline failures |
| Controlled exclusions | Hardcoded exclude patterns (not user-input controlled) |
| Safe `find` usage | `find -print0` with `read -r -d ''` in cp fallback |

---

## 6. Remediation Summary

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| 3.1 | MEDIUM | Arithmetic injection via env vars | REMEDIATED |
| 3.2 | MEDIUM | Missing `umask 077` | REMEDIATED |
| 3.3 | LOW | `_daemon` command exposed | REMEDIATED |
| 3.4 | LOW | Path validation missing | REMEDIATED |
| 3.5 | INFO | Undocumented `-e` omission | REMEDIATED |
| 3.6 | INFO | `ls` output parsing | REMEDIATED |
| 3.7 | INFO | Git Bash signal handling | DOCUMENTED |

---

## 7. Verification Results

| Test Case | Expected | Actual |
|-----------|----------|--------|
| Arithmetic injection payload | Blocked, exit 1 | PASS |
| Negative interval value | Rejected, exit 1 | PASS |
| `_daemon` direct invocation | Rejected, exit 1 | PASS |
| Normal `status` command | Works correctly | PASS |
| `.claude/` in git index | Not tracked | PASS |
| Git history secrets scan | Clean | PASS |
| Bash syntax check (`bash -n`) | Exit 0 | PASS |
| `/tmp/pwned` not created | File absent | PASS |

---

## 8. Recommendations

1. **GitHub repository settings**: Enable branch protection on `main` (require PR reviews, disable force pushes)
2. **ShellCheck CI**: Consider adding `shellcheck claude-backup.sh` to a GitHub Actions workflow
3. **Encrypted backups**: For sensitive environments, document recommending encrypted filesystem for backup destination (added to README Known Limitations)

---

## 9. Files Modified During Remediation

| File | Changes |
|------|---------|
| `claude-backup.sh` | `umask 077`, input validation, `_daemon` guard, `set` flags comment, glob-based snapshot enumeration |
| `CONTRIBUTING.md` | Warning against force-adding `.claude/` directory |
| `README.md` | "Known Limitations" section (Git Bash signals, encryption at rest) |

---

*This audit was performed by Claude Opus 4.6 as an automated security review prior to open-source publication.*
