<!--
Template: copy into a project root as AGENTS.md (OpenCode) and/or CLAUDE.md (Claude Code).
Replace <name>/<project> placeholders. Keep the whole file under ~600 tokens — this file
is loaded into EVERY request, and local models have 32–64k of context total. Everything
bulky lives in the generated repo map instead.
-->

# <project>

Stack: Next.js (app router) · TypeScript · Tailwind · pnpm.
Dev URL: https://<name>.localhost — stable, no port numbers (portless proxy).

## Commands
- `pnpm dev` — runs under portless → https://<name>.localhost (HTTPS)
- `pnpm build` · `pnpm lint` · `pnpm test`
- `repomap` — regenerate `.agents/repomap.md`. Auto-refreshes at session start and on
  commits; run it manually only after creating/moving files mid-session.
  (repomix-backed; map globs live in `repomix.config.json`)

## Context rules (small context window — follow strictly)
1. Read `.agents/repomap.md` first. It has the directory tree, routes, and every
   exported symbol with its file. Do NOT re-scan the tree or list directories.
2. Open files by exact path from the repo map; read only the line ranges you need.
3. Look up symbols with grep, not by reading whole files.
4. Never cat entire directories. Never paste more than ~50 lines back into chat.
5. One file open at a time; finish an edit before reading the next file.

## Conventions
- Components in `app/components/`, PascalCase; server components by default,
  `'use client'` only when state/effects/events require it.
- Styling: Tailwind classes only — no CSS files, no inline styles.
- Data: server actions in `app/actions/`, inputs validated with zod.
- Never edit generated files (`.agents/`, `.next/`, lockfiles).

## Verify frontend changes
- App is live at https://<name>.localhost while `pnpm dev` runs.
- Smoke check: `curl -sk https://<name>.localhost | head -30`
- Git worktree branches get their own URL: https://<branch>.<name>.localhost
