# Contributing Guide

> Thank you for your interest in Claude Local Backup Manager!
> Contributions of all kinds are welcome — from fixing typos to proposing entirely new standard documents.

---

## 1. Before You Start

- **Search existing issues** to avoid duplicates.
- For non-trivial changes, **open an issue first** to discuss the direction before investing time in a PR.
- Read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

---

## 2. How to Contribute

### Fork & Branch Workflow

```bash
# 1. Fork this repository on GitHub, then clone your fork
git clone https://github.com/<your-username>/claude-local-backup-manager.git
cd claude-local-backup-manager

# 2. Create a feature branch from main
git checkout -b feature/your-topic

# 3. Make your changes, then commit
git add <specific-files>
git commit -m "docs(boilerplate): add API design standard"

# 4. Push and open a Pull Request
git push origin feature/your-topic
```

### Branch Naming

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feature/` | New documents or sections | `feature/api-design-guide` |
| `fix/` | Corrections, typo fixes | `fix/doc12-verification` |
| `chore/` | Repo config, CI, metadata | `chore/update-gitignore` |

---

## 3. Commit Message Convention

This repository follows **Conventional Commits** with the `docs` type as default.

```
docs(<scope>): <subject>
```

**Scopes**: `tech-stack`, `boilerplate`, `readme`, `claude`, `repo`

```bash
# Examples
git commit -m "docs(boilerplate): add API design standard"
git commit -m "docs(tech-stack): update Node.js version to 24"
git commit -m "docs(repo): add GitHub issue templates"
```

**Rules**:
- Use imperative mood in the subject (`add`, not `added` or `adds`)
- Keep the subject line under 72 characters
- Do **not** use `git add -A` or `git add .` — stage specific files only

---

## 4. Document Writing Conventions

All documents in this repository must follow these standards:

### Structure

1. **One H1 (`#`) per file** — used as the document title
2. **Blockquote summary** — a 1-2 line `>` summary immediately after the title
3. **Body sections** — organized with H2 (`##`) and H3 (`###`)
4. **Verification section** — a `## Verification` section at the end with commands or checklists to confirm setup

### Content Principles

- **No business logic** — keep examples generic and universally applicable
- **Copy-paste ready** — code blocks must be complete and runnable, with language tags (` ```bash `, ` ```typescript `, etc.)
- **Self-contained** — each document should be independently referenceable
- **English only** — all documents, code comments, and variable names in English

### File Naming

- Use **kebab-case**: `api-design-guide.md`
- Documents within directories use **number prefixes**: `00-index.md`, `01-topic.md`

---

## 5. Pull Request Guidelines

- Fill out the PR template completely.
- Reference the related issue (e.g., `Closes #12`).
- Keep PRs focused — one topic per PR.
- Ensure all documents follow the writing conventions above.
- Verify cross-reference consistency (e.g., if you add a new document, update `00-index.md` and `README.md`).

---

## 6. Reporting Issues

Use the GitHub issue templates provided:

- **Bug Report** — for broken links, incorrect information, formatting issues
- **Document Request** — for proposing new standard documents or categories

---

## 7. License

By contributing, you agree that your contributions will be licensed under the [CC BY 4.0](LICENSE) license.