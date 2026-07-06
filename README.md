# local-llm-dev

Full-stack (frontend-heavy) development on **local models** with Claude Code and OpenCode.
No proxies: Ollama ≥ 0.14 speaks the
[Anthropic Messages API natively](https://ollama.com/blog/claude), so Claude Code talks to it
directly via `ANTHROPIC_BASE_URL`. Designed to coexist with an existing Claude Code setup —
your `~/.claude/settings.json` and login are never touched; local mode is opt-in per
invocation, per shell session, or per project.

## Swapping cloud ↔ local

Three swap scopes — pick per situation:

| Scope | How | Back to cloud |
|---|---|---|
| One invocation | `cc-qwen` / `cc-local <model>` / `bin/claude-local` | just run plain `claude` |
| Current shell | `cc-mode local [model]` — plain `claude` now hits Ollama | `cc-mode cloud` (or new terminal) |
| One project | copy `config/claude-settings.local.json` → `<repo>/.claude/settings.local.json` | delete the file |

`cc-mode status` shows which mode a shell is in. All three only set env vars
(`ANTHROPIC_BASE_URL` etc.) — nothing writes to your global Claude config, so your work
login/settings survive intact. `bin/claude-local` is POSIX sh for machines without fish
(symlink onto PATH).

## What's here

```
models/            Modelfiles — derived models with num_ctx baked in
fish/functions/    cc-local, cc-qwen, cc-gemma, oc-local, ollama-tuned
config/            opencode.json + per-project .claude/settings.local.json template
templates/         AGENTS.local.md (compact project context) + portless.json
scripts/           setup.fish (installer) + repomap.sh (context compressor)
```

## Model matrix — pick by RAM (one model loaded at a time)

Default set (fits 16 GB):

| Model | Base tag | Size | Ctx | Role |
|---|---|---|---|---|
| `qwen3.5-dev` | `qwen3.5:9b` (q4_K_M) | 6.6 GB | 64k | Main agent — tools, thinking, vision. Opus/Sonnet tier. |
| `qwen3.5-fast` | `qwen3.5:4b` | 3.4 GB | 32k | Haiku tier / OpenCode `small_model` — titles, quick edits. |
| `gemma4-vision` | `gemma4:e4b-it-qat` | 6.1 GB | 32k | Frontend screenshot review (multimodal, QAT quant). |

More RAM (e.g. a beefier work machine) → bigger main agent; `setup.fish` creates these
automatically if the base tag is pulled:

| RAM | Pull | Derived model | Notes |
|---|---|---|---|
| 32 GB | `qwen3.5:27b` (17 GB) | `qwen3.5-dev-27b` | strongest dense coder that fits; Apple Silicon alt: `27b-coding-nvfp4` |
| 48–64 GB | `qwen3.5:35b-a3b` (24 GB) | `qwen3.5-dev-35b` | MoE, 3B active — near-27b quality, much faster |
| 64 GB+ | `gemma4:31b` (20 GB) | — | 256k ctx, strong reasoning; make own Modelfile if wanted |

Use them via `cc-local qwen3.5-dev-27b`, `cc-mode local qwen3.5-dev-27b`, or edit the
defaults in the wrappers. On 16 GB, 27b+ models don't fit with an agent-sized KV cache. Qwen 3.5 carries the
`tools thinking vision` capability tags ([qwen3.5 tags](https://ollama.com/library/qwen3.5/tags));
agentic tool-calling is the hard requirement for Claude Code/OpenCode. Gemma 4 E4B-QAT is the
cheapest capable multimodal option ([gemma4 tags](https://ollama.com/library/gemma4/tags)) — paste
UI screenshots at it. If a task outgrows the hardware, `qwen3.5:397b-cloud` / `gemma4:cloud` are
drop-in Ollama cloud tags.

KV cache is the hidden memory cost: the server tuning (`ollama-tuned` /
`launchctl setenv` in setup) sets `OLLAMA_KV_CACHE_TYPE=q8_0` + flash attention, which roughly
halves KV memory and is what makes 64k context viable next to a 6.6 GB model.

## Install

```fish
./scripts/setup.fish --pull --portless   # ~16 GB of downloads
```

Then:

```fish
cc-qwen                  # Claude Code → qwen3.5-dev (64k, tools+thinking)
cc-gemma                 # Claude Code → gemma4-vision (paste screenshots)
cc-local <any-model>     # generic wrapper
oc-local                 # OpenCode → ollama/qwen3.5-dev
```

To pin a whole project to local models without wrappers, copy
`config/claude-settings.local.json` → `<project>/.claude/settings.local.json`.
To go back to Anthropic cloud: just use plain `claude` (wrappers scope env to one invocation).

## Overhead overrides — why local feels slow without them

Claude Code ships defaults tuned for Anthropic's cloud. Three of them actively hurt local
models; all are overridden in the wrappers, `cc-mode`, and the settings template:

| Override | What it fixes |
|---|---|
| `CLAUDE_CODE_ATTRIBUTION_HEADER=0` (env) | **The big one.** Claude Code prepends an attribution/billing line to the system prompt whose value changes every request — so the KV cache misses on the whole prefix, every turn. [Measured ~90% slower inference on local models](http://www.mykolaaleksandrov.dev/posts/2026/06/claude-code-huge-prompt-investigation/); with it off, the stable prefix prefills once and is reused. |
| `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1` (env) | Background haiku-class calls (terminal titles, tips, flavor text). Harmless in the cloud; locally they queue behind your main model (`OLLAMA_NUM_PARALLEL=1`) and stall real work. [Env-var reference](https://code.claude.com/docs/en/env-vars). |
| `API_TIMEOUT_MS=600000` (env) | Local prefill on big context is slow; default timeout can fire and retry — and a retry means paying the whole prefill again. |
| `attribution: {"commit": "", "pr": ""}` ([settings](https://code.claude.com/docs/en/settings)) | Drops the Co-Authored-By/PR footer text (work-repo hygiene + a few fewer prompt tokens). `includeCoAuthoredBy` is deprecated — use the `attribution` object. |
| `includeGitInstructions: false` (settings) | Removes the built-in commit/PR workflow instructions and per-request git-status snapshot from the system prompt — smaller and more cache-stable prefix. Trade-off: no built-in commit ceremony; AGENTS.md conventions cover it. |
| `awaySummaryEnabled: false`, `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` | More background model calls (away recap, agent supervisor view) — same stall problem as above. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (env) | Telemetry/error-reporting/surveys. Caveat: [also disables the auto-updater](https://github.com/anthropics/claude-code/issues/53899) — update Claude Code manually on the work PC. |

**System-prompt overrides (both wired in):**

- `--exclude-dynamic-system-prompt-sections` — now the default in `cc-local`/`cc-qwen`/
  `cc-gemma`/`bin/claude-local`, and `cc-mode local` shadows plain `claude` with it (env vars
  can't carry CLI flags; `cc-mode cloud` removes the shadow). Moves per-request sections
  (cwd, git status, env info) out of the system prompt into the first user message →
  byte-stable prefix → KV-cache hit every turn. No behavior loss; ignored when a custom
  system prompt is set.
- **`cc-turbo [model]`** — replaces the ~10k-token harness prompt with
  `templates/system-prompt.slim.md` (~200 tokens, installed to `~/.config/local-llm-dev/`)
  via `--system-prompt-file`. Tool calling still works (tool schemas travel separately from
  the system prompt); the measured effect of this class of swap is prefill dropping from
  ~60s to ~2s on large local models. Trade-off: no built-in harness contract — the slim
  prompt re-teaches essentials (repomap-first retrieval, targeted edits, verify-after-edit,
  terse output) and defers the rest to AGENTS.md. Best on the 9b/4b models where prefill
  dominates; prefer plain `cc-qwen` when you want full harness behavior.

Also available but not defaulted: `claude --bare` strips hooks/plugins/MCP *and* CLAUDE.md —
defeats the repomap strategy; one-off throwaway sessions only.

OpenCode side (already in `config/opencode.json`): `"share": "disabled"` (no conversation
uploads — work machine), `"autoupdate": "notify"`, and `"compaction": {"prune": true}` which
drops old tool outputs instead of carrying them — the cheapest token savings available
([OpenCode config reference](https://opencode.ai/docs/config/)). OpenCode has no git-attribution
config key; if its commits need clean trailers, say so in AGENTS.md.

## Context strategy — the important part

Local models have 32–64k of real context vs Claude's 1M, and every wasted token also costs
KV-cache RAM and prefill time. The setup uses three layers:

1. **Tiny always-loaded file** — `templates/AGENTS.local.md` (~600 tokens hard budget).
   Stack, commands, conventions, the portless URL, and *rules telling the model how to
   retrieve context* instead of embedding context. Copy as `AGENTS.md`/`CLAUDE.md` per project.
2. **Generated repo map** — `scripts/repomap.sh` writes `.agents/repomap.md`. Backed by
   [repomix](https://repomix.com): tree-sitter `--compress` reduces every file to its
   signatures (functions, classes, interfaces, types — with parameter/field types intact),
   plus the directory tree and `package.json`. `output.tokenBudget: 8000` fails loudly if the
   map outgrows its share of a 64k window, and secretlint scans the pack so no credentials
   land in a prompt (work-machine relevant). First run seeds `repomix.config.json` from
   `templates/` — tune its `include` globs per repo. The model reads this one file instead of
   exploring — "scan the tree" (dozens of tool calls) becomes one read. Re-run after
   structural changes. Caveats: `--compress` drops exported *consts* (keeps
   functions/types/interfaces), and node-less machines fall back to a built-in grep generator
   (TS/JS exports only, 16 KB cap).

   **Regeneration is automatic.** Setup links the script as `~/.local/bin/repomap`; the
   settings template wires a Claude Code `SessionStart` hook running `repomap --if-stale`
   (no-op unless HEAD moved, and only in repos that opted in via `repomix.config.json`),
   and `repomap --install-hook` adds git post-commit/post-merge/post-checkout hooks so the
   map also stays fresh under OpenCode. Only gap: files created mid-session before any
   commit — the AGENTS rules tell the model to run `repomap` after structural changes.
3. **Retrieval on demand** — the AGENTS rules force grep-for-symbol → open-exact-path →
   read-only-needed-ranges. Never whole directories. Your RTK hook compounds this by
   token-filtering the shell commands the agent runs.

Also: keep the prompt prefix static (stable CLAUDE.md, no timestamps) so Ollama's KV cache
reuses the prefill across turns — that's most of the perceived speed on Apple Silicon.

## Frontend loop with portless

[Portless](https://github.com/vercel-labs/portless) (Vercel Labs) replaces `localhost:3000`
with stable named URLs — built explicitly for agents:

```fish
portless trust                 # once: local HTTPS
cd myapp
portless next dev              # → https://myapp.localhost
# or in package.json: "dev": "portless run next dev"
```

Why it matters here:
- **Stable URL in AGENTS.md** — the model always knows where the app runs; no port guessing,
  no "is it 3000 or 3001 today". The template bakes it in.
- **Worktree isolation** — branch `fix-ui` → `https://fix-ui.myapp.localhost`. Run agents in
  parallel worktrees, each app on its own deterministic URL.
- **Verify loop** — `curl -sk https://myapp.localhost` for smoke checks; screenshot the URL and
  paste into `cc-gemma` for visual review (Qwen 3.5 also accepts images).

Copy `templates/portless.json` into the project and set `name`.

## OpenCode

`config/opencode.json` (installed to `~/.config/opencode/` by setup) registers the three models
under an `ollama` provider via `@ai-sdk/openai-compatible` against `http://127.0.0.1:11434/v1`,
with context limits declared so OpenCode's compaction triggers correctly. `qwen3.5-dev` is the
default `model`, `qwen3.5-fast` the `small_model`. Docs:
[OpenCode providers](https://opencode.ai/docs/providers/), [Ollama × OpenCode](https://docs.ollama.com/integrations/opencode).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Unable to connect to API (ConnectionRefused)` in plain `claude` | Stale `ANTHROPIC_BASE_URL` in env — `set -e ANTHROPIC_BASE_URL` |
| Model ignores tools / truncates early | Context fell back to a small default — use the derived models (`num_ctx` baked in), not raw tags |
| OpenCode "missing API key" | `options.apiKey: "ollama"` must stay in the provider block (dummy value; Ollama ignores it) |
| Everything slow, fans spinning | Two models loaded — `OLLAMA_MAX_LOADED_MODELS=1` (set by `ollama-tuned`/setup), and don't run cc-qwen + cc-gemma simultaneously |
| Safari can't open `*.localhost` | `portless hosts sync` (Chrome/Firefox/Edge resolve it natively) |
| Docker container can't reach Ollama | `OLLAMA_HOST=0.0.0.0:11434 ollama serve` |

## Sources

- [Ollama — Claude Code integration](https://docs.ollama.com/integrations/claude-code) · [Anthropic API compatibility announcement](https://ollama.com/blog/claude)
- [Ollama — OpenCode integration](https://docs.ollama.com/integrations/opencode) · [OpenCode provider docs](https://opencode.ai/docs/providers/) · [OpenCode model docs](https://opencode.ai/docs/models/)
- [qwen3.5 tags](https://ollama.com/library/qwen3.5/tags) · [gemma4 tags](https://ollama.com/library/gemma4/tags)
- [vercel-labs/portless](https://github.com/vercel-labs/portless) · [portless docs](https://mintlify.wiki/vercel-labs/portless/introduction)
- Context-length guidance (32k floor / 64k sweet spot): [Claude Code with local LLMs](https://renezander.com/guides/claude-code-local-llm-anthropic-base-url/) · [Unsloth guide](https://unsloth.ai/docs/basics/claude-code)
