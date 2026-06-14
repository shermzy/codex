---
name: init-project
description: Use when starting a new repository and you need to initialize git plus OpenClaw workspace files from any folder.
---

# Init Project

Initialize a repository with a T3/OpenClaw-style project scaffold.

## When to Use

Use this skill when:
- Starting a new project folder
- Retrofitting an existing project to include OpenClaw context files
- Standardizing AI context, git initialization, and first commit behavior across repositories

## What This Creates

- `AGENTS.md`
- `SOUL.md`
- `TOOLS.md`
- `USER.md`
- `MEMORY.md`
- `README.md`
- `memory/today.md`
- `agents/.gitkeep`
- `.gitignore` entries for local runtime artifacts

## Run

From any new project folder:

```powershell
& "C:\Users\sherm\.codex\bin\init-t3-project.ps1"
```

Or target a specific folder:

```powershell
& "C:\Users\sherm\.codex\bin\init-t3-project.ps1" -TargetDir "<repo-root>"
```

## Options

- `-TargetDir`: Folder to initialize. Defaults to the current folder.
- `-RepoName`: GitHub repository name. Defaults to a sanitized target folder name.
- `-ForceDocs`: Overwrite existing scaffold markdown files.
- `-NoRemote`: Skip GitHub repository creation and push for local testing.

`-Force` is accepted as a backward-compatible alias for `-ForceDocs`.

## Git Behavior

- Initializes git with branch `main` when the target does not already have its own `.git` directory.
- Preserves an existing target repository and existing `origin` remote.
- Creates a private GitHub repository with `gh repo create` when no `origin` exists.
- Stages only the bootstrap files, commits `Initialize project scaffold`, and pushes `main`.

## Backward-Compatible Script Path

The legacy script path remains installed and delegates to the same workflow implementation:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\sherm\.codex\skills\init-project\scripts\init_openclaw_project.ps1" -TargetDir "<repo-root>"
```
