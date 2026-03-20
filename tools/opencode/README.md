# OpenCode bootstrap

## Files

- `bootstrap-mac.sh`: run on Mac to download Linux install artifacts into this project
- `install-in-container.sh`: run inside the CentOS 8 container to install OpenCode from local files
- `skills/`: stores project-level OpenCode skills that will be copied into `.opencode/skills/`
- `dist/`: stores Linux binary archives downloaded by `bootstrap-mac.sh`
- `src/`: stores optional source archive downloaded by `bootstrap-mac.sh`

## Run on Mac

```bash
bash tools/opencode/bootstrap-mac.sh
```

Optional parameters:

```bash
OPENCODE_VERSION=v1.2.27 bash tools/opencode/bootstrap-mac.sh
DOWNLOAD_SOURCE=false bash tools/opencode/bootstrap-mac.sh
DOWNLOAD_REGION=official bash tools/opencode/bootstrap-mac.sh
GITHUB_PROXY_PREFIX="https://mirror.ghproxy.com/" bash tools/opencode/bootstrap-mac.sh
```

## China download acceleration

`bootstrap-mac.sh` now defaults to `DOWNLOAD_REGION=cn`, which tries these download sources in order and falls back automatically if one fails:

- `mirror.ghproxy.com`
- `gh-proxy.com`
- `kkgithub.com`
- official `github.com`

For the small `install.sh` file, it tries:

- `opencode.ai`
- `cdn.jsdelivr.net`
- `raw.githubusercontent.com`

If your network environment already has a better GitHub proxy, you can override it:

```bash
GITHUB_PROXY_PREFIX="https://your-proxy.example.com/" bash tools/opencode/bootstrap-mac.sh
```

## Run inside container

```bash
bash tools/opencode/install-in-container.sh
```

By default, `install-in-container.sh` now:

- installs OpenCode from local project files
- writes a shared runtime environment file under the project
- adds shell startup sourcing to `~/.bashrc`, `~/.bash_profile`, and `~/.profile`
- writes project-level `opencode.json` by default
- creates the project-level `.opencode/skills/` directory and copies `tools/opencode/skills/` into it
- installs the binary into the project shared runtime directory
- starts `opencode serve` in the background with an absolute binary path

### Recommended one-line usage

Anthropic example:

```bash
ANTHROPIC_API_KEY="your_key" \
OPENCODE_MODEL="anthropic/claude-sonnet-4-5" \
bash tools/opencode/install-in-container.sh
```

OpenAI example:

```bash
OPENAI_API_KEY="your_key" \
OPENCODE_MODEL="openai/gpt-5" \
bash tools/opencode/install-in-container.sh
```

OpenRouter example:

```bash
OPENROUTER_API_KEY="your_key" \
OPENCODE_MODEL="openrouter/anthropic/claude-sonnet-4-5" \
bash tools/opencode/install-in-container.sh
```

### Useful parameters

```bash
START_OPENCODE_AFTER_INSTALL=false bash tools/opencode/install-in-container.sh
RUN_AUTH_LOGIN_AFTER_INSTALL=true bash tools/opencode/install-in-container.sh
OPENCODE_CONFIG_SCOPE=global bash tools/opencode/install-in-container.sh
FORCE_WRITE_OPENCODE_CONFIG=true bash tools/opencode/install-in-container.sh
OPENCODE_PROVIDER_BASE_URL="https://your-proxy.example.com/v1" bash tools/opencode/install-in-container.sh
```

### What the script writes

- Shared runtime directory: `./.opencode-runtime/`
- Runtime binary: `./.opencode-runtime/bin/opencode`
- Runtime env file: `./.opencode-runtime/env.sh`
- Runtime log file: `./.opencode-runtime/opencode-<hostname>.log`
- Runtime pid file: `./.opencode-runtime/opencode-<hostname>.pid`
- Project config by default: `./opencode.json`
- Global config if requested: `~/.config/opencode/opencode.json`
- Project skills directory: `./.opencode/skills/`

If `opencode.json` already exists, the script does not overwrite it unless you set:

```bash
FORCE_WRITE_OPENCODE_CONFIG=true
```

## Notes

- The current bootstrap downloads `linux-x64` and `linux-x64-baseline` packages.
- If the target container is `aarch64`, download the matching `opencode-linux-arm64.tar.gz` package manually into `tools/opencode/dist/`.
- If you do not pass any provider credentials, the script still installs and writes model config, but you will need to run `opencode auth login` or `/connect` later.
- The online server project directory defaults to `/shared_data/app_data/www/default.qunar.com/webapps/ROOT` when that path exists.
- The runtime installation no longer depends on `$HOME`; it is stored under the project shared directory so different users and pods see the same binary path.
