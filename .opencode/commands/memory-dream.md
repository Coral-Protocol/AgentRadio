---
description: "꿈(Dream)+압축(Compact): 최근 daily를 MEMORY.md로 승격하고, 현재 세션 요약을 메모리에 기록해 컨텍스트 압축(/compact) 후에도 맥락 보존. 인자: (없음)=둘 다, 'compact'=압축만, 'dream'=승격만"
agent: build
---

# /memory-dream — Dream + Compact

이 명령은 두 역할을 한다:
- **Dream**: 최근 daily 노트를 훑어 `MEMORY.md`로 승격 (기존 동작).
- **Compact**: 현재 세션(대화)의 핵심을 구조화 요약해 메모리에 기록 → 빌트인 `/compact`(또는
  auto-compaction)로 트랜스크립트가 잘려도 맥락이 보존된다. 즉 이 명령이 **`/compact`의
  "메모리 보존" 역할을 대신**한다.

인자(`$ARGUMENTS`):
- 비어 있음 → Dream + Compact 둘 다
- `compact` → Compact(세션 요약)만
- `dream` → Dream(승격)만
- 숫자(예 `7`) → Dream 범위(days)로 쓰고 Compact도 함께

## Dream 단계 (인자에 따라)
1. `memory_dream` days=7(또는 숫자 인자) 로 후보 스캔.
2. durable 후보는 `memory_write path="MEMORY.md"` 로 curated 승격(간결하게).
3. 아직 daily에 없는 세션 결과는 `memory_write path="daily"` 로 append.

## Compact 단계 (인자에 따라) — /compact 역할
현재 대화 전체를 훑어 다음을 추출, **간결한** 세션 압축 요약을 만든다(토큰 절약, 핵심만):
- **목표/요청**: 사용자가 원한 것
- **수행한 작업**: 단계별 + 검증(실행한 명령/나온 결과 요약)
- **결정/결론**: 내린 결정과 그 근거
- **미완료/열린 스레드**: 남은 것, 블로커, 확인 필요 사항
- **다음 단계/인계**: 이후 할 일, 다른 세션/에이전트에 넘길 인계 사항

기록 위치:
- 항상 `memory/YYYY-MM-DD.md` 에 `## 🧩 Session Compact <HH:MM>` 섹션으로 append
  (`memory_search` 인덱싱 대상 → 압축 후 복원 가능).
- 세션간 협업 중 task id를 아는 경우 `sessions/<task-id>/compact.md` 에도 기록(다른 세션이
  `memory_get` 으로 복원).
- 동시에 이 요약을 사용자에게 **출력** → 이것이 "압축된 컨텍스트" 본문이다.

## 출력
- Dream 모드: (a) MEMORY.md 승격 항목, (b) daily 잔류 항목, (c) 제안 next-action(실행 금지).
- Compact 모드: 세션 압축 요약 본문. 이후 빌트인 `/compact` 실행 또는 auto-compaction 발생 시,
  `memory_search "세션 압축"` 으로 요약을 복원할 수 있음을 안내.
- 둘 다: 위 두 출력을 순서대로.

규칙: daily는 append-only, MEMORY.md는 curated(간결), 비밀 금지. Compact 요약은 **사실 기반**
(대화에 없는 내용을 지어내지 말 것).

Non-opencode fallback: `memory dream 7`(승격) · 세션 요약은 `memory write --path daily
--content "## 🧩 Session Compact ...본문..."`(CLI from https://github.com/tak2-08/memory).
