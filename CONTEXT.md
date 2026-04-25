# TokenGuard Context

## Purpose

Local-first macOS menu bar utility for AI tool usage and reset timing.

## Migration Notes

- Migrated from `Projects/Personal/TokenGuard` on 2026-04-20.
- Build products, derived data, old orchestration state, and other generated artifacts were excluded.

## Troubleshooting Notes

- If Antigravity stalls or fails to respond in this repo, check Git worktree state first. On 2026-04-24, `.git/worktrees/agitated-villani-cbd957/config.worktree` remained after the linked `.claude/worktrees/agitated-villani-cbd957` directory was gone, and `git worktree list --porcelain` marked it prunable. Also check for `extensions.worktreeConfig` in `.git/config`: Antigravity can fail with `core.repositoryformatversion does not support extension: worktreeconfig`, which prevents workspace resolution, trajectory persistence, and planner context loading. Start future debugging with `.git/config`, `.git/worktrees/*/config.worktree`, and `extensions.worktreeConfig`.
