---
description: "Debate (토론): proxy가 사회자로 팀원 간 구조적 stance 토론 진행. 수용/부정/긍정/조건부부정/공격/방어로 입장 제시, 종합 후 팀장에 권고. 사용법: /debate <주제>"
agent: build
---

# ⚖️ Debate (토론) — AgentRadio

팀장이 토론을 트리거하면 **대리(proxy)가 사회자(모더레이터)**가 되어 팀원 간 구조적 토론을 진행한다.

## 입력
`$ARGUMENTS` = 토론 주제 + 목표 (팀장이 내린 것).

---

## 프로토콜
1. **leader → proxy**: 주제+목표를 `sessions/<task-id>/debate-<n>.md` (또는 radio)에 기록.
2. **proxy → members (개별 전달)**: 대리가 주제+목표를 각 팀원에게 *개별적으로* 전달.
   각 팀원은 반드시 하나의 **입장(stance)** 을 제시한다 — 근거/증거 포함:
   - `수용`(accept) · `부정`(reject) · `긍정`(positive/build) · `조건부부정`(reject-unless-condition) · `공격`(attack another's position) · `방어`(defend a position)
3. **proxy 사회자**: 모든 팀원 응답 확인, 필요시 1~2 라운드 추가해 attack/defend로 서로 반응하게 함.
   대리는 **편을 들지 않고** 충돌을 부각·정리·온토픽 유지.
4. **proxy → leader**: 토론 정리되면(또는 타임아웃) `sessions/<task-id>/proxy-debate-<n>.md` 에 종합(팀원별 입장, 합의점, 미해결 충돌, 권고) 기록·전달.
5. **leader 결정**: 종합을 읽고 스스로 **신규 업무를 추가 하달/진행**. 그 후 릴레이 계속.

## 메시지 태그
`STANCE:수용|부정|긍정|조건부부정|공격|방어`

> 단일 세션(한 세션 내 병렬 서브에이전트)에서도 동일: 오케스트레이터가 대리/사회자 역할을 맡아 `task` 워커들 간 동일 stance 기반 토론 진행.
