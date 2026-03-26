# Project-level OpenCode Agents

Put your reusable project agents in this directory.

Each agent should use this structure:

```text
tools/opencode/agents/<agent-name>/AGENT.md
```

Example:

```text
tools/opencode/agents/ops-minimal-orchestrator/AGENT.md
```

When `tools/opencode/install-in-container.sh` runs, it copies everything from this directory into the project-level OpenCode agents directory:

```text
<project>/.opencode/agents/
```

For the online server path in this project, the target project directory defaults to:

```text
/shared_data/app_data/www/default.qunar.com/webapps/ROOT
```

If you need to override it, set:

```bash
OPENCODE_PROJECT_DIR=/your/project/path bash tools/opencode/install-in-container.sh
```
