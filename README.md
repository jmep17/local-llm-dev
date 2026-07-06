# local-llm-dev

Run **Claude Code and OpenCode on local models** (Ollama) for full-stack development.

- **No proxy.** Ollama ≥ 0.14 speaks the [Anthropic API natively](https://ollama.com/blog/claude) — Claude Code just points at `localhost:11434`.
- **No conflict with your existing setup.** Local mode is opt-in per command, per shell, or per project. Your `~/.claude` settings and login are never touched.
- **Tuned for real work.** Strips the Claude Code defaults that cripple local models (a cache-busting attribution header alone makes inference ~90% slower), and ships a context system that fits a codebase into a 64k window.

---

## Quick start

```sh
git clone https://github.com/jmep17/local-llm-dev && cd local-llm-dev

# fish (personal Mac):
./scripts/setup.fish              # pulls ~16 GB of models on first run

# zsh/bash (work PC):
./scripts/setup.sh
# then add the line it prints to ~/.zshrc:
#   source /path/to/local-llm-dev/shell/local-llm-dev.zsh
```

Open a new shell, then:

```sh
cc-qwen        # Claude Code on a local model. That's it.
```

Setup is idempotent (re-run any time; skips what exists). `--no-pull` skips downloads —
wrappers auto-pull any missing model on first use anyway. `--portless` also installs
[portless](https://github.com/vercel-labs/portless) (see Frontend workflow).

---

## Daily use

| Command | What it does |
|---|---|
| `cc-qwen` | Claude Code → `qwen3.5-dev` (the main local agent) |
| `cc-turbo` | Same, but with a ~200-token system prompt instead of the ~10k harness prompt — fastest prefill |
| `cc-gemma` | Claude Code → `gemma4-vision` — paste UI screenshots for visual review |
| `cc-local <model>` | Claude Code → any Ollama model (auto-pulls if missing) |
| `cc-mode local` / `cloud` / `status` | Make plain `claude` local for this shell / revert / check |
| `oc-local` | OpenCode → local models |
| `ollama-tuned` | Run the Ollama server with the right flags (see Performance) |
| `repomap` | Regenerate the repo's context map (usually automatic — see Context) |
| `cc-mcp` / `cc-skill` | Manage MCP allowlist / skills (see Extending) |

**Switching cloud ↔ local** is just scope choice:

| Scope | Local | Back to cloud |
|---|---|---|
| One command | `cc-qwen` etc. | run plain `claude` |
| This shell | `cc-mode local` | `cc-mode cloud` or new terminal |
| One project | copy `config/claude-settings.local.json` → `<repo>/.claude/settings.local.json` | delete that file |

Everything is env-var scoped. Nothing writes to your global Claude config. On a work
machine, pin work repos with the per-project file so forgetting `cc-mode` can't send code
to the cloud.

---

## Models

Default set fits **16 GB** (one model loaded at a time). Wrappers auto-pull/create any of
these on first use; setup pre-pulls them.

| Model | Base | Size | Ctx | Role |
|---|---|---|---|---|
| `qwen3.5-dev` | `qwen3.5:9b` | 6.6 GB | 64k | Main agent — tools, thinking, vision |
| `qwen3.5-fast` | `qwen3.5:4b` | 3.4 GB | 32k | Background/haiku tier |
| `gemma4-vision` | `gemma4:e4b-it-qat` | 6.1 GB | 32k | Screenshot review (multimodal) |

More RAM → stronger main agent (`cc-local qwen3.5-dev-27b` auto-pulls it):

| RAM | Model | Notes |
|---|---|---|
| 32 GB | `qwen3.5-dev-27b` | strongest dense coder; Apple Silicon alt: `27b-coding-nvfp4` |
| 48 GB+ | `qwen3.5-dev-35b` | MoE, 3B active — near-27b quality, much faster |

These are *derived models* (`models/*.Modelfile`): base + `num_ctx` baked in, because raw
Ollama tags default to a context too small for agents. Tags: [qwen3.5](https://ollama.com/library/qwen3.5/tags) ·
[gemma4](https://ollama.com/library/gemma4/tags). Avoid `:cloud` tags if code must stay local — those run on Ollama's servers.

---

## Performance: why this isn't slow

Two things make local agents miserable: re-prefilling the prompt every turn, and background
model calls. Both are handled.

**KV-cache stability** (the prompt prefix must be byte-identical each turn, or the model
re-processes everything):

| Fix | Problem it solves |
|---|---|
| `CLAUDE_CODE_ATTRIBUTION_HEADER=0` | Claude Code prepends a per-request-changing line to the system prompt — [~90% slower on local models](http://www.mykolaaleksandrov.dev/posts/2026/06/claude-code-huge-prompt-investigation/) |
| `--exclude-dynamic-system-prompt-sections` | cwd/git-status/env sections change per request; this moves them out of the prompt prefix |
| `cc-turbo` | Replaces the ~10k-token harness prompt entirely (`--system-prompt-file`, ~200 tokens). Tool calling unaffected — schemas travel separately |
| `ollama-tuned` / setup's `launchctl` env | `OLLAMA_KV_CACHE_TYPE=q8_0` + flash attention ≈ halves KV memory — what makes 64k ctx fit next to a 6.6 GB model in 16 GB |

**No background stalls:**

| Fix | Problem it solves |
|---|---|
| `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1` | Titles/tips/flavor calls queue behind your one loaded model |
| `awaySummaryEnabled: false`, `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` | Two more background-call sources |
| `API_TIMEOUT_MS=600000` | A timeout retry = paying slow prefill twice |
| `attribution: {"commit":"","pr":""}`, `includeGitInstructions: false` | Smaller prompt; clean commits ([settings ref](https://code.claude.com/docs/en/settings)) |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | Telemetry/surveys off. Side effect: [auto-updater off too](https://github.com/anthropics/claude-code/issues/53899) — update Claude Code manually |

All of this is baked into the wrappers and `config/claude-settings.local.json` — nothing to
remember. (`claude --bare` exists for max stripping but skips CLAUDE.md, which breaks the
context system below — throwaway sessions only.)

---

## Context: fitting a codebase in 64k

Local models have 32–64k of context vs the cloud's 1M. Three layers, per project:

1. **AGENTS.md** (`templates/AGENTS.local.md`, ≤600 tokens) — stack, commands, conventions,
   dev URL, and *rules for retrieving* context instead of embedding it: repo-map first,
   grep for symbols, open exact paths, read only needed ranges, never cat directories.
2. **Repo map** (`.agents/repomap.md`, ~8k-token budget) — generated by
   [repomix](https://repomix.com): tree-sitter compression reduces every file to its
   signatures, plus directory tree and dependencies. One read replaces dozens of
   exploration tool calls. Secretlint scans the pack so credentials can't land in a prompt;
   the map is auto-gitignored. First run seeds `repomix.config.json` — tune its `include`
   globs per repo. (Known limit: compression keeps functions/classes/types but drops
   exported consts. No node? A grep-based fallback generator runs instead.)
3. **Grep on demand** — enforced by the AGENTS rules for everything else.

**The map maintains itself:** a Claude Code `SessionStart` hook (in the settings template)
and optional git hooks (`repomap --install-hook`) run `repomap --if-stale`, which
regenerates only when git HEAD moved. Manual `repomap` only needed after creating files
mid-session.

Per-project setup: copy `templates/AGENTS.local.md` → `AGENTS.md`/`CLAUDE.md`, run
`repomap`, done.

---

## Extending: MCPs and skills

```sh
cc-mcp list
cc-mcp add linear https://mcp.linear.app/mcp      # remote HTTP server
cc-mcp add playwright npx -y @playwright/mcp      # local stdio server
cc-mcp rm playwright

cc-skill new my-review               # scaffold ~/.claude/skills/my-review/SKILL.md
cc-skill new deploy --project        # scaffold into this repo only
cc-skill add https://github.com/x/y  # install from git (single skill or collection)
cc-skill list
```

Local mode runs **only** MCP servers on the allowlist (`--strict-mcp-config`) — default is
context7 (docs lookup) + repomix. Two budget rules for 64k models: every MCP server's tool
schemas and every skill's description line load into each session's prompt, so keep both
lists short. Adding a remote MCP is a locality decision — that server receives what the
model sends it.

---

## Frontend workflow (portless)

[Portless](https://github.com/vercel-labs/portless) (Vercel Labs) gives dev servers stable
named URLs instead of ports:

```sh
portless trust            # once — local HTTPS
portless next dev         # → https://myapp.localhost
```

Why it matters for agents: the URL is deterministic, so it lives in AGENTS.md and the model
always knows where the app runs; git worktree branches get their own URL
(`https://fix-ui.myapp.localhost`) so parallel agents don't collide; and the verify loop is
trivial — `curl -sk https://myapp.localhost` for smoke checks, screenshot → paste into
`cc-gemma` for visual review. Copy `templates/portless.json`, set `name`.

Note: portless is pre-1.0 and installs a root-owned launchd service (port 443) — check
policy before sudo-installing on a work machine.

---

## OpenCode

`config/opencode.json` (installed by setup) registers all models via
`@ai-sdk/openai-compatible` → `127.0.0.1:11434/v1` with correct context limits, plus
`share: "disabled"` (no conversation uploads), `autoupdate: "notify"`, and
`compaction.prune` (drops old tool outputs). Docs: [providers](https://opencode.ai/docs/providers/) ·
[Ollama × OpenCode](https://docs.ollama.com/integrations/opencode). If you already have an
OpenCode config, setup writes `opencode.local-models.json` next to it for manual merge
instead of overwriting.

---

## Is it 100% local?

Model traffic (prompts, code, completions) never leaves `localhost`. Remaining outbound, by
design: npm package fetches on first use, OpenCode's models.dev catalog + update-notify
pings, and context7 doc queries (allowlisted deliberately). WebFetch's phone-home domain
check is disabled (`skipWebFetchPreflight`). Cloud mode (`claude` without local pinning) is
normal Anthropic traffic — that's the point of the swap.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "model may not exist" on first run | It's downloading — wrappers auto-pull; watch the terminal. Or run setup once. |
| `ConnectionRefused` in plain `claude` | Stale local env — `cc-mode cloud`, or new terminal |
| Model ignores tools / truncates early | Using a raw tag with default (tiny) context — use the derived models |
| OpenCode "missing API key" | Keep `apiKey: "ollama"` in the provider options (dummy; Ollama ignores it) |
| Everything slow, fans on | Two models loaded — don't run cc-qwen and cc-gemma at once (`OLLAMA_MAX_LOADED_MODELS=1` guards this) |
| Safari can't open `*.localhost` | `portless hosts sync` |
| Docker can't reach Ollama | `OLLAMA_HOST=0.0.0.0:11434 ollama serve` |

---

## Repo layout

```
bin/               claude-local (POSIX wrapper), cc-mcp, cc-skill, cc-ensure-model
config/            opencode.json, claude-settings.local.json (per-project pin), mcp-local.json
fish/functions/    cc-local, cc-qwen, cc-gemma, cc-turbo, cc-mode, oc-local, ollama-tuned
shell/             local-llm-dev.zsh — zsh port of all functions
models/            Modelfiles (base + num_ctx) for the derived models
scripts/           setup.fish, setup.sh, repomap.sh
templates/         AGENTS.local.md, repomix.config.json, portless.json, system-prompt.slim.md
```

## Sources

[Ollama × Claude Code](https://docs.ollama.com/integrations/claude-code) · [Anthropic-compat announcement](https://ollama.com/blog/claude) · [Ollama × OpenCode](https://docs.ollama.com/integrations/opencode) · [OpenCode providers](https://opencode.ai/docs/providers/) / [models](https://opencode.ai/docs/models/) / [config](https://opencode.ai/docs/config/) · [qwen3.5 tags](https://ollama.com/library/qwen3.5/tags) · [gemma4 tags](https://ollama.com/library/gemma4/tags) · [portless](https://github.com/vercel-labs/portless) · [repomix](https://repomix.com) · [Claude Code prompt investigation](http://www.mykolaaleksandrov.dev/posts/2026/06/claude-code-huge-prompt-investigation/) · [Unsloth local guide](https://unsloth.ai/docs/basics/claude-code) · [env vars](https://code.claude.com/docs/en/env-vars) · [settings](https://code.claude.com/docs/en/settings)
