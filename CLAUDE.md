# Claude Local Backup Manager Rules

## Core Principles
* **Simplicity and Reliability**: The backup script must run silently in the background and reliably backup the `~/.claude` directory without heavy external dependencies like `cron`.
* **Cross-Platform Compatibility**: The script must support Windows (Git Bash), WSL, macOS, and Linux seamlessly.
* **Fail-Safe Operations**: Implement robust locking mechanisms (`mkdir`-based locking) and graceful shutdown sequences (`SIGTERM` -> up to 5-second grace period -> `SIGKILL`).
* **English Only**: All project output, documentation, and commit messages must be written in English to be an open-source standard project.

## Repository Structure
* `claude-backup.sh`: Main executable bash script for managing the daemon and performing backups.
* `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `LICENSE`: Primary open-source project documentation.
* `.github/`: Issue and Pull Request templates for the community.
* `.gitattributes`: LF line-ending enforcement for all text and shell files.
* `.gitignore`: Excludes `.claude/` local settings and other non-tracked files.
* `audits/`: Security and documentation audit reports.
* `github-repo-card.html`, `github-repo-card.png`: GitHub social preview assets.

## Git Rules
* **Commit Types**: Use Conventional Commits (`feat`, `fix`, `docs`, `chore`, `refactor`).
* **Format**: `type[(scope)]: subject` — scope is optional (e.g., `feat(core): add generic rsync support`, `docs: update README`).
* **Line Endings**: Enforce LF line endings for all shell scripts.
* **Subject**: Use the imperative mood in commit subjects.

## Prohibited Actions
* Do NOT add massive external dependencies. Stick to built-in or widely available standard commands (`rsync`, `robocopy`, `cp`, `tar`, `awk`, `sed`).
* Do NOT commit secrets, sensitive credentials, or specific user environment variables to the repository.
* Do NOT force push (`git push -f`) to the `main` branch.
