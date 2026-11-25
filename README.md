<p align="center">
  <img src="main.png" alt="AgentRadio — passive awareness for multi-agent coding" width="100%">
</p>

<h1 align="center">📻 AgentRadio</h1>

<h3 align="center">Passive awareness for long-horizon multi-agent collaboration — four coding agents that keep working <b>while</b> they listen</h3>

<p align="center">
  <a href="https://coralcode.dev/"><img src="https://img.shields.io/badge/Coral_Code-%2430_free_credit-FF7F50?style=for-the-badge&logoColor=white" alt="Coral Code"></a>
  <a href="https://arxiv.org/abs/2607.28430"><img src="https://img.shields.io/badge/Paper-arXiv-B31B1B?style=for-the-badge&logo=arxiv&logoColor=white" alt="Paper"></a>
  <a href="https://github.com/Coral-Protocol/AgentRadio"><img src="https://img.shields.io/badge/Code-GitHub-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache_2.0-D22128?style=for-the-badge&logo=apache&logoColor=white" alt="License: Apache 2.0"></a>
</p>

<p align="center">
  <a href="https://github.com/scaleapi/SWE-Atlas"><img src="https://img.shields.io/badge/Benchmark-SWE--Atlas_QnA-0E9B9B?style=for-the-badge&logo=github&logoColor=white" alt="Benchmark"></a>
  <a href="https://github.com/laude-institute/harbor"><img src="https://img.shields.io/badge/Orchestration-Harbor-4B32C3?style=for-the-badge&logo=github&logoColor=white" alt="Harbor"></a>
  <a href="https://modal.com"><img src="https://img.shields.io/badge/Compute-Modal-7FEE64?style=for-the-badge&logo=modal&logoColor=black" alt="Modal"></a>
</p>

<p align="center">
  <a href="https://discord.gg/GSHKNXF8U"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"></a>
  <a href="https://github.com/Coral-Protocol"><img src="https://img.shields.io/badge/Coral_Protocol-Org-FF5C8A?style=for-the-badge&logo=github&logoColor=white" alt="Coral Protocol"></a>
</p>

<p align="center">
  <b>English</b> |
  <a href="README.zh-CN.md">简体中文</a> |
  <a href="README.es.md">Español</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.ar.md">العربية</a>
</p>

<p align="center">
  <i>Give four coding agents a shared radio channel. They divide the work, negotiate the
  plan, and keep broadcasting discoveries <b>while</b> they work — because listening runs as a
  background task instead of stealing a turn.</i>
</p>

This repository contains the code and data to reproduce the experiments of the paper
*AgentRadio: Passive Awareness for Long-Horizon Multi-Agent Collaboration*
([arXiv:2607.28430](https://arxiv.org/abs/2607.28430)).

> ### ☁️ Prefer the product? → **[Coral Code](https://coralcode.dev/)**
>
> **[Coral Code](https://coralcode.dev/)** is the product version of AgentRadio.
> **New users get $30 in free credit.**

### 🏆 One protocol, four agents — +29.8 points over a single agent

| Configuration | What it adds | Task acc. (Opus 4.6) | Task acc. (DeepSeek V4 Pro) |
|---|---|:---:|:---:|
| **B0** single agent | — | 32.3 % | 29.0 % |
| **B1** best of six single runs | 6× budget, no coordination | 37.9 % | 31.4 % |
| **L1** four agents + division | division of labor | 39.5 % | 31.4 % |
| **L2** + negotiation | joint planning + cross-review (blocking receive) | 51.6 % | 39.5 % |
| **L3** + passive awareness (**AgentRadio**) | background `wait_for_mention` | **62.1 %** | **50.8 %** |

The step from L2 to L3 changes **only** the communication mode. It wins 15 tasks and loses 2
with Opus 4.6 (exact McNemar test, p = 0.0023) and wins 17 while losing 3 with DeepSeek
(p = 0.0026). Four Opus 4.6 agents under AgentRadio (62.1 %) surpass the strongest
single-agent leaderboard entry, Claude Code with the newer Opus 4.8 (57.2 %).

→ [See the full results](#-results) · [paper](https://arxiv.org/abs/2607.28430) · [run it yourself](#-running-the-four-configurations)

## 📣 News

- **2026-08** — AgentRadio was covered by [VentureBeat](https://venturebeat.com/): ["Four AI agents coordinating in real time outperformed Claude Opus 4.8 on enterprise coding tasks"](https://venturebeat.com/orchestration/four-ai-agents-coordinating-in-real-time-outperformed-claude-opus-4-8-on-enterprise-coding-tasks). 📰
- **2026-07** — The AgentRadio paper is released on [arXiv](https://arxiv.org/abs/2607.28430). 🎉
- **2026-07** — Code, adapters, and the full 124-task SWE-Atlas QnA setup are open-sourced. 🚀

## 🤖 OpenCode / Claude Code / Codex Integration (`.opencode/`)

**EN** — This repo also ships an **opencode integration** (the `.opencode/` directory) that turns AgentRadio's protocol into a usable skill across **OpenCode**, **Claude Code**, and **Codex**. It adds everything below on top of the research harness:

**KO** — 이 저장소에는 AgentRadio 프로토콜을 **OpenCode**, **Claude Code**, **Codex**에서 바로 쓸 수 있게 만드는 **opencode 통합**(`.opencode/` 디렉터리)도 포함되어 있습니다. 연구용 하네스 위에 아래 기능을 모두 추가합니다:

* **Passive-awareness bus** — `plugins/agent-radio.ts` + `scripts/radio.sh` give every agent a file-based radio channel (`create-thread` / `send` / `wait_for_mention`) with **zero servers**.
  · **수동적 인지 버스** — `plugins/agent-radio.ts` + `scripts/radio.sh`로 서버 없이 모든 에이전트가 파일 기반 라디오 채널(`create-thread` / `send` / `wait_for_mention`)을 씁니다.
* **Universal memory store** — `plugins/memory-core.ts` + the [`tak2-08/memory`](https://github.com/tak2-08/memory) GitHub repo make long-term memory **shared by ALL sessions / agents / environments** (OpenCode, Claude Code, Codex). Portable CLI: `bin/memory.sh` (curl-install). Recall is mandatory before answering about prior work.
  · **범용 메모리 저장소** — `plugins/memory-core.ts` + GitHub 저장소 [`tak2-08/memory`](https://github.com/tak2-08/memory)로 장기 기억을 **모든 세션/에이전트/환경**(OpenCode, Claude Code, Codex)이 공유합니다. 이식 가능한 CLI: `bin/memory.sh`(curl 설치). 이전 작업에 답하기 전 필수 회상.
* **`/memory-dream` also plays the `/compact` role** — besides promoting daily notes to `MEMORY.md`, it writes a structured **session-compact summary** to `memory/YYYY-MM-DD.md` (and `sessions/<task-id>/compact.md` when collaborating across sessions), so the conversation can be safely truncated via the built-in `/compact` / auto-compaction and later restored with `memory_search "세션 압축"`.
  · **`/memory-dream`이 `/compact` 역할도 함** — daily 노트를 `MEMORY.md`로 승격하는 것 외에, 현재 세션 요약을 `memory/YYYY-MM-DD.md`(세션간 협업 시 `sessions/<task-id>/compact.md`)에 기록합니다. 빌트인 `/compact`/auto-compaction으로 대화를 잘라도 `memory_search "세션 압축"`으로 복원 가능.
* **Team Leader lifecycle** — a *Team Leader Session* talks to the boss (user), runs `/team-leader` to design the topology (1 leader + 1 proxy + N members) and emit copy-paste launch prompts, then orchestrates a hierarchical relay: `user → leader → proxy → member …`.
  · **팀장 세션 라이프사이클** — *팀장 세션*이 boss(유저)와 대화하고, `/team-leader`를 실행해 토폴로지(팀장 1 + 대리 1 + 팀원 N)와 복붙용 시작 프롬프트를 설계한 뒤 계층적 릴레이(`user → leader → proxy → member …`)를 조율합니다.
* **`/team-leader`** (was `/plan`) — Team Leader designs session topology + launch prompts.
  · **`/team-leader`**(구 `/plan`) — 팀장이 세션 토폴로지 + 시작 프롬프트 설계.
* **`/debate`** — proxy-moderated stance-based debate (수용/부정/긍정/조건부부정/공격/방어) among members; synthesis back to the leader, who may assign new work.
  · **`/debate`** — 대리 사회자의 입장 기반 토론(수용/부정/긍정/조건부부정/공격/방어); 종합을 팀장이 받아 신규 업무를 하달.
* **`/proxy` · `/member`** — output the Proxy / Team-Member launch prompts.
  · **`/proxy` · `/member`** — 대리 / 팀원 시작 프롬프트 출력.
* **`/cross-session`** — guide for cross-session collaboration (radio bus + memory store).
  · **`/cross-session`** — 세션 간 협업 가이드(라디오 버스 + 메모리 저장소).
* **Role templates** — `prompts/team-leader-CLAUDE.md.template`, `prompts/proxy-CLAUDE.md.template`, `prompts/member-CLAUDE.md.template` for Team Leader / Proxy / Team Member sessions.
  · **역할 템플릿** — `prompts/team-leader-CLAUDE.md.template`, `prompts/proxy-CLAUDE.md.template`, `prompts/member-CLAUDE.md.template` (팀장 / 대리 / 팀원 세션용).

### Works with `agent-shared-context`

**EN** — AgentRadio integrates naturally with **[agent-shared-context](https://github.com/tak2-08/agent-shared-context)** — a token-saving inter-agent shared context DB. Use *agent-shared-context* as the structured knowledge store and *AgentRadio* as the live collaboration / orchestration layer; together they give agents both **shared memory** and **coordinated multi-agent execution**. (The agent-shared-context README likewise points back to AgentRadio as its collaboration layer.)

**KO** — AgentRadio는 **[agent-shared-context](https://github.com/tak2-08/agent-shared-context)**(토큰 절약형 인터에이전트 공유 컨텍스트 DB)와 자연스럽게 결합합니다. *agent-shared-context*를 구조화된 지식 저장소로, *AgentRadio*를 실시간 협업/오케스트레이션 레이어로 쓰면, 에이전트는 **공유 기억**과 **조율된 멀티에이전트 실행**을 동시에 갖게 됩니다. (agent-shared-context README도 협업 레이어로 AgentRadio를 가리킵니다.)

### Usage

* **OpenCode** — the `.opencode/` folder is auto-loaded. Restart opencode; the `memory_*` and radio commands plus `/team-leader`, `/debate`, `/proxy`, `/member`, `/cross-session` are available. The plugin syncs memory to `tak2-08/memory` (set `AGENT_MEMORY_REPO` / `AGENT_MEMORY_LOCAL` / `AGENT_MEMORY_NS` to override).
  · **OpenCode** — `.opencode/` 폴더가 자동 로드됩니다. opencode를 재시작하면 `memory_*` 및 라디오 명령, `/team-leader`·`/debate`·`/proxy`·`/member`·`/cross-session`를 쓸 수 있습니다. 플러그인이 메모리를 `tak2-08/memory`에 동기화합니다(`AGENT_MEMORY_REPO` / `AGENT_MEMORY_LOCAL` / `AGENT_MEMORY_NS`로 오버라이드).
* **Claude Code** — copy `skills/agent-radio` and `skills/memory-core` into `~/.claude/skills/`, and install the portable store with `bin/memory.sh` (curl-install). Drop the role templates into your `CLAUDE.md` or a skill.
  · **Claude Code** — `skills/agent-radio`와 `skills/memory-core`를 `~/.claude/skills/`에 복사하고, 이식 가능한 저장소는 `bin/memory.sh`(curl 설치)로 설치. 역할 템플릿은 `CLAUDE.md`나 스킬에 넣습니다.
* **Codex** — same as Claude Code: copy the skills into `~/.codex/skills/` (or your codex skills dir) and install `bin/memory.sh`.
  · **Codex** — Claude Code와 동일: 스킬을 `~/.codex/skills/`(또는 codex 스킬 디렉터리)에 복사하고 `bin/memory.sh`를 설치.

See `skills/agent-radio/SKILL.md` for the full protocol, and `skills/memory-core/SKILL.md` for the memory system.
(자세한 프로토콜은 `skills/agent-radio/SKILL.md`, 메모리 시스템은 `skills/memory-core/SKILL.md` 참조.)

## 💡 Why AgentRadio

* **Communication stops costing work** — `wait_for_mention` runs as a *background task* of
  the harness, so a teammate's message surfaces at the next step boundary instead of
  consuming a turn. Agents no longer choose between working and listening.
* **Mid-execution correction** — in blocking systems a discovery cannot reach a teammate
  until the next phase boundary. Under passive awareness it lands immediately, and the
  teammate folds it into the task already in flight.
* **No harness modification** — the harness only has to run a shell command in the
  background, which mainstream coding harnesses already do. AgentRadio ships as a
  standalone message server plus three thin shell scripts.
* **No extra LLM calls** — the watcher is an ordinary OS process, not an agent step. The
  only new tokens an agent pays for are the messages that actually surface.
* **Model-agnostic** — the same protocol, prompts, and startup scripts run on Claude
  Opus 4.6 and on DeepSeek-V4-Pro through a LiteLLM translation proxy.
* **A clean ablation ladder** — B0 → L1 → L2 → L3 isolates division of labor, negotiation,
  and passive awareness one layer at a time, on identical harness settings.

## 🧩 How It Works

### The three primitives

AgentRadio exposes three operations to every agent:

| Primitive | Behavior |
|---|---|
| `create_thread(name, participants)` | Opens a named conversation on the message server and returns its identifier. |
| `send_message(thread, content, mentions)` | Appends a message to a thread and returns immediately, whether or not anyone is listening. May @-mention specific agents. |
| `wait_for_mention(timeout)` | Blocks until a message mentioning the caller arrives, then returns it together with a full snapshot of every thread — so the caller never needs a second read to reconstruct context. |

The layer takes no position on *when* an agent listens. Where `wait_for_mention` runs is the
single degree of freedom separating the two communication modes:

- **Foreground** → *blocking receive*. The agent stops working in order to listen. Every
  message heard costs a step of work. This is the L2 baseline.
- **Background task** → *passive awareness*. The agent keeps working and any mention
  surfaces at the next step boundary, with no step spent listening. This is L3, full AgentRadio.

Everything else — the primitives, the threads, the protocol — stays fixed. That single-bit
difference is what the experiments isolate.

### The five-phase protocol

Four agents run a fixed protocol of division of labor and negotiation. Agent-1 additionally
serves as the **assembler**: it opens the planning, worklog, and final-answer threads, and
gates every transition — a phase ends only after it collects an explicit approval from every agent.

1. **P1 · Explore** — every agent starts its background watcher, independently explores the
   repository, and drafts the sub-questions it sees. Nothing is sent.
2. **P2 · Divide** — the assembler opens a planning thread. Agents pool their findings,
   negotiate a partition of the sub-questions, and revise it until every agent approves.
3. **P3 · Execute** — each agent works its own sub-questions. A discovery triggers a worklog
   post the moment it is made: a finding that bears on a teammate, a contradiction with the
   agreed plan, an obstacle, or an abandoned dead end.
4. **P4 · Review** — each agent broadcasts its findings with evidence in its own results
   thread. Reviewers post factual conflicts, thin evidence, and unmentioned observations,
   and can send a sub-question back to P3.
5. **P5 · Submit** — the assembler composes the final answer from the approved results,
   broadcasts the draft for a last round of approvals, and submits.

Under blocking receive the same five phases run unchanged, but the live sharing of P3
disappears: hearing a message costs a foreground wait, so agents fall silent while they
work and a discovery cannot reach a teammate before P4.

## 🗂️ Repository Layout

```
data/qa/                          124 SWE-Atlas QnA tasks (harbor dataset scale-ai/swe-atlas-qna)
multi_agent/
  coral_multi_agent.py            L2 adapter: division + negotiation (blocking receive)
  coral_multi_agent_ablation.py   L1 adapter: division only
  coral_multi_agent_passive.py    L3 adapter: full AgentRadio (passive awareness)
  startup.sh / startup_ablation.sh / startup_passive.sh
                                  per-agent bootstrap + protocol prompts (CLAUDE.md)
  coral-agent*.toml               message-server agent definitions
  passive_scripts/                MCP-over-HTTP shell primitives (create_thread /
                                  send_message / wait_for_mention / read_resource)
  coral-server.jar                message server (download from Releases, see below)
  monitor_coral_log.sh            live thread/message monitor for running containers
run_config/qa/
  claude-token                    OAuth token helper
  full_run.sh                     B0 baseline batch runner (all 124 tasks)
  run_passive_multi_agent.sh      L3 batch runner
verify_local.py                   rubric verifier (LLM judge), run locally on a trial dir

.opencode/                         OpenCode/Claude Code/Codex integration (see "OpenCode / Claude
                                   Code / Codex Integration" above): passive radio bus, universal
                                    memory store, /team-leader /debate /proxy /member /cross-session commands,
                                   team-leader/proxy/member role templates, and the memory-core
                                   plugin synced to the tak2-08/memory GitHub repo.
```

Every task directory under `data/qa/` carries the instruction, the pinned execution
environment, and the rubric set used by the verifier.

---

## 📦 Setup

Runs execute in Docker containers on [Modal](https://modal.com), orchestrated by
[Harbor](https://github.com/laude-institute/harbor). One task = one container running the
message server plus four Claude Code agents.

### 1. Docker Desktop

Install from https://www.docker.com/products/docker-desktop/ and verify with `docker run hello-world`.

### 2. uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 3. Harbor (pinned to 0.6.4)

Newer Harbor releases (0.7+) have breaking API changes that make these adapters fail. Pin the versions:

| Component | Working version |
|-----------|-----------------|
| harbor | **0.6.4** |
| modal | **1.4.2** |

```bash
uv tool uninstall harbor 2>/dev/null || true
uv tool install 'harbor[modal]==0.6.4'
harbor --version   # must show 0.6.4
```

### 4. Modal

```bash
pip install 'modal==1.4.2'
modal --version    # must show 1.4.2
modal setup        # opens browser to log in
```

### 5. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | sh
claude --version
```

You need a **Claude Max subscription** for the agents. The verifier additionally needs an
**Anthropic API key**.

### 6. Message server JAR

The 106 MB server JAR is hosted as an anonymized artifact (too large for a git blob).
The `confirm=t` parameter bypasses the large-file scan interstitial so `curl` gets the
binary directly:

```bash
curl -L -o multi_agent/coral-server.jar \
  "https://drive.usercontent.google.com/download?id=17b40_1kXFrAC0pnN8w_7PPY13O7pYVke&export=download&confirm=t"
```

The adapters upload this JAR into each task container. Nothing needs to run locally, so no
local JDK is required.

### 7. Token helper and .env

```bash
cp run_config/qa/claude-token ~/.local/bin/claude-token
chmod +x ~/.local/bin/claude-token
cp .env.example .env      # then fill in your Anthropic API key
```

### Before each run: refresh the OAuth token

The Claude Code OAuth token rotates. Each container gets a static snapshot at launch, and a
stale token kills all four agents with 401 mid-run. Refresh before every session:

```bash
claude /login    # opens browser

security find-generic-password -s "Claude Code-credentials" -w | python3 -c "
import json, sys, os
data = json.loads(sys.stdin.read())
oauth = data.get('claudeAiOauth', {})
with open(os.path.expanduser('~/.claude/.credentials.json'), 'w') as f:
    json.dump({'claudeAiOauth': oauth}, f, indent=2)
print(f'Token refreshed. Expires at: {oauth.get(\"expiresAt\")}')
"

~/.local/bin/claude-token --check
source .env
```

---

## ⚡ Running the Four Configurations

All commands run from the repository root, after `source .env`. Task IDs are the directory
names under `data/qa/` (repeat `-i` to batch; drop `-i` entirely to run all 124). `-n` is the
number of concurrent tasks (one task = four agents for L1–L3).

### B0 — single agent (baseline)

```bash
source .env

harbor run \
  -p ./data/qa \
  -a claude-code \
  -m "anthropic/claude-opus-4-6" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "baseline-ba998" \
  -y
```

### L1 — four agents + division of labor

Agent-1 explores briefly, partitions the question, and each agent solves its share
independently. Answers are merged without review.

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent_ablation:CoralMultiAgentAblation' \
  -m "anthropic/claude-opus-4-6" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "division-ba998" \
  -y
```

### L2 — + negotiation (blocking receive)

The full five-phase protocol — joint exploration, negotiated partition to unanimity, live
execution, cross-review, assembled submission — with `wait_for_mention` running in the
**foreground**, so agents stop working in order to listen.

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent:CoralMultiAgent' \
  -m "anthropic/claude-opus-4-6" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "divneg-ba998" \
  -y
```

### L3 — + passive awareness (full AgentRadio)

Same protocol, but `wait_for_mention` runs as a **background task**: agents keep working and
messages surface between steps. Claude Code gets no MCP config — all communication goes
through the thin shell wrappers in `passive_scripts/`.

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent_passive:CoralMultiAgentPassive' \
  -m "anthropic/claude-opus-4-6" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "passive-ba998" \
  -y
```

`run_config/qa/run_passive_multi_agent.sh` wraps the same command as a batch runner, one
harbor job per task id.

---

## 🔀 Running with DeepSeek-V4-Pro

The multi-agent configurations (L1–L3) can be run with **DeepSeek-V4-Pro** agents instead of
Opus 4.6, reproducing the DeepSeek column of the results table. Everything about the
protocol, prompts, startup scripts, and resume guard is identical; only the LLM backend changes.

Claude Code speaks only the Anthropic Messages API, while DeepSeek is served through
OpenRouter (OpenAI-compatible only). We bridge the two with a **LiteLLM translation proxy
hosted once on Modal**. The task containers install nothing — they just point
`ANTHROPIC_BASE_URL` at the proxy's public URL.

The rubric verifier is unchanged: it still uses your Anthropic judge (`OPENAI_API_KEY` /
`EVAL_MODEL`). DeepSeek is only the *agent* backend.

### One-time proxy setup

```bash
# 1. An OpenRouter API key with deepseek-v4-pro access (https://openrouter.ai/keys)
#    is stored as a Modal secret — it never leaves your Modal account.
modal secret create openrouter-deepseek OPENROUTER_API_KEY=sk-or-...

# 2. Deploy the proxy. This prints your personal URL.
modal deploy multi_agent/deepseek_litellm_modal.py
# -> https://<your-user>--deepseek-litellm-proxy-serve.modal.run

# 3. Put that URL in .env so the adapters can find it:
echo 'export AGENTRADIO_PROXY_URL=https://<your-user>--deepseek-litellm-proxy-serve.modal.run' >> .env
source .env
```

The proxy stays warm (`min_containers=1`); redeploy only after editing it. To stop billing
when idle: `modal app stop deepseek-litellm-proxy` (a later `modal deploy` brings it back).

### L1 / L2 / L3 with DeepSeek

Identical to the Opus commands above, but the import path points at the DeepSeek adapter and
`-m "deepseek-v4-pro"` routes through the proxy. `source .env` must have exported
`AGENTRADIO_PROXY_URL`. Task IDs and `-i` batching work exactly as above.

#### DeepSeek B0 — single agent (baseline)

The DeepSeek baseline uses a thin subclass of the built-in `claude-code` agent (it forces the
proxy endpoint and drops the OAuth token the built-in agent would otherwise re-mint), so it
takes `--agent-import-path` rather than `-a claude-code`.

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.claude_code_deepseek:ClaudeCodeDeepseek' \
  -m "deepseek-v4-pro" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "deepseek-baseline-ba998" \
  -y
```

#### DeepSeek L1 — division only

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent_ablation_deepseek:CoralMultiAgentAblationDeepseek' \
  -m "deepseek-v4-pro" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "deepseek-division-ba998" \
  -y
```

#### DeepSeek L2 — + negotiation

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent_deepseek:CoralMultiAgentDeepseek' \
  -m "deepseek-v4-pro" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "deepseek-divneg-ba998" \
  -y
```

#### DeepSeek L3 — + passive awareness

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

harbor run \
  -p ./data/qa \
  --agent-import-path='multi_agent.coral_multi_agent_passive_deepseek:CoralMultiAgentPassiveDeepseek' \
  -m "deepseek-v4-pro" \
  -e modal -k 1 -n 1 \
  -i "task-6905333b74f22949d97ba998" \
  --ak reasoning_effort=high \
  -o results/qa/ \
  --job-name "deepseek-passive-ba998" \
  -y
```

The shared proxy injection (which swaps the LLM backend while inheriting all multi-agent
logic, startup scripts, and the resume guard) lives in `multi_agent/deepseek_proxy.py`; the
B0 baseline subclass is `multi_agent/claude_code_deepseek.py`.

### Resume a cancelled or failed job

```bash
source .env
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"
harbor job resume -p results/qa/<job-name> -f CancelledError -f RuntimeError
```

### Live monitoring (optional, separate terminal)

```bash
bash multi_agent/monitor_coral_log.sh   # renders coral://state from the running container
```

---

## 🧪 Scoring

Each trial writes the team's answer to `<trial>/agent/answer.txt`. Score it with the
benchmark's LLM judge:

```bash
source .env
python3 verify_local.py <task-id> <trial-dir>
# e.g.
python3 verify_local.py task-6905333b74f22949d97ba998 \
  results/qa/divneg-ba998/task-6905333b74f22949d97ba998__XXXXX
```

This writes `<trial>/verifier/reward.txt` (1 only when every rubric passes) and
`evaluation_results.json` (per-rubric scores). `pip install openai` if missing.

### Trial output structure

```
task-xxx__randomId/
├── config.json / result.json / trial.log
├── agent/
│   ├── answer.txt                # final answer (written by agent-1)
│   ├── coral-server.log          # threads and messages
│   └── agent-{1..4}-claude-code.txt
└── verifier/
    ├── reward.txt
    └── evaluation_results.json
```

---

## 📊 Results

Full results on SWE-Atlas QnA (124 tasks, 1,306 rubrics). Category rows give tasks resolved,
with category sizes in parentheses. Within each model column every configuration uses the
same harness and settings.

`B0` = single Claude Code · `L1` = 4× Claude Code + division of labor · `L2` = L1 +
negotiation · `L3` = L2 + passive awareness (AgentRadio).

**Opus 4.6**

| | B0 | L1 | L2 | L3 |
|---|:---:|:---:|:---:|:---:|
| Architecture and system design (44) | 15 | 13 | 24 | **30** |
| Root-cause analysis (37) | 9 | 16 | 18 | **20** |
| Code onboarding (28) | 11 | 12 | 14 | **18** |
| Security (11) | 4 | **7** | **7** | **7** |
| API and library integration (4) | 1 | 1 | 1 | **2** |
| **All tasks resolved (124)** | 40 | 49 | 64 | **77** |
| **Task accuracy (%)** | 32.3 | 39.5 | 51.6 | **62.1** |
| **Rubric pass rate (%)** | 84.2 | 86.1 | 91.3 | **93.1** |

**DeepSeek V4 Pro**

| | B0 | L1 | L2 | L3 |
|---|:---:|:---:|:---:|:---:|
| Architecture and system design (44) | 14 | 13 | 17 | **24** |
| Root-cause analysis (37) | 11 | 13 | 15 | **18** |
| Code onboarding (28) | 7 | 8 | 10 | **13** |
| Security (11) | 4 | 4 | 6 | **7** |
| API and library integration (4) | 0 | 0 | 1 | **1** |
| **All tasks resolved (124)** | 36 | 39 | 49 | **63** |
| **Task accuracy (%)** | 29.0 | 31.4 | 39.5 | **50.8** |
| **Rubric pass rate (%)** | 81.2 | 83.7 | 85.9 | **90.2** |

**L3 vs. L2, exact McNemar on paired task outcomes** — Opus 4.6: wins 15, loses 2,
p = 0.0023. DeepSeek V4 Pro: wins 17, loses 3, p = 0.0026.

Rubric-level analysis shows the passive-awareness gain growing with task difficulty,
consistent with mid-course correction as the underlying mechanism.

---

## 🛠️ Troubleshooting

- **401 errors mid-run** — the OAuth token snapshot went stale. Refresh (see above), then
  `harbor job resume -p results/qa/<job-name> -f NonZeroAgentExitCodeError`.
- **`claude: not found` in coral-server.log** — the startup scripts export
  `PATH="$HOME/.local/bin:$PATH"`; check that Claude Code installed inside the container.
- **Alpine-based tasks** — some tasks use Alpine images; the adapters auto-detect this and
  install an Alpine-compatible JDK.
- **Inspecting communication** —
  `grep "sent message\|created thread" <trial>/agent/coral-server.log | sed 's/\x1b\[[0-9;]*m//g'`

---

## 🙏 Acknowledgements

The task data is the [SWE-Atlas QnA](https://github.com/scaleapi/SWE-Atlas) benchmark
(harbor dataset `scale-ai/swe-atlas-qna`) by Scale AI. Runs are orchestrated with
[Harbor](https://github.com/laude-institute/harbor) on [Modal](https://modal.com).

---

## 📚 Citation

```bibtex
@misc{ren2026agentradio,
  title  = {AgentRadio: Passive Awareness for Long-Horizon Multi-Agent Collaboration},
  author = {Xinxing Ren and Qianbo Zang and Ziyan Wang and Caelum Forder and
            Suman Deb and Peter Carroll and Zekun Guo},
  year   = {2026},
  eprint = {2607.28430},
  archivePrefix = {arXiv},
  url    = {https://arxiv.org/abs/2607.28430}
}
```

---

## 📄 License

Released under the [Apache License 2.0](LICENSE).

---

Built at Coral AI Labs, SnT — Université du Luxembourg, King's College London, and the
University of Hull.
