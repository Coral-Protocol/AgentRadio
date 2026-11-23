"""
Pier agent: message server + 4 Claude Code instances for DeepSWE (L1 / L2 / L3).

Port of the AgentRadio Harbor adapters (coral_multi_agent*.py) to Pier's no-network
Modal environment:

  - JDK 24 and Claude Code are installed through ``install_spec()``, which Pier bakes
    into the task image at BUILD time (network available). The runtime ``install()``
    is skipped for pre-installed agents, so nothing is downloaded inside the sandbox.
  - The message-server JAR, the startup script (resume-guarded), the agent TOML and
    the passive shell scripts are uploaded at the start of ``run()`` with
    ``environment.upload_file`` (host -> sandbox through the Modal API, no sandbox
    egress needed).
  - ``network_allowlist()`` returns api.anthropic.com so Pier creates the egress proxy;
    every ``exec`` inherits HTTPS_PROXY / NO_PROXY=localhost, so the four Claude Code
    processes reach the model API while the server on localhost:5555 is untouched.
  - The full instruction.md is passed through (the "new branch + commit" line is
    agent-1's job). Completion is signalled by /logs/agent/answer.txt, written by
    agent-1 only after its commit exists; the verifier then collects base..HEAD.

Variants (select with ``--ak variant=l1|l2|l3`` or the fixed subclasses below):
  l1  startup_deepswe_ablation.sh   division only, no negotiation, MCP tools
  l2  startup_deepswe.sh            division + negotiation, blocking receive, MCP tools
  l3  startup_deepswe_passive.sh    + passive awareness (background watcher, scripts)
  l25 startup_deepswe_l25.sh       L2 phases/gates; working phases (Phase 3, Phase 5
                                   implementation) share as you go in a WORKLOG thread,
                                   receive by reading coral://state (no watcher), MCP tools

Usage:
  PYTHONPATH=/home/xinxing/deep-swe CLAUDE_CODE_OAUTH_TOKEN=... pier run -p tasks \
    -i ipython-session-bundle-replay --n-tasks 1 -n 1 \
    --agent-import-path multi_agent.coral_multi_agent_deepswe:CoralMultiAgentDeepSWEL2 \
    --model anthropic/claude-opus-4-6 \
    --env modal --ek app_name=deepswe-l2 \
    --override-cpus 4 --override-memory-mb 16384 \
    --job-name deepswe-l2-ipython-01
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

from multi_agent.resume_guard import make_guarded_startup

MULTI_AGENT_DIR = Path(__file__).parent
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

VARIANTS = {
    "l1": {
        "startup": "startup_deepswe_ablation.sh",
        "label": "L1 division-only",
        "agent1_role": "coordinator",
    },
    "l2": {
        "startup": "startup_deepswe.sh",
        "label": "L2 division+negotiation (blocking)",
        "agent1_role": "implementer",
    },
    "l3": {
        "startup": "startup_deepswe_passive.sh",
        "label": "L3 passive awareness",
        "agent1_role": "implementer",
    },
    "l25": {
        "startup": "startup_deepswe_l25.sh",
        "label": "L2.5 blocking discussion phases + share-as-you-go working phases (self-read receive)",
        "agent1_role": "implementer",
    },
}

WS = "/tmp/coral-workspace"
AGENT_NAME = "deepswe-agent"
AGENT_DIR = f"{WS}/{AGENT_NAME}"
INSTRUCTION_PATH = f"{WS}/instruction.md"
BRIEF_PATH = f"{WS}/brief.md"
ANSWER_FILE = "/logs/agent/answer.txt"

JDK_URL = (
    "https://api.adoptium.net/v3/binary/latest/24/ga/linux/x64/jdk/hotspot/normal/eclipse"
)
DEFAULT_CLAUDE_CODE_VERSION = "2.1.310"


def _agent_toml(startup: str, label: str) -> str:
    return f"""edition = 3

[agent]
name = "{AGENT_NAME}"
version = "0.1.0"
description = "DeepSWE multi-agent peer ({label})"

readme = "Claude Code agent for DeepSWE multi-agent collaboration via the message server ({label})"
summary = "4 agents investigate a feature request; agent-1 implements and commits"

[agent.license]
type = "spdx"
expression = "MIT"

[options.auto_launch]
type = "string"
default = "true"

[runtimes.executable]
path = "bash"
arguments = ["{startup}"]
transport = "streamable_http"
"""


class CoralMultiAgentDeepSWE(BaseInstalledAgent):
    """Pier agent: message server + 4 Claude Code instances (variant via kwarg)."""

    SUPPORTS_ATIF: bool = False
    VARIANT: str = "l2"

    def __init__(
        self,
        logs_dir: Path,
        variant: str | None = None,
        claude_code_version: str = DEFAULT_CLAUDE_CODE_VERSION,
        wait_minutes: int = 170,
        *args,
        **kwargs,
    ):
        self._variant = (variant or self.VARIANT).lower()
        if self._variant not in VARIANTS:
            raise ValueError(f"variant must be one of {sorted(VARIANTS)}, got {variant!r}")
        self._cc_version = str(claude_code_version)
        self._wait_minutes = int(wait_minutes)
        super().__init__(logs_dir, *args, **kwargs)

    # ------------------------------------------------------------------ identity
    @staticmethod
    def name() -> str:
        return "coral-multi-agent-deepswe"

    def get_version_command(self) -> str | None:
        return None

    def parse_version(self, stdout: str) -> str:
        return "0.1.0"

    @property
    def _cfg(self) -> dict:
        return VARIANTS[self._variant]

    # ------------------------------------------------------------------ install
    def install_spec(self) -> AgentInstallSpec:
        """Build-time steps (network available): JDK 24 + Claude Code."""
        root_run = (
            "set -euo pipefail; "
            "export DEBIAN_FRONTEND=noninteractive; "
            "if command -v apt-get >/dev/null 2>&1; then "
            "  apt-get update -qq && apt-get install -y -qq curl ca-certificates jq python3 >/dev/null; "
            "elif command -v apk >/dev/null 2>&1; then "
            "  apk add --no-cache curl ca-certificates jq bash python3; "
            "elif command -v yum >/dev/null 2>&1; then "
            "  yum install -y curl ca-certificates jq python3; "
            "fi; "
            f"curl -fsSL {shlex.quote(JDK_URL)} -o /tmp/jdk24.tar.gz && "
            "mkdir -p /opt/java && tar -xzf /tmp/jdk24.tar.gz -C /opt/java --strip-components=1 && "
            "rm -f /tmp/jdk24.tar.gz && ln -sf /opt/java/bin/java /usr/local/bin/java && "
            "java -version && python3 --version"
        )
        agent_run = (
            "set -euo pipefail; "
            f"curl -fsSL https://claude.ai/install.sh | bash -s -- {shlex.quote(self._cc_version)} && "
            "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc && "
            'export PATH="$HOME/.local/bin:$PATH" && claude --version'
        )
        return AgentInstallSpec(
            agent_name=self.name(),
            version=self._cc_version,
            steps=[
                InstallStep(user="root", run=root_run, env={"DEBIAN_FRONTEND": "noninteractive"}),
                InstallStep(user="agent", run=agent_run),
            ],
            verification_command=(
                'export PATH="$HOME/.local/bin:$PATH"; claude --version && java -version'
            ),
        )

    def network_allowlist(self) -> NetworkAllowlist:
        # Model API only. Required: an empty allowlist means no egress proxy at all.
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

    async def _upload_bundle(self, environment: BaseEnvironment) -> None:
        startup_name = self._cfg["startup"]
        startup_local = MULTI_AGENT_DIR / startup_name
        for p in [CORAL_SERVER_JAR, startup_local, *(PASSIVE_SCRIPTS_DIR / n for n in PASSIVE_SCRIPTS)]:
            if not p.exists():
                raise RuntimeError(f"Required file not found: {p}")

        await self.exec_as_agent(
            environment,
            command=f"mkdir -p {AGENT_DIR}/passive_scripts {AGENT_DIR}/instances /logs/agent",
        )
        await environment.upload_file(CORAL_SERVER_JAR, f"{WS}/coral-server.jar")
        # Resume-guarded startup: relaunch claude with --continue until answer.txt exists.
        await self._upload_text(
            environment, make_guarded_startup(startup_local.read_text()), f"{AGENT_DIR}/{startup_name}"
        )
        await self._upload_text(
            environment, _agent_toml(startup_name, self._cfg["label"]), f"{AGENT_DIR}/coral-agent.toml"
        )
        for n in PASSIVE_SCRIPTS:
            await environment.upload_file(PASSIVE_SCRIPTS_DIR / n, f"{AGENT_DIR}/passive_scripts/{n}")
        await self.exec_as_agent(
            environment,
            command=f"chmod +x {AGENT_DIR}/{startup_name} {AGENT_DIR}/passive_scripts/*.sh && ls -la {AGENT_DIR}",
        )

    def _runtime_env(self) -> dict[str, str]:
        env: dict[str, str] = {}
        oauth = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")
        api_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN") or ""
        if oauth:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = oauth
        elif api_key:
            env["ANTHROPIC_API_KEY"] = api_key
        if self.model_name:
            env["ANTHROPIC_MODEL"] = self.model_name.split("/")[-1]
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["IS_SANDBOX"] = "1"
        env["CORAL_REPO_DIR"] = "/app"
        env["CORAL_INSTRUCTION_PATH"] = INSTRUCTION_PATH
        env["CORAL_BRIEF_PATH"] = BRIEF_PATH
        return env

    # ------------------------------------------------------------------ run
    async def run(self, instruction: str, environment: BaseEnvironment, context: AgentContext) -> None:
        env = self._runtime_env()
        startup_name = self._cfg["startup"]

        # 1. Upload server + startup + scripts, write the FULL instruction
        await self._upload_bundle(environment)
        await self._upload_text(environment, instruction.rstrip() + "\n", INSTRUCTION_PATH)
        await self.exec_as_agent(
            environment,
            command=(
                f"echo '>>> [run] variant={self._variant} startup={startup_name}' && "
                f"wc -c {INSTRUCTION_PATH} && git -C /app rev-parse --abbrev-ref HEAD && git -C /app rev-parse HEAD"
            ),
            env=env,
        )

        # 2. Start the message server (background) with a health check
        await self.exec_as_agent(
            environment,
            command=(
                "echo '>>> [run] Starting message server...' && "
                f"cd {WS} && setsid nohup java -jar {WS}/coral-server.jar "
                "--auth.keys=test "
                "--network.bind_port=5555 "
                "--network.allow_any_host=true "
                "--session.defaultWaitTimeout=300000 "
                "--registry.include_debug_agents=true "
                f"--registry.local_agents={AGENT_DIR} "
                f"> {WS}/coral-server.log 2>&1 < /dev/null & "
                "CORAL_PID=$!; echo '>>> [run] message server PID: '$CORAL_PID; "
                "for i in $(seq 1 150); do "
                "  if curl --noproxy '*' -s http://localhost:5555/api/v1/local/namespace "
                '    -H "Authorization: Bearer test" > /dev/null 2>&1; then '
                "    echo '>>> [run] message server ready after '$i' checks'; exit 0; fi; "
                "  if ! kill -0 $CORAL_PID 2>/dev/null; then "
                "    echo '>>> [run] ERROR: message server died!'; "
                f"    tail -40 {WS}/coral-server.log; exit 1; fi; "
                "  sleep 2; "
                "done; "
                f"echo '>>> [run] ERROR: server not ready after 300s'; tail -40 {WS}/coral-server.log; exit 1"
            ),
            env=env,
            timeout_sec=420,
        )

        # 3. Create the session: the server launches 4 agents via the startup script
        session_json = json.dumps({
            "agentGraphRequest": {
                "agents": [
                    {
                        "id": {
                            "name": AGENT_NAME,
                            "version": "0.1.0",
                            "registrySourceId": {"type": "local"},
                        },
                        "name": f"agent-{i}",
                        "provider": {"type": "local", "runtime": "executable"},
                        "description": "DeepSWE peer agent"
                        + (f" ({self._cfg['agent1_role']})" if i == 1 else ""),
                        "options": {},
                        "blocking": False,
                    }
                    for i in range(1, 5)
                ],
                "groups": [["agent-1", "agent-2", "agent-3", "agent-4"]],
            },
            "namespaceProvider": {
                "type": "create_if_not_exists",
                "namespaceRequest": {"name": "deepswe", "deleteOnLastSessionExit": False},
            },
            "execution": {"mode": "immediate", "runtimeSettings": {"ttl": 86400000}},
        })
        await self.exec_as_agent(
            environment,
            command=(
                "echo '>>> [run] Creating session with 4 agents...' && "
                "curl --noproxy '*' -s -X POST http://localhost:5555/api/v1/local/session "
                '-H "Authorization: Bearer test" -H "Content-Type: application/json" '
                f"-d {shlex.quote(session_json)} > {WS}/session-response.json && "
                f"cat {WS}/session-response.json && echo"
            ),
            env=env,
        )

        # 4. Wait for the completion file; sync logs every minute
        sync = (
            f"cp {WS}/coral-server.log /logs/agent/ 2>/dev/null || true; "
            f"cp {WS}/session-response.json /logs/agent/ 2>/dev/null || true; "
            f"cp {BRIEF_PATH} /logs/agent/ 2>/dev/null || true; "
            f"find {AGENT_DIR}/instances/ -name '*-claude-code.txt' -exec cp {{}} /logs/agent/ \\; 2>/dev/null || true"
        )
        n_ticks = self._wait_minutes * 6  # 10 s per tick
        await self.exec_as_agent(
            environment,
            command=(
                f"mkdir -p /logs/agent && {sync} && "
                f"echo '>>> [run] Agents launched. Waiting up to {self._wait_minutes} min for {ANSWER_FILE}...' && "
                f"for i in $(seq 1 {n_ticks}); do "
                f"  if [ -f {ANSWER_FILE} ]; then echo '>>> [run] Completion file found after '$((i*10))' s'; cat {ANSWER_FILE}; sleep 90; break; fi; "
                "  if [ $((i % 6)) -eq 0 ]; then "
                f"    {sync}; "
                "    echo '>>> [run] '$((i/6))' min | claude procs: '$(pgrep -fc 'claude --verbose' || true)"
                f"' | server log lines: '$(wc -l < {WS}/coral-server.log 2>/dev/null || echo 0); "
                "  fi; "
                "  sleep 10; "
                "done; "
                f"if [ ! -f {ANSWER_FILE} ]; then echo '>>> [run] TIMEOUT: no completion file'; fi"
            ),
            env=env,
            timeout_sec=self._wait_minutes * 60 + 300,
        )

        # 5. Final save: logs, session dumps, git state
        await self.exec_as_agent(
            environment,
            command=(
                "echo '>>> [run] Saving logs...' && mkdir -p /logs/agent/coral-state && "
                f"{sync}; "
                "cp /tmp/coral-session-dumps/*.json /logs/agent/coral-state/ 2>/dev/null || echo '  no session dumps'; "
                f"ls -la {AGENT_DIR}/instances/*/ 2>/dev/null || true; "
                "{ echo '--- git branch'; git -C /app rev-parse --abbrev-ref HEAD; "
                "  echo '--- git log -3'; git -C /app log --oneline -3; "
                "  echo '--- git status'; git -C /app status --short | head -50; } > /logs/agent/git-state.txt 2>&1 || true; "
                "cat /logs/agent/git-state.txt; echo '>>> [run] Done'"
            ),
            env=env,
        )

    def populate_context_post_run(self, context: AgentContext) -> None:
        pass


class CoralMultiAgentDeepSWEL1(CoralMultiAgentDeepSWE):
    VARIANT = "l1"


class CoralMultiAgentDeepSWEL2(CoralMultiAgentDeepSWE):
    VARIANT = "l2"


class CoralMultiAgentDeepSWEL3(CoralMultiAgentDeepSWE):
    VARIANT = "l3"


class CoralMultiAgentDeepSWEL25(CoralMultiAgentDeepSWE):
    VARIANT = "l25"
