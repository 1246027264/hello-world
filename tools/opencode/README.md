# OpenCode bootstrap

## Files

- `bootstrap-mac.sh`: run on Mac to download Linux install artifacts into this project
- `install-in-container.sh`: run inside the CentOS 8 container to install OpenCode from local files
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
export PATH="$HOME/.opencode/bin:$PATH"
opencode --version
```

## Notes

- The current bootstrap downloads `linux-x64` and `linux-x64-baseline` packages.
- If the target container is `aarch64`, download the matching `opencode-linux-arm64.tar.gz` package manually into `tools/opencode/dist/`.
