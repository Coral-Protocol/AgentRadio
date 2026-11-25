# 🧠 Memory Core — 장기 기억 (GitHub-backed universal store)

이 파일은 **모든 세션, 모든 에이전트**에 자동 주입된다. 플러그인(`plugins/memory-core.ts`)이 동일 내용을 시스템 프롬프트에 매 턴 주입하므로, 이 문서는 정본이다. 체계는 OpenClaw `MEMORY.md` + `memory/YYYY-MM-DD.md`를 따르되, **저장소를 GitHub repo로 대체**했다.

## 저장소 (single source of truth)

- **GitHub repo: `tak2-08/memory`** (private) — 모든 세션/에이전트/환경이 공유하는 유일한 메모리.
- 로컬 캐시(클론): `~/.cache/agent-memory` (`AGENT_MEMORY_LOCAL`로 변경 가능).
- 매 연산: `pull → operate → push`. 로컬은 캐시.

## 파일 위치

- `MEMORY.md` — curated long-term (durable facts, preferences, decisions). 세션 시작 시 60줄 미리보기 주입.
- `memory/YYYY-MM-DD.md` — daily notes (원시 로그, 관찰, 세션 요약). `memory_search`로 인덱싱, 매 턴 주입은 오늘/어제 30줄 미리보기만.
- `agents/<ns>/` — 선택적 per-agent 네임스페이스 (`AGENT_MEMORY_NS`).

도구로 쓰는 것 외에 직접 `read`/`write`/`edit`로 파일을 편집해도 된다 — 플러그인은 파일을 소스로 본다(그 후 sync).

## 네이티브 툴 (opencode 플러그인 제공, 코어처럼 항상 있음)

| 툴 | 용도 |
|---|---|
| `memory_search` | **필수 recall**: prior work/결정/날짜/인물/선호/todos에 답하기 전 반드시 실행. `MEMORY.md`+`memory/*.md` 검색. `Source: path#line` 인용. |
| `memory_get` | `path`+`from`+`lines`로 정확한 발췌. |
| `memory_write` | `path`에 쓰기. `daily`/date는 append-only, `MEMORY.md`는 curated. 쓰면 자동 push. |
| `memory_status` | 인덱스 상태. |
| `memory_dream` | 최근 N일 daily를 훑어 `MEMORY.md` 승격 후보 제안. |

## 다른 환경(codex, claude code, 셸)

포터블 CLI `bin/memory.sh` (https://github.com/tak2-08/memory 에 있음):

```bash
curl -fsSL https://raw.githubusercontent.com/tak2-08/memory/main/bin/memory.sh \
  -o ~/.local/bin/memory && chmod +x ~/.local/bin/memory
memory search "query"; memory write --path daily --content "..."; memory get MEMORY.md
```

## 필수 recall 규칙

> **이전 작업, 결정, 날짜, 인물, 선호, todos에 관한 질문에 답하기 전에는 반드시 `memory_search`를 먼저 실행하고, 필요한 줄은 `memory_get`으로 당겨라. 확신이 낮으면 “확인했고 없었다”고 말하라.**

`memory_search` 없이 기억을 지어내지 마라. `memory_get` 없이 추측하지 마라.

## 쓰기 정책

- **Daily**: `memory/YYYY-MM-DD.md`에 append-only.
- **Curated**: `MEMORY.md`에 간결히. 주기적으로 daily에서 승격.
- **액션 민감 메모**: 승인/권한, 임시 제약, 핸드오프, 만료 조건, source/owner 명시.
- 비밀은 `MEMORY.md`에 넣지 마라.

## 자동 flush (compaction 전)

컴팩션 직전 플러그인이 `memory/YYYY-MM-DD.md`에 최근 20개 메시지를 flush하고 push.

## Dreaming (옵션, thresholded)

`memory_dream`은 최근 daily를 스캔해 `REMEMBER|DECISION|선호|항상|절대` 등 휴리스틱으로 후보를 뽑는다. 승격은 네가 `memory_write path="MEMORY.md"`로 직접. `/memory-dream` 커맨드가 이 승격을 수행한다.

## Compact (세션 압축 — `/compact` 역할)

`/memory-dream`은 빌트인 `/compact`의 **메모리 보존 역할**도 겸한다. 인자 `compact`(또는 인자 없이)로 현재 세션 요약을 `memory/YYYY-MM-DD.md`(`## 🧩 Session Compact`)와 세션간 협업 시 `sessions/<task-id>/compact.md`에 기록한다. 트랜스크립트가 압축되어도 `memory_search "세션 압축"`으로 복원. 긴 세션은 `/memory-dream` → `/compact` 순으로 실행.

## 환경 변수

| Var | Default | Purpose |
|---|---|---|
| `AGENT_MEMORY_REPO` | `tak2-08/memory` | owner/repo |
| `AGENT_MEMORY_LOCAL` | `~/.cache/agent-memory` | 로컬 클론 캐시 |
| `AGENT_MEMORY_NS` | _(empty=shared)_ | `agents/<ns>/` 네임스페이스 |

## Radio와 연동

`radio_send`로 `worklog`/`planning`에 보낸 발견은 자동으로 `memory/YYYY-MM-DD.md`에도 append+push — radio의 휘발성 bus가 daily로 durable해짐.
