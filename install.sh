#!/bin/sh
# Lupa server installer — CLI + REST API + MCP, no Homebrew required.
#
#   curl -fsSL https://raw.githubusercontent.com/cifarra/homebrew-lupa/main/install.sh | sh
#   ... | sh -s -- --service     # also run always-on (starts at login)
#   ... | sh -s -- --daemon      # always-on at BOOT, no login needed (uses sudo; headless minis)
#   ... | sh -s -- --uninstall   # remove (keeps ~/.lupa data)
#
# Installs to ~/.local/share/lupa with a `lupa` shim in ~/.local/bin.
# Re-running upgrades in place and restarts a running service/daemon.
set -eu

REPO="cifarra/homebrew-lupa"
ASSET="lupa-server-aarch64-apple-darwin.tar.gz"
URL="${LUPA_INSTALL_URL:-https://github.com/$REPO/releases/latest/download/$ASSET}"
PREFIX="${LUPA_PREFIX:-$HOME/.local}"
PAYLOAD="$PREFIX/share/lupa"
SHIM="$PREFIX/bin/lupa"
LABEL="com.lupa.server"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DAEMON_PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "lupa-server supports Apple Silicon macOS only." >&2
    exit 1
fi
if [ "$(id -u)" = "0" ]; then
    echo "Run as a normal user, not root — --daemon uses sudo only where needed." >&2
    exit 1
fi

stop_agent() { launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; }
stop_daemon() {
    sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
    i=0
    while sudo launchctl print "system/$LABEL" >/dev/null 2>&1 && [ $i -lt 15 ]; do
        i=$((i + 1)); sleep 1
    done
}
stop_lupa_qdrant() {
    # The sidecar leaves its qdrant running detached; without this, an
    # upgraded install keeps executing the OLD qdrant binary until reboot.
    # Only called when a lupa service existed — never on a CLI-only machine
    # where a desktop Lupa app may own the running qdrant.
    pid_file="$HOME/.lupa/qdrant.pid"
    [ -f "$pid_file" ] || return 0
    pid=$(cat "$pid_file" 2>/dev/null) || return 0
    if [ -n "$pid" ] && ps -p "$pid" -o command= 2>/dev/null | grep -q qdrant; then
        kill "$pid" 2>/dev/null || true
        i=0
        while ps -p "$pid" >/dev/null 2>&1 && [ $i -lt 10 ]; do
            i=$((i + 1)); sleep 1
        done
    fi
    rm -f "$pid_file"
}

had_agent=0; had_daemon=0
[ -f "$AGENT_PLIST" ] && had_agent=1
[ -f "$DAEMON_PLIST" ] && had_daemon=1

if [ "${1:-}" = "--uninstall" ]; then
    stop_agent
    rm -f "$AGENT_PLIST" "$SHIM"
    if [ "$had_daemon" = 1 ]; then
        stop_daemon
        sudo rm -f "$DAEMON_PLIST"
    fi
    [ "$had_agent$had_daemon" != "00" ] && stop_lupa_qdrant
    rm -rf "$PAYLOAD"
    echo "lupa removed. Your data and config (~/.lupa) were left untouched."
    exit 0
fi

# Mode: an explicit flag wins; otherwise keep whatever is already installed.
mode=none
[ "$had_agent" = 1 ] && mode=agent
[ "$had_daemon" = 1 ] && mode=daemon
case "${1:-}" in
    --service) mode=agent ;;
    --daemon) mode=daemon ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading lupa-server..."
curl -fL --progress-bar "$URL" -o "$tmp/$ASSET"
if curl -fsSL "$URL.sha256" -o "$tmp/$ASSET.sha256" 2>/dev/null; then
    want=$(cut -d' ' -f1 "$tmp/$ASSET.sha256")
    got=$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)
    if [ "$want" != "$got" ]; then
        echo "Checksum mismatch (expected $want, got $got) — aborting." >&2
        exit 1
    fi
fi
mkdir -p "$tmp/payload" "$PREFIX/bin" "$(dirname "$PAYLOAD")"
tar -xzf "$tmp/$ASSET" -C "$tmp/payload"

# A running service must not keep executing a half-replaced payload — and
# its detached qdrant must die too, or the new bundled qdrant never runs.
stop_agent
[ "$had_daemon" = 1 ] && stop_daemon
[ "$had_agent$had_daemon" != "00" ] && stop_lupa_qdrant

rm -rf "$PAYLOAD"
mv "$tmp/payload" "$PAYLOAD"

cat > "$SHIM" <<EOF
#!/bin/sh
QDRANT_PATH="$PAYLOAD/qdrant/qdrant" exec "$PAYLOAD/python-sidecar/python-sidecar-aarch64-apple-darwin" "\$@"
EOF
chmod +x "$SHIM"

echo "Installed lupa $(cat "$PAYLOAD/VERSION" 2>/dev/null || echo '?') -> $SHIM"

case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) echo "NOTE: $PREFIX/bin is not on your PATH. Add:  export PATH=\"$PREFIX/bin:\$PATH\"" ;;
esac

write_plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$SHIM</string><string>serve</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>HOME</key><string>$HOME</string></dict>
    $1
    <key>WorkingDirectory</key><string>$HOME</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$HOME/.lupa/logs/server.log</string>
    <key>StandardErrorPath</key><string>$HOME/.lupa/logs/server.log</string>
</dict>
</plist>
EOF
}

case "$mode" in
    agent)
        mkdir -p "$HOME/.lupa/logs" "$HOME/Library/LaunchAgents"
        write_plist "" > "$AGENT_PLIST"
        launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
        echo "Service running (starts at login). Logs: ~/.lupa/logs/server.log"
        ;;
    daemon)
        mkdir -p "$HOME/.lupa/logs"
        write_plist "<key>UserName</key><string>$(id -un)</string>" | sudo tee "$DAEMON_PLIST" >/dev/null
        sudo chown root:wheel "$DAEMON_PLIST"
        sudo chmod 644 "$DAEMON_PLIST"
        sudo launchctl bootstrap system "$DAEMON_PLIST"
        echo "Daemon running (starts at boot, no login needed). Logs: ~/.lupa/logs/server.log"
        ;;
    none)
        echo "Run the server:  lupa serve"
        echo "Always-on:       re-run this installer with --service (login) or --daemon (boot)"
        ;;
esac

cat <<'EOF'

Configure ~/.lupa/config.yaml (created on first run):

  server:
    port: 54321
    listen_on_network: false    # true = serve on your network. The API has
                                # NO authentication: anyone on the network can
                                # read every indexed image and modify
                                # collections. Trusted home networks only —
                                # otherwise use an SSH tunnel or Tailscale.
    collections:                # folders to index and serve
      - /Volumes/images/photos
EOF
