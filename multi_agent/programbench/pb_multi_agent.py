"""
Pier agent: message server + 4 Claude Code instances on ONE ProgramBench task in a
SHARED working tree, under a hard wall-clock budget, with periodic workspace snapshots
graded offline with `programbench eval` (same grading as the B0 adapter).

Two conditions, selected with ``--ak variant=l25|l3`` or the subclasses below:
  l25  fixed communication windows (W1 split, W2 review, W3 wrap-up), MCP tools,
       blocking receive, silence outside windows
  l3   share as you go, shell scripts, background watcher (passive awareness)
  l3h  share as you go, shell scripts to send; a Claude Code PostToolUse hook delivers
       new peer messages after every tool call (harness-level passive awareness)
  l25p L2.5 windows kept (MCP tools, blocking receive inside windows); the working phases
       between them use the L3 share-as-you-go rules, but nothing is pushed: agents
       receive by reading coral://state themselves
The prompt text that is not about communication is generated from the same source for
both (see startup_pb.sh); only the communication section and the timeline differ.

Layout inside the container:
  /tmp/pb                prompt.md, bells.txt, start_epoch, STOP, session.json,
                         next_bell.sh, bin/git (guard), pb_runner.sh
  /tmp/coral-workspace   coral-server.jar, pb-agent/{coral-agent.toml, startup_pb.sh,
                         passive_scripts/, instances/<session>/<agent>/}
  /workspace             the shared tree (owned by the `agent` user)
  /logs/agent            run.log, snapshots/, agent-N-claude-code.txt, coral-server.log

Usage:
  PYTHONPATH=/home/xinxing/deep-swe CLAUDE_CODE_OAUTH_TOKEN=... pier run -p pb_tasks -i pandoc \
    --agent-import-path pb_agent.pb_multi_agent:ProgramBenchCoralL3 \
    --model anthropic/claude-opus-5-5 --env docker \
    --ak budget_minutes=60 --ak snapshot_minutes=5 --job-name pb-l3-local-pandoc-60m-01
"""

import json
import os
import shlex
import tempfile
from pathlib import Path

from pier.agents.installed.base import BaseInstalledAgent
from pier.environments.base import BaseEnvironment
from pier.models.agent.context import AgentContext
from pier.models.agent.install import AgentInstallSpec, InstallStep
from pier.models.agent.network import NetworkAllowlist

HERE = Path(__file__).parent
# coral-server.jar and passive_scripts/ live in multi_agent/: a sibling of this package in
# the deep-swe checkout (pb_agent/ next to multi_agent/), the parent directory in the
# AgentRadio repository (multi_agent/programbench/).
MULTI_AGENT_DIR = HERE.parent / "multi_agent" if (HERE.parent / "multi_agent" / "passive_scripts").is_dir() else HERE.parent
CORAL_SERVER_JAR = MULTI_AGENT_DIR / "coral-server.jar"
PASSIVE_SCRIPTS_DIR = MULTI_AGENT_DIR / "passive_scripts"
PASSIVE_SCRIPTS = [
    "coral_mcp_lib.sh",
    "coral_json.py",
    "wait_for_mention.sh",
    "send_message.sh",
    "create_thread.sh",
    "read_resource.sh",
]
STARTUP = HERE / "startup_pb.sh"
RUNNER = HERE / "pb_runner.sh"
BELL_SCRIPT = HERE / "pb_scripts" / "next_bell.sh"
GIT_GUARD = HERE / "pb_scripts" / "git"
TS_SCRIPT = HERE / "pb_scripts" / "ts.py"
INBOX_HOOK = HERE / "pb_scripts" / "inbox_hook.py"

PB_DIR = "/tmp/pb"
WS = "/tmp/coral-workspace"
AGENT_NAME = "pb-agent"
AGENT_DIR = f"{WS}/{AGENT_NAME}"
AGENT_USER = "agent"
AGENT_HOME = "/home/agent"
JDK_URL = "https://api.adoptium.net/v3/binary/latest/24/ga/linux/x64/jdk/hotspot/normal/eclipse"
DEFAULT_CLAUDE_CODE_VERSION = "2.1.310"
DEFAULT_MODEL = "claude-opus-5-5"
N_AGENTS = 4

VARIANTS = {
    "l25": {
        "label": "L2.5 fixed windows (blocking receive)",
        # minute -> bell text, for a 60-minute budget (scaled for other budgets)
        "bells": [
            (5, "W1 OPEN: split window. Post your BRIEF in the team thread; agent-1 posts the SPLIT; run the window loop until W1 CLOSE."),
            (10, "W1 CLOSE: silent implementation until W2 (minute 30). No sends, no waits, no state reads."),
            (30, "W2 OPEN: review window. Post STATUS (DONE/CLAIM/FACT/REQUEST/FAIL), review one peer module, agent-1 answers REQUESTs; loop until W2 CLOSE."),
            (35, "W2 CLOSE: silent implementation until W3 (minute 50)."),
            (45, "15 minutes left."),
            (50, "W3 OPEN: wrap-up window. Final STATUS and open FAILs; agent-1 assigns fixes and runs the fresh-copy check; loop until W3 CLOSE."),
            (54, "W3 CLOSE: fix only what W3 assigned, silently."),
            (58, "FREEZE: stop editing the shared tree now. Final snapshot at the deadline."),
        ],
    },
    "l3": {
        "label": "L3 share as you go (passive awareness)",
        "bells": [
            (5, "5 minutes elapsed: post your BRIEF in the team thread now."),
            (10, "10 minutes elapsed: the SPLIT should be posted by now (agent-1); peers claim modules."),
            (30, "30 minutes left."),
            (45, "15 minutes left."),
            (55, "5 minutes left: finish the piece you are in, commit, make sure the tree compiles."),
            (58, "FREEZE: stop editing the shared tree now. Final snapshot at the deadline."),
        ],
    },
}
VARIANTS["l25p"] = {
    "label": "L2.5 windows + share-as-you-go working phases (self-read receive)",
    "bells": [
        (5, "W1 OPEN: split window. Post your BRIEF in the team thread; agent-1 posts the SPLIT; run the window loop until W1 CLOSE."),
        (10, "W1 CLOSE: working phase until W2 (minute 30): implement, share as you go, no blocking waits; read coral://state yourself to receive."),
        (30, "W2 OPEN: review window. Post STATUS (DONE/CLAIM/FACT/REQUEST/FAIL), review one peer module, agent-1 answers REQUESTs; loop until W2 CLOSE."),
        (35, "W2 CLOSE: working phase until W3 (minute 50): implement, share as you go, no blocking waits; read coral://state yourself to receive."),
        (45, "15 minutes left."),
        (50, "W3 OPEN: wrap-up window. Final STATUS and open FAILs; agent-1 assigns fixes and runs the fresh-copy check; loop until W3 CLOSE."),
        (54, "W3 CLOSE: fix only what W3 assigned; post FIXED when done; no blocking waits; read coral://state yourself to receive."),
        (58, "FREEZE: stop editing the shared tree now. Final snapshot at the deadline."),
    ],
}
VARIANTS["l3h"] = {
    "label": "L3 share as you go (hook-delivered passive awareness)",
    "bells": VARIANTS["l3"]["bells"],  # same clock as l3; only the receive channel differs
}


def _agent_toml(label: str) -> str:
    return f"""edition = 3

[agent]
name = "{AGENT_NAME}"
version = "0.1.0"
description = "ProgramBench team peer ({label})"

readme = "Claude Code agent rebuilding a program with three peers in a shared tree ({label})"
summary = "4 agents, one shared workspace, wall-clock budget"

[agent.license]
type = "spdx"
expression = "MIT"

[options.auto_launch]
type = "string"
default = "true"

[runtimes.executable]
path = "bash"
arguments = ["startup_pb.sh"]
transport = "streamable_http"
"""


class ProgramBenchCoralTeam(BaseInstalledAgent):
    SUPPORTS_ATIF: bool = False
    VARIANT: str = "l3"

    def __init__(
        self,
        logs_dir: Path,
        variant: str | None = None,
        claude_code_version: str = DEFAULT_CLAUDE_CODE_VERSION,
        budget_minutes: int | str = 60,
        snapshot_minutes: int | str = 5,
        effort: str = "xhigh",
        *args,
        **kwargs,
    ):
        self._variant = (variant or self.VARIANT).lower()
        if self._variant not in VARIANTS:
            raise ValueError(f"variant must be one of {sorted(VARIANTS)}, got {variant!r}")
        self._cc_version = str(claude_code_version)
        self._budget = int(budget_minutes)
        self._snap = int(snapshot_minutes)
        self._effort = str(effort)
        super().__init__(logs_dir, *args, **kwargs)

    @staticmethod
    def name() -> str:
        return "programbench-coral-team"

    def get_version_command(self) -> str | None:
        return None

    def parse_version(self, stdout: str) -> str:
        return "0.1.0"

    @property
    def _cfg(self) -> dict:
        return VARIANTS[self._variant]

    # ------------------------------------------------------------------ install
    def install_spec(self) -> AgentInstallSpec:
        root_run = (
            "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; "
            "command -v curl >/dev/null || (apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null); "
            f"curl -fsSL {shlex.quote(JDK_URL)} -o /tmp/jdk24.tar.gz && "
            "mkdir -p /opt/java && tar -xzf /tmp/jdk24.tar.gz -C /opt/java --strip-components=1 && "
            "rm -f /tmp/jdk24.tar.gz && ln -sf /opt/java/bin/java /usr/local/bin/java && java -version && "
            f"mkdir -p {AGENT_HOME} && chown -R {AGENT_USER}:{AGENT_USER} {AGENT_HOME}"
        )
        agent_run = (
            f"set -euo pipefail; export HOME={AGENT_HOME}; cd $HOME; "
            f"curl -fsSL https://claude.ai/install.sh | bash -s -- {shlex.quote(self._cc_version)} && "
            'export PATH="$HOME/.local/bin:$PATH" && claude --version'
        )
        return AgentInstallSpec(
            agent_name=self.name(),
            version=self._cc_version,
            steps=[
                InstallStep(user="root", run=root_run, env={"DEBIAN_FRONTEND": "noninteractive"}),
                InstallStep(user=AGENT_USER, run=agent_run, env={"HOME": AGENT_HOME}),
            ],
            verification_command=(
                f'export HOME={AGENT_HOME}; export PATH="$HOME/.local/bin:$PATH"; claude --version && java -version'
            ),
        )

    def network_allowlist(self) -> NetworkAllowlist:
        return NetworkAllowlist(domains=["api.anthropic.com"])

    # ------------------------------------------------------------------ helpers
    async def _upload_text(self, environment: BaseEnvironment, text: str, remote: str) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=Path(remote).suffix, delete=False) as f:
            f.write(text)
            tmp = f.name
        try:
            await environment.upload_file(tmp, remote)
        finally:
            os.unlink(tmp)

    def _bells_text(self) -> str:
        scale = self._budget / 60.0
        lines = []
        for minute, text in self._cfg["bells"]:
            m = max(1, round(minute * scale))
            lines.append(f"{m}\t{text}")
        return "\n".join(lines) + "\n"

    def _session_json(self) -> str:
        return json.dumps({
            "agentGraphRequest": {
                "agents": [
                    {
                        "id": {"name": AGENT_NAME, "version": "0.1.0", "registrySourceId": {"type": "local"}},
                        "name": f"agent-{i}",
                        "provider": {"type": "local", "runtime": "executable"},
                        "description": "ProgramBench team peer" + (" (core owner)" if i == 1 else ""),
                        "options": {},
                        "blocking": False,
                    }
                    for i in range(1, N_AGENTS + 1)
                ],
                "groups": [[f"agent-{i}" for i in range(1, N_AGENTS + 1)]],
            },
            "namespaceProvider": {
                "type": "create_if_not_exists",
                "namespaceRequest": {"name": "pb", "deleteOnLastSessionExit": False},
            },
            "execution": {"mode": "immediate", "runtimeSettings": {"ttl": 86400000}},
        })

    def _runtime_env(self) -> dict[str, str]:
        env: dict[str, str] = {}
        oauth = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")
        api_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN") or ""
        if oauth:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = oauth
        elif api_key:
            env["ANTHROPIC_API_KEY"] = api_key
        env["PB_VARIANT"] = self._variant
        env["PB_MODEL"] = (self.model_name or DEFAULT_MODEL).split("/")[-1]
        env["PB_EFFORT"] = self._effort
        env["PB_BUDGET_MIN"] = str(self._budget)
        env["PB_SNAP_MIN"] = str(self._snap)
        env["PB_DIR"] = PB_DIR
        env["PB_WORKSPACE"] = "/workspace"
        env["CORAL_WS"] = WS
        env["CORAL_AGENT_DIR"] = AGENT_DIR
        env["HOME"] = AGENT_HOME
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["DISABLE_AUTOUPDATER"] = "1"
        env["CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL"] = "1"
        env["IS_SANDBOX"] = "1"
        env["PAGER"] = "cat"
        env["MANPAGER"] = "cat"
        return env

    # ------------------------------------------------------------------ run
    async def run(self, instruction: str, environment: BaseEnvironment, context: AgentContext) -> None:
        env = self._runtime_env()
        prompt = instruction.rstrip() + "\n"
        if self._budget != 60:
            prompt = prompt.replace("budget of 60 minutes", f"budget of {self._budget} minutes")

        for p in [CORAL_SERVER_JAR, STARTUP, RUNNER, BELL_SCRIPT, GIT_GUARD, TS_SCRIPT, INBOX_HOOK, *(PASSIVE_SCRIPTS_DIR / n for n in PASSIVE_SCRIPTS)]:
            if not p.exists():
                raise RuntimeError(f"Required file not found: {p}")

        # 1. directories (root), then uploads
        await self.exec_as_root(
            environment,
            command=(
                f"mkdir -p {PB_DIR}/bin /logs/agent {AGENT_DIR}/passive_scripts {AGENT_DIR}/instances && "
                f"chmod 777 /logs/agent {PB_DIR} {PB_DIR}/bin && chown -R {AGENT_USER}:{AGENT_USER} {WS} {PB_DIR}"
            ),
        )
        await environment.upload_file(CORAL_SERVER_JAR, f"{WS}/coral-server.jar")
        await environment.upload_file(STARTUP, f"{AGENT_DIR}/startup_pb.sh")
        await self._upload_text(environment, _agent_toml(self._cfg["label"]), f"{AGENT_DIR}/coral-agent.toml")
        for n in PASSIVE_SCRIPTS:
            await environment.upload_file(PASSIVE_SCRIPTS_DIR / n, f"{AGENT_DIR}/passive_scripts/{n}")
        await environment.upload_file(RUNNER, f"{PB_DIR}/pb_runner.sh")
        await environment.upload_file(BELL_SCRIPT, f"{PB_DIR}/next_bell.sh")
        await environment.upload_file(GIT_GUARD, f"{PB_DIR}/bin/git")
        await environment.upload_file(TS_SCRIPT, f"{PB_DIR}/ts.py")
        await environment.upload_file(INBOX_HOOK, f"{PB_DIR}/inbox_hook.py")
        await self._upload_text(environment, prompt, f"{PB_DIR}/prompt.md")
        await self._upload_text(environment, self._bells_text(), f"{PB_DIR}/bells.txt")
        await self._upload_text(environment, self._session_json(), f"{PB_DIR}/session.json")
        await self.exec_as_root(
            environment,
            command=(
                f"chmod 755 {AGENT_DIR}/startup_pb.sh {AGENT_DIR}/passive_scripts/*.sh {PB_DIR}/pb_runner.sh "
                f"{PB_DIR}/next_bell.sh {PB_DIR}/bin/git && chmod 644 {PB_DIR}/prompt.md {PB_DIR}/bells.txt {PB_DIR}/session.json {PB_DIR}/inbox_hook.py && "
                f"chown -R {AGENT_USER}:{AGENT_USER} {WS} {PB_DIR} && ls -la {PB_DIR} {AGENT_DIR} && "
                # sticky-bit workspace: agents create and edit freely, but cannot delete or
                # rename the root-owned reference binary (an in-place compile.sh would)
                f"chown root:{AGENT_USER} /workspace && chmod 1775 /workspace && ls -ld /workspace && "
                f"su -s /bin/bash {AGENT_USER} -c 'export HOME={AGENT_HOME}; git config --global --add safe.directory /workspace; "
                f"PATH={PB_DIR}/bin:$PATH git -C /workspace status --short | head -3; cd /workspace && ./executable --version 2>&1 | head -2'"
            ),
        )

        # 2. message server (background) with a health check
        await self.exec_as_agent(
            environment,
            command=(
                f"export HOME={AGENT_HOME}; echo '>>> [run] starting message server' && "
                f"cd {WS} && setsid nohup java -jar {WS}/coral-server.jar "
                "--auth.keys=test --network.bind_port=5555 --network.allow_any_host=true "
                "--session.defaultWaitTimeout=300000 --registry.include_debug_agents=true "
                f"--registry.local_agents={AGENT_DIR} > {WS}/coral-server.log 2>&1 < /dev/null & "
                "CORAL_PID=$!; echo '>>> [run] server PID '$CORAL_PID; "
                "for i in $(seq 1 150); do "
                "  if curl --noproxy '*' -s http://localhost:5555/api/v1/local/namespace "
                '    -H "Authorization: Bearer test" > /dev/null 2>&1; then '
                "    echo '>>> [run] server ready after '$i' checks'; exit 0; fi; "
                "  if ! kill -0 $CORAL_PID 2>/dev/null; then echo '>>> [run] ERROR: server died'; "
                f"    tail -40 {WS}/coral-server.log; exit 1; fi; "
                "  sleep 2; done; "
                f"echo '>>> [run] ERROR: server not ready after 300s'; tail -40 {WS}/coral-server.log; exit 1"
            ),
            env=env,
            timeout_sec=420,
        )

        # 3. the runner: starts the clock, creates the session (launching the 4 agents),
        #    snapshots, and kills everything at the deadline
        await self.exec_as_agent(
            environment,
            command=f"export HOME={AGENT_HOME}; bash {PB_DIR}/pb_runner.sh",
            env=env,
            cwd="/workspace",
            timeout_sec=self._budget * 60 + 900,
        )

    def populate_context_post_run(self, context: AgentContext) -> None:
        pass


class ProgramBenchCoralL25(ProgramBenchCoralTeam):
    VARIANT = "l25"


class ProgramBenchCoralL3(ProgramBenchCoralTeam):
    VARIANT = "l3"


class ProgramBenchCoralL3H(ProgramBenchCoralTeam):
    VARIANT = "l3h"


class ProgramBenchCoralL25P(ProgramBenchCoralTeam):
    VARIANT = "l25p"
