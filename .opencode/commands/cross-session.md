---
description: "Cross-session (세션 간 협력): 별도 세션/프로세스 간 조율 버스로 설치 유저의 개인 GitHub memory repo (agent-shared-context agent-memory.mjs) 를 사용. 사용법: /cross-session"
agent: build
---

# 🌐 Cross-session (세션 간 협력) — AgentRadio

서로 다른 세션/프로세스/환경이 협력할 때는 radio 버스가 공유되지 않는다.
이 명령은 **설치 유저의 개인 GitHub memory repo** (`agent-shared-context`의 `agent-memory.mjs`가
최초 사용 시 자동 생성)를 **세션 간 조율 버스**로 쓰는 패턴을 정의한다.

> ⚠️ **중앙 `tak2-08/memory` 는 사용하지 않는다.** 각 유저는 자신의 GitHub 계정에
> `agent-shared-context-memory` (private) repo를 가지며, 모든 메모리 데이터는 그곳에만 저장된다.

## 전송 계층 (Transport)
- **radio** = 한 세션 내 실시간 패시브 버스 (`RADIO_ROOT` 동일 시 자동 공유)
- **memory** = 여러 세션 간 내구성 있는 조율 버스 → **유저 개인 GitHub repo** (`ac.mjs memory`)

## 권장 패턴 (Recommended pattern)
1. **팀장 세션**: `ac.mjs memory write sessions/<task-id>/leader-directive.md "목표·파티션·승인 기준"`
2. **대리 세션**: `ac.mjs memory search "<task-id>"` 로 지시 수신 → 팀원에게 radio(worklog) 또는 memory로 하위 지시 배분 → 팀원 결과를 `ac.mjs memory write sessions/<task-id>/proxy-synthesis.md` 에 종합
3. **팀원 세션**: `ac.mjs memory get sessions/<task-id>/leader-directive.md` (또는 대리 지시) 읽고 작업 → `ac.mjs memory write sessions/<task-id>/member-<id>.md "결과/증거"`
4. **팀장 세션**: `ac.mjs memory get sessions/<task-id>/proxy-synthesis.md` 로 종합 수신 → 승인/피드백을 다시 memory에 기록

## 규칙
- 모든 지시/의견/상태는 `sessions/<task-id>/` 아래에 기록 (라벨: leader-directive / proxy-synthesis / member-<id> / leader-feedback).
- `ac.mjs memory search` 로 회상 전에는 이전 결정을 지어내지 마라.
- radio 에 보낸 `worklog`/`planning` 발견은 memory 에도 자동 append 되므로, 중요한 건 `ac.mjs memory dream` 으로 `MEMORY.md` 승격 고려.

## 메모리 초기화
최초 실행 시 `ac.mjs memory status` 로 개인 repo가 자동 생성된다 (`gh auth login` 필요).
수동 지정: `agent-context.config.json` 의 `live.memory.repo` 에 `owner/repo` 설정.
