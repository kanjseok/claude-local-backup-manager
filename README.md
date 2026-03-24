# claude-local-files-backup

`~/.claude` 폴더를 5분 간격으로 자동 백업하는 크로스 플랫폼 백그라운드 스크립트입니다.

## 지원 환경

- Windows (Git Bash)
- WSL (Ubuntu)
- macOS
- Linux

## 사용법

```bash
./claude-backup.sh start      # 백그라운드 데몬 시작
./claude-backup.sh stop       # 데몬 종료
./claude-backup.sh status     # 상태 확인
./claude-backup.sh run-once   # 1회 백업 실행
./claude-backup.sh list       # 스냅샷 목록
```

## 동작 방식

### 2단계 백업

1. **미러 동기화 (5분마다)**: `~/.claude` → `~/.claude-backups/current/` 증분 복사
2. **스냅샷 (1시간마다)**: 미러의 tar.gz 아카이브 생성, 최근 48개 보존

### 동기화 엔진 (자동 감지)

| 우선순위 | 엔진 | 환경 |
|----------|------|------|
| 1 | rsync | WSL, macOS, Linux |
| 2 | robocopy | Windows (Git Bash) |
| 3 | cp 증분 비교 | fallback |

### 데몬 관리

- `nohup` + sleep 루프 방식 (cron 미사용)
- PID 파일로 프로세스 추적
- `mkdir` 기반 락으로 동시 실행 방지
- `SIGTERM` → 5초 대기 → `SIGKILL` 순서로 안전 종료

## 백업 디렉토리 구조

```
~/.claude-backups/
├── current/                  # 최신 미러
├── snapshots/                # 타임스탬프별 tar.gz 아카이브
│   ├── 20260325_043653.tar.gz
│   └── ...
├── logs/
│   └── backup.log            # 실행 로그
└── claude-backup.pid          # 데몬 PID 파일
```

## 백업 대상

| 포함 | 제외 |
|------|------|
| `config.json`, `settings.json` | `.git` |
| `.credentials.json` | `cache`, `debug` |
| `MEMORY.md`, `history.jsonl` | `backups`, `shell-snapshots` |
| `projects/`, `plans/`, `todos/` | `statsig`, `telemetry` |
| `commands/`, `skills/`, `tasks/` | `worktrees` |
| `file-history/`, `plugins/` (설정) | `.update.lock` |

## 환경변수 설정

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CLAUDE_BACKUP_SOURCE` | `~/.claude` | 소스 디렉토리 |
| `CLAUDE_BACKUP_DIR` | `~/.claude-backups` | 백업 저장 위치 |
| `CLAUDE_BACKUP_INTERVAL` | `300` | 동기화 주기 (초) |
| `CLAUDE_BACKUP_SNAPSHOT_INTERVAL` | `3600` | 스냅샷 생성 주기 (초) |
| `CLAUDE_BACKUP_MAX_SNAPSHOTS` | `48` | 스냅샷 최대 보존 수 |

### 예시: 1분 간격, 백업 경로 변경

```bash
CLAUDE_BACKUP_INTERVAL=60 CLAUDE_BACKUP_DIR=/mnt/backup/.claude-backups ./claude-backup.sh start
```
