# Project-level OpenCode Skills

Put your reusable project skills in this directory.

Each skill should use this structure:

```text
tools/opencode/skills/<skill-name>/SKILL.md
```

Example:

```text
tools/opencode/skills/java-service-review/SKILL.md
```

When `tools/opencode/install-in-container.sh` runs, it copies everything from this directory into the project-level OpenCode skills directory:

```text
<project>/.opencode/skills/
```

For the online server path in this project, the target project directory defaults to:

```text
/shared_data/app_data/www/default.qunar.com/webapps/ROOT
```

If you need to override it, set:

```bash
OPENCODE_PROJECT_DIR=/your/project/path bash tools/opencode/install-in-container.sh
```
