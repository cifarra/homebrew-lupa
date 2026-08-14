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
  listen_on_network: true     # serve on your LAN (default: localhost only)
  collections:                # folders to index and serve
    - /Volumes/images/photos
    - /Volumes/images/screenshots
```

Every folder in `collections` is registered on boot and indexed in the
background — add a folder, restart the service, done.

## Run

```sh
brew services start lupa        # always-on, starts at login
sudo brew services start lupa   # headless Mac mini: starts at boot, no login needed
```

- REST API: `http://<host>:54321/api/...`
- MCP: `http://127.0.0.1:54321/mcp` — localhost-only by design; from another
  machine tunnel it: `ssh -N -L 54321:127.0.0.1:54321 <host>`
- CLI: `lupa search "golden hour"`, `lupa --help`

Apple Silicon macOS only (CLIP runs on the GPU via MPS).
