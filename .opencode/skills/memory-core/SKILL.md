---
name: memory-core
description: Stable, systematic long-term memory shared across ALL sessions, agents, and environments (opencode, codex, claude code). GitHub-backed universal store. Use when you need to remember durable facts, preferences, decisions across sessions, search prior notes, or promote daily logs to MEMORY.md. Triggers: memory_search, memory_get, MEMORY.md, daily notes, dreaming, long-term, remember this.
---

# Memory Core — 장기 기억 (GitHub-backed universal store)

OpenClaw의 `MEMORY.md` + `memory/YYYY-MM-DD.md` 체계를 이식하되, **저장소를 로컬 파일이 아닌 GitHub repo로 바꿨다.** 모든 세션·에이전트·환경(opencode, codex, claude code, 일반 셸)이 **하나의 메모리**를 공유한다.

## 저장소 (single source of truth)

- GitHub repo: **`tak2-08/memory`** (private)
- 로컬 캐시(클론): `~/.cache/agent-memory` (env `AGENT_MEMORY_LOCAL`로 변경 가능)
- 매 연산마다 `pull → operate → push` 동기화. 로컬 캐시는 캐시일 뿐.

## opencode에서 사용

플러그인(`plugins/memory-core.ts`)이 네이티브 툴을 이 repo의 로컬 클론에 연결하고 동기화한다. 재시작 후 적용.

```bash
memory_search(query, maxResults=5, minScore=0.05)  # 필수 recall
memory_get(path, from=1, lines=80)                 # 정확한 발췌
memory_write(path, content, mode="append")         # daily append-only / MEMORY.md curated
memory_status()                                     # 인덱스 상태
memory_dream(days=7)                                # MEMORY.md 승격 후보 제안
```

## 다른 환경(codex, claude code, 셸)에서 사용

포터블 CLI `bin/memory.sh` (repo에 포함) 사용:

```bash
# 설치
curl -fsSL https://raw.githubusercontent.com/tak2-08/memory/main/bin/memory.sh \
  -o ~/.local/bin/memory && chmod +x ~/.local/bin/memory
# gh auth login (https push용: gh auth setup-git)

memory write --path daily --content "decided to use Postgres for X"
memory write --path MEMORY.md --content "## Standing rule\n- Always do Y"
memory search "Postgres decision"
memory get MEMORY.md 1 40
memory status
memory dream 7
```

## 필수 recall 규칙

> 이전 작업, 결정, 날짜, 인물, 선호, todos에 답하기 전에 반드시 `memory_search`(또는 `memory search`)를 먼저 실행하고, 필요한 줄은 `memory_get`(또는 `memory get`)으로 당겨라. 확신이 낮으면 “확인했고 없었다”고 말하라.

## 쓰기 정책

- Daily: 상세 로그 → `memory/YYYY-MM-DD.md`에 append-only.
- Curated: durable facts → `MEMORY.md`. 주기적으로 daily에서 승격.
- Action-sensitive: 승인/권한, 임시 제약, 핸드오프, 만료 조건, source/owner 명시.
- 비밀은 넣지 마라 (repo는 private지만).

## 자동 flush

컴팩션 직전 플러그인이 `memory/YYYY-MM-DD.md`에 최근 20개 메시지를 flush하고 push.

## Dreaming

`memory_dream`(또는 `memory dream`)은 최근 daily를 스캔해 승격 후보 제안. 자동 쓰기 안 함 — 네가 `memory_write path="MEMORY.md"`로 승격.

`/memory-dream` 커맨드가 이 승격 단계를 수행한다(인자 `dream`=승격만).

## Compact (세션 압축 — `/compact` 역할)

`/memory-dream`은 **`/compact`의 메모리 보존 역할**도 겸한다. 빌트인 `/compact`(또는
auto-compaction)는 트랜스크립트를 자르지만, `/memory-dream compact`(또는 인자 없이 둘 다)를
먼저/함께 돌리면 현재 세션 요약이 `memory/YYYY-MM-DD.md`(`## 🧩 Session Compact`)와
`tasks/<id>/compact.md`(세션간 협업 시)에 기록되어, 압축 후에도 `memory_search "세션 압축"`으로
복원된다. 요약은 목표/수행작업/결정/미완료/다음단계 구조.

> 워크플로: 긴 세션 중간이나 컨텍스트가 차오르기 전 `/memory-dream` → 빌트인 `/compact` 순으로
> 실행하면 맥락 손실 없이 트랜스크립트를 줄일 수 있다. (플러그인의 자동 flush는 최근 20개 메시지를
> daily에 append — `/memory-dream`은 그보다 구조화된 세션 요약을 더한다.)

## 환경 변수

| Var | Default | Purpose |
|---|---|---|
| `AGENT_MEMORY_REPO` | `tak2-08/memory` | owner/repo |
| `AGENT_MEMORY_LOCAL` | `~/.cache/agent-memory` | 로컬 클론 캐시 |
| `AGENT_MEMORY_NS` | _(empty=shared)_ | `agents/<ns>/` 네임스페이스 (동시성 분리) |

## Radio와 연동

`radio_send`로 보낸 발견은 자동으로 daily에 append + push 됨.
