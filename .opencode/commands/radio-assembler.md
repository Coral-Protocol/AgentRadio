---
description: "Radio-Assembler (팀장) 실행 — opencode 단일 세션에서 task 서브에이전트로 프록시/팀원 호출, agent-shared-context 회의실로만 조율. 사용법: /radio-assembler <목표>"
agent: build
---

# 📻 Radio-Assembler — opencode 단일 세션 오케스트레이터 실행 명령

이 명령은 **현재 opencode 세션에서** Radio-Assembler(팀장) 역할을 수행한다.
별도 세션/터미널 없이, **`task` 툴로 서브에이전트(프록시/팀원)를 호출**하고,
**모든 조율을 `agent-shared-context` 회의실(meeting room)로만 수행**한다.

---

## 사용법

```
/radio-assembler <목표 설명>
```

예: `/radio-assembler "인증 모듈 리팩토링: JWT 검증 분리, 테스트 커버리지 80% 이상"`

---

## 실행 흐름 (이 명령 호출 시 자동 수행)

### 1. 목표 상세화 (Goal Clarification)
사장(user)에게 범위·제약·마감·품질기준을 묻고 파티션 설계.

### 2. 메인 회의실 개설 (Main Meeting Room)
```bash
node tools/agent-meeting.mjs create \
  --title "${taskId} Main" \
  --type planning \
  --moderator "radio-assembler" \
  --participants "radio-proxy,radio-member-1,radio-member-2,..." \
  --agenda "${goalSummary}"
```
- 반환된 `meetingId`를 모든 서브에이전트 프롬프트에 포함.

### 3. 서브에이전트 병렬 호출 (via `task` tool)
```javascript
// 프록시 1명
await task({
  subagent_type: "radio-proxy",
  description: `Proxy for ${taskId}`,
  prompt: `당신은 프록시(대리)입니다. Task: ${taskId}. 회의실 ID: ${meetingId}. 팀장 지시 대기 후 팀원 분배·종합 수행.`
});

// 팀원 N명 (역할별 병렬)
for (const member of members) {
  await task({
    subagent_type: "radio-member",
    description: `Member-${member.role} for ${taskId}`,
    prompt: `당신은 팀원(${member.role})입니다. Task: ${taskId}. 회의실 ID: ${meetingId}. 프록시 지시 대기 후 실행·보고.`
  });
}
```

### 4. 회의실 기반 릴레이 (Meeting-Room Relay)
Radio 버스 대신 **회의실 메시지**로 계층적 릴레이:

```
사장 → 팀장(회의실: 발표/결정)
팀장 → 프록시(회의실: 지시/분배)
프록시 → 팀원(회의실: 작업 할당)
팀원 → 프록시(회의실: 진행/완료/이슈)
프록시 → 팀장(회의실: 종합/보고)
팀장 → 사장(회의실: 최종 보고) → 종료
```

### 5. 감독 게이트 (Supervision Gate)
사장의 "Ok" 타이핑 대신, 회의실에서 **`agreement` kind 발언**을 트리거로 사용:
- 팀장/프록시가 라운드 완료를 `decision` kind로 선언
- 사장이 회의실에서 `speak --kind agreement "Ok"` 하면 다음 라운드 진행

### 6. 종료 (Terminate)
팀장이 메인 회의실에서 `decision` kind로 **"작업 완료"** 선언 시:
1. 메인 회의실 `end` 호출 → 회의록 자동 생성 (`agent-context` 엔트리 저장)
2. 모든 서브에이전트 `task` 완료 대기
3. 최종 결과물 경로·검증 링크 사장에 보고

---

## 서브에이전트 정의 (이미 생성됨)

| 에이전트 | 파일 | 역할 |
|----------|------|------|
| `radio-proxy` | `.opencode/agents/radio-proxy.md` | 팀장↔팀원 허브, 분배·종합·토론 사회자 |
| `radio-member` | `.opencode/agents/radio-member.md` | 병렬 작업자, 증거 기반 실시간 보고 |

---

## 도구 사용 (이 세션에서 직접 실행)

- `node tools/agent-meeting.mjs create/join/start/speak/end/minutes/list`
- `node tools/ac.mjs meeting ...`
- `node tools/agent-search-lite.mjs` — 컨텍스트 검색
- `node tools/agent-context-index.mjs` — 인덱스 갱신 (자동)

---

## 주의사항

- **Radio 버스(RADIO_ROOT) 사용 안 함** — opencode 단일 세션에서는 회의실만 사용
- 서브에이전트는 독립 컨텍스트이므로 **회의실 ID·자신 역할 ID를 프롬프트에 반드시 포함**
- 회의록은 `agent-context/meetings/minutes/` + `agent-context/notes/` (type: meeting) 양쪽 저장 → 검색 가능
- `agent-search-lite.mjs`로 회의 내용 검색 가능