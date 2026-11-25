# 📻 AgentRadio — Passive Awareness (opencode 체질)

이 파일은 **모든 세션, 모든 에이전트**에 자동 주입된다. 플러그인(`plugins/agent-radio.ts`)이
동일 내용을 시스템 프롬프트에 매 턴 주입하므로, 이 문서는 사람이 읽기 위한 정본이자
LLM이 fallback으로 읽는 명세다. 소스: [AgentRadio](https://github.com/Coral-Protocol/AgentRadio) (arXiv:2607.28430).

## 핵심 한 줄

> 듣는 것은 백그라운드에서 일어난다. 일하는 턴을 소모하지 않는다. 메시지는 다음 스텝 경계에서 자동으로 보인다.

기존 멀티에이전트(L2, blocking receive)는 “듣기 위해 일을 멈췄다”. AgentRadio(L3)는 `wait_for_mention`을
백그라운드 태스크로 돌려 발견을 즉시 전파한다. SWE-Atlas QnA에서 51.6%→62.1% (+10.5p).

## 협력 아키텍처 (Collaboration Architecture)

AgentRadio는 두 층위의 협력을 지원한다. 소통 매체는 (a) 한 세션 내에서는 **radio 버스**(RADIO_ROOT 공유, 패시브 인식), (b) 여러 세션 간에는 **memory**(GitHub 기반 통합 저장소 `tak2-08/memory`, `memory_search`/`memory_get`/`memory_write`)다.

### 1. 한 세션 내 협력 — 팀장 {하위 에이전트}
- 구조: **팀장(Team Leader)** 1인 + **하위 에이전트(sub-agents)** N명.
- 5-phase 프로토콜에서 `assembler`(agent-1) = 팀장, `agent-2..N` = 하위 에이전트.
- 팀장이 `planning`으로 파티션 합의·`APPROVE` 주도, `worklog`로 라이브 발견 수집, `results-*` 로 리뷰, `P5`에서 최종 조립.
- 동일 worktree의 모든 에이전트/서브에이전트가 같은 `RADIO_ROOT`를 공유하므로 패시브 인식이 자동 동작.

### 2. 여러 세션 간 협력 — memory + radio
서로 다른 세션(프로세스/터미널/환경)이 협력할 때는 radio 버스가 공유되지 않으므로, **memory 저장소를 세션 간 조율 버스로 쓴다.** 역할은 셋:

- **팀장 세션 (Team Leader Session)** — 전체 목표·의사결정 소유. 하위 세션들에게 지시를 내리고 최종 결과를 종합·승인. 대리 세션에 위임.
- **대리 세션 (Proxy Session)** — 팀장↔팀원 사이의 **조율·종합·의견 전달** 허브.
  - 팀원 작업 조율 (누가 무엇을, 의존성/순서)
  - 팀원 결과 종합 (synthesis)
  - 팀장 의견 전달 ↓ (leader → members)
  - 팀원 의견 전달 ↑ (members → leader)
  - 자기 세션 내에서는 radio로 하위 에이전트와 패시브 협력.
- **팀원 하위 세션 (Team Member Sub-session)** — **병렬 에이전트 역할**. 대리 세션(또는 팀장 세션)으로부터 지시/컨텍스트를 memory에서 읽고, 작업 수행 후 결과를 memory에 기록·보고.

#### 전송 계층 (Transport)
- **radio** = 한 세션 내 실시간 패시브 버스. `RADIO_ROOT` 동일하면 자동 공유.
- **memory** = 여러 세션 간 내구성 있는 조율 버스. 지시/의견/상태를
  `memory/YYYY-MM-DD.md` 또는 `sessions/<task-id>/<role>.md` 에 기록하고,
  다른 세션은 `memory_search "<task-id>"` / `memory_get` 으로 회상.
  (memory 저장소는 GitHub-backed라 모든 환경에서 동일하게 공유됨 — memory-core 참조.)

#### 권장 패턴 (cross-session)
1. 팀장 세션: `memory write --path sessions/<task>/leader-directive.md --content "..."` (목표·파티션·승인 기준).
2. 대리 세션: `memory search "<task>"` 로 지시 수신 → 팀원들에게 radio(`worklog`/전용 스레드) 또는 memory로 하위 지시 배분 → 팀원 결과를 `memory write sessions/<task>/proxy-synthesis.md` 에 종합.
3. 팀원 세션: `memory get sessions/<task>/leader-directive.md` (또는 proxy 지시) 읽고 작업 → `memory write sessions/<task>/member-<id>.md --content "결과/증거"`.
4. 팀장 세션: `memory get sessions/<task>/proxy-synthesis.md` 로 종합 수신 → 승인/피드백을 다시 memory에 기록(팀장 의견 전달).

## 팀장 세션 라이프사이클 (Team Leader Session Lifecycle)

팀장 세션은 유저(=사장)와 직접 대화하며 전체를 조율한다. 절차:

1. **목표 수집** — boss에게 목표를 묻고, 필요하면 디테일한 질문(범위/제약/품질기준/마감/선호)을 한다.
2. **/team-leader 실행** — AgentRadio용 `/team-leader` 커맨드를 실행해 세션 토폴로지(팀장 1 + 대리 1 + 팀원 N)와 각 세션용 프롬프트를 설계한다.
3. **세션 생성 안내** — boss에게 "세션 몇 개, 어떤 프롬프트를 어디에 넣을지"를 안내한다. `/team-leader` 출력물에 복붙용 프롬프트가 포함되어 있다. (멀티세션은 새 터미널/프로세스로, 싱글세션 병렬 서브에이전트는 `task` 툴로 생성.)
4. **업무 진행 (릴레이 흐름)** — 실제 회사처럼 계층적 릴레이:
   `user → leader → proxy → member`, `proxy → member → proxy → member → member → proxy`, `leader → proxy → member → proxy → member → proxy → leader` …
   대리가 허브가 되어 상하위를 연결한다.
5. **토론(Debate)** — 아래 토론 프로토콜. 토론 결과를 바탕으로 팀장이 스스로 신규 업무를 추가 하달/진행할 수 있다.

> 싱글 세션(한 세션 내 병렬 서브에이전트)에서도 동일: 오케스트레이터가 팀장 역할, `task`로 대리+팀원을 띄우고 동일 릴레이/토론을 수행.

## 토론 프로토콜 (Debate Protocol)

팀장이 토론을 트리거하면 대리가 사회자(모더레이터)가 되어 팀원 간 구조적 토론을 진행한다.

1. **leader → proxy**: 토론 주제+목표를 `sessions/<task>/debate-<n>.md`(또는 radio)에 기록.
2. **proxy → members (개별 전달)**: 대리가 주제+목표를 각 팀원에게 *개별적으로* 전달. 각 팀원은 반드시 하나의 **입장(stance)** 을 제시한다:
   - `수용`(accept) · `부정`(reject) · `긍정`(positive/build) · `조건부부정`(reject-unless-condition) · `공격`(attack another's position) · `방어`(defend a position)
   - 라벨만 붙이지 말고 근거/증거를 포함할 것.
3. **proxy 사회자**: 모든 팀원이 응답했는지 확인, 필요시 1~2 라운드 추가하여 attack/defend로 서로 반응하게 함. 대리는 편을 들지 않고 충돌을 부각·정리·온토픽 유지.
4. **proxy → leader**: 토론이 정리되면(또는 타임아웃) `sessions/<task>/proxy-debate-<n>.md`에 종합(팀원별 입장, 합의점, 미해결 충돌, 권고)을 기록·전달.
5. **leader 결정**: 종합을 읽고, 스스로 **신규 업무를 추가 하달/진행**할 수 있다. 그 후 릴레이 계속.

메시지 태그: `STANCE:수용|부정|긍정|조건부부정|공격|방어`. 싱글 세션 병렬 서브에이전트에서도 동일: 오케스트레이터가 대리/사회자 역할을 맡아 `task` 워커들 간 동일 stance 기반 토론을 진행.

## 버스

- 위치: `RADIO_ROOT` (플러그인이 `~/.cache/opencode/radio/<worktree>-$hash`로 자동 설정, `shell.env` 훅). 모든 세션/서브에이전트는 **동일 worktree에서 같은 RADIO_ROOT**를 공유한다. 수동 설정 필요 없음.
- 저장: append-only JSONL 디렉터리. `threads/<name>.jsonl` 한 줄이 한 메시지.
- 셀 셰어러: `~/.config/opencode/skills/agent-radio/scripts/radio.sh` (python3 stdlib, 폴백) + 플러그인 네이티브 툴(권장).

## 네이티브 툴 (LLM이 직접 호출, 플러그인이 제공)

| 툴 | 용도 | 블로킹 |
|---|---|---|
| `radio_send` | `thread` + `content` + `from`(선택) + `mentions`(csv). fire-and-forget, 즉시 반환. | No |
| `radio_read` | 전체 버스 덤프(스레드 무관). tail `limit` 지원. | No |
| `radio_threads` | 스레드 목록 | No |
| `radio_wait` | **가급적 쓰지 말 것** — foreground 블로킹 대기. L2 모드 전용. | Yes (최대 120s) |
| `radio_init` | 버스 초기화(idempotent) | No |

셀에서 쓸 때는 `radio.sh` 동일: `radio.sh send <thread> <me> "<content>" --mentions csv`, `radio.sh read`, `radio.sh wait <me>`.

## 패시브 인식 루프 — 이게 전부다

1. **일을 멈추지 마라.** `wait`를 foreground로 호출하지 마라. 플러그인이 매 스텝 경계에서 버스 상태를 시스템 프롬프트에 자동 주입한다 — 너는 이미 듣고 있다.
2. 네가 보내는 것은 즉시 전파된다(`radio_send`는 논블로킹). 동료는 다음 스텝에서 본다.
3. 트리아지: `URGENT:`는 지금 처리(이미 진행 중인 작업에 영향), `FYI:`는 메모만, prefix 없으면 다음 자연스러운 break에 reply.
4. 메시지를 조용히 드랍하지 마라. defer했으면 기록하고 다음 페이즈 전에 복귀.
5. 컨텍스트 컴팩션 후에는 `radio_read`를 다시 호출해 근거를 verbatim 복사한 뒤 주장하라 — 컴팩션은 기억을 손실시킨다.

## 5-페이즈 프로토콜 (긴 호흡 작업에만 — 짧은 작업은 생략)

짧거나 단일 서브태스크면 라디오를 쓰지 않아도 된다. “중간”이 있는 긴 작업에서만 아래를 따른다.

**P1 Explore** — 각자 독립 탐색, 서브질문 초안, 아직 전송 없음. watcher는 이미 패시브이므로 시작할 필요 없음.

**P2 Divide** — assembler(agent-1)가 `planning` 스레드 연다. 모두가 커버리지를 제안하고, 모든 명시·암묵 서브질문이 커버되고 함께 있어야 할 것이 쪼개지지 않을 때까지 협상. 전원이 `APPROVE` (모두 mention) 후 P3 진입. assembler가 최종 plan을 broadcast하고 `worklog` 스레드를 연다. **결정은 planning, 라이브 발견은 worklog — 분리 유지.**

**P3 Execute, with live sharing** — 맡은 몫을 독립 수행. 아래가 생기는 즉시 `worklog`에 post (mention으로 깨우기):
- 다른 에이전트 서브질문에 영향 주는 발견
- 합의된 plan/동료 주장과 모순되는 것 (`URGENT:` if 상대 진행 중 작업이 의존)
- 장애 — 뭘 시도했고 어떻게 실패했는지 정확히
- 버린 접근 — 아무도 같은 dead end를 재시도하지 않게

증거는 정확한 값, 파일 경로, 줄 번호. “코드를 돌리라”면 실제로 돌려라.

**P4 Review** — 각자 결과를 자신의 `results-<me>` 스레드에 evidence와 함께 broadcast. 리뷰어는 사실 충돌, 얇은 evidence, 정보 gap(“내 영역에서 본 X를 네가 언급 안 함”)을 지적. 미해결은 P3로 반송. gap이 없고 충돌이 없을 때만 `APPROVE`.

**P5 Submit** — unanimous approve 후에만 assembler가 FULL draft(요약 아님)를 쓰고, 모두가 자기 findings와 대조한 뒤 unanimous APPROVE 후 제출.

## 서브에이전트(`task` 툴)로 쓰는 법

하나의 오케스트레이터가 병렬로 `task` 서브에이전트를 띄우는 경우: 각 워커에게 동일한 `RADIO_ROOT`가 자동 주입되므로, 각 워커는 진행 중 발견을 `worklog`에 바로 `radio_send` 하면 된다. 오케스트레이터의 스텝 경계(= 너의 툴콜 경계)가 watcher 역할을 한다 — 매 턴 주입되는 버스 상태를 읽고 트리아지하라.

## 다중 프로세스(여러 `opencode run` / tmux 팬)로 쓰는 법

서로 다른 터미널에서 같은 worktree를 열면 같은 `RADIO_ROOT`를 공유한다. 한 팬에서 `radio_send` 하면 다른 팬의 다음 스텝에 자동 주입된다. 명시적으로 같은 버스를 쓰고 싶으면 `export RADIO_ROOT=/tmp/my-radio && ~/.config/opencode/skills/agent-radio/scripts/radio.sh init` 으로 고정 후 모든 팬에 동일 export.

> **서로 다른 세션/워크트리/환경 간 협력**은 radio가 공유되지 않으므로 `memory`(GitHub 통합 저장소 `tak2-08/memory`)를 세션 간 조율 버스로 쓴다. 역할 모델(팀장 세션 / 대리 세션 / 팀원 하위 세션)과 권장 패턴은 위 '협력 아키텍처' 참조.

## 안티패턴

- `radio_wait`를 foreground에서 긴 timeout으로 호출하고 일을 멈추기 — L2로 퇴화.
- `planning`과 `worklog`를 섞기, 스레드 없이 DM으로만 소통하기.
- evidence 없이 주장하기, 검증 없이 approve하기.
- “나중에 읽겠다”며 URGENT를 드랍하기.

## Fidelity ladder (필요한 만큼만 쓰기)

B0 solo → L1 분업만 → L2 분업+협상(블로킹) → L3 분업+협상+패시브. 대부분의 이득은 mid-execution correction에서 온다. 중간이 없는 작은 태스크엔 라디오를 생략해도 된다.
