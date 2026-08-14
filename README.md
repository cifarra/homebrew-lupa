# homebrew-lupa

Homebrew tap for [Lupa](https://github.com/jmedina21/lupa-tauri) — local-first
semantic image search. Installs the always-on server: CLI + REST API + MCP,
with CLIP embeddings and a bundled Qdrant.

## Install

```sh
brew install cifarra/lupa/lupa
```

Or without Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/cifarra/homebrew-lupa/main/install.sh | sh
```

The curl installer puts `lupa` in `~/.local/bin`. Flags (`| sh -s -- <flag>`):
`--service` runs it always-on from login; `--daemon` runs it from **boot** with
no login needed (headless Mac minis; uses sudo); `--uninstall` removes it
(data stays). Re-running upgrades in place and restarts the service.

## Configure

One file: `~/.lupa/config.yaml` (created on first run).

```yaml
server:
  port: 54321
  listen_on_network: false    # see the warning below before setting true
  collections:                # folders to index and serve
    - /Volumes/images/photos
    - /Volumes/images/screenshots
```

Every folder in `collections` is registered on boot and new files are
indexed in the background — add a folder, restart the service, done.

> **`listen_on_network: true` exposes an unauthenticated API.** Anyone on
> the network can read every indexed image and add/remove collections. Use
> it on trusted home networks only; for remote access prefer an SSH tunnel
> (`ssh -N -L 54321:127.0.0.1:54321 <host>`) or Tailscale.

## Run

```sh
brew services start lupa                # always-on, starts at login
curl -fsSL .../install.sh | sh -s -- --daemon   # headless mini: starts at boot, no login
```

- REST API: `http://<host>:54321/api/...`
- MCP: `http://127.0.0.1:54321/mcp` — guarded against browser/DNS-rebinding
  access; reach it remotely through the SSH tunnel above
- CLI: `lupa search "golden hour"`, `lupa --help`

Apple Silicon macOS only (CLIP runs on the GPU via MPS).
