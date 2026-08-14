#!/bin/sh
# Lupa server installer — CLI + REST API + MCP, no Homebrew required.
#
#   curl -fsSL https://raw.githubusercontent.com/cifarra/homebrew-lupa/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --service     # also run always-on (launchd)
#   curl -fsSL .../install.sh | sh -s -- --uninstall   # remove (keeps ~/.lupa data)
#
# Installs to ~/.local/share/lupa with a `lupa` shim in ~/.local/bin.
# Re-running upgrades in place (a running service is restarted).
set -eu

REPO="cifarra/homebrew-lupa"
ASSET="lupa-server-aarch64-apple-darwin.tar.gz"
URL="${LUPA_INSTALL_URL:-https://github.com/$REPO/releases/latest/download/$ASSET}"
PREFIX="${LUPA_PREFIX:-$HOME/.local}"
PAYLOAD="$PREFIX/share/lupa"
SHIM="$PREFIX/bin/lupa"
LABEL="com.lupa.server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "lupa-server supports Apple Silicon macOS only." >&2
    exit 1
fi

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$SHIM"
    rm -rf "$PAYLOAD"
    echo "lupa removed. Your data and config (~/.lupa) were left untouched."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading lupa-server..."
curl -fL --progress-bar "$URL" -o "$tmp/$ASSET"
mkdir -p "$tmp/payload" "$PREFIX/bin" "$(dirname "$PAYLOAD")"
tar -xzf "$tmp/$ASSET" -C "$tmp/payload"

# A running service must not keep executing a half-replaced payload.
service_was_running=0
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    service_was_running=1
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
fi

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

if [ "${1:-}" = "--service" ] || [ "$service_was_running" = 1 ]; then
    mkdir -p "$HOME/.lupa/logs" "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$SHIM</string><string>serve</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>HOME</key><string>$HOME</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$HOME/.lupa/logs/server.log</string>
    <key>StandardErrorPath</key><string>$HOME/.lupa/logs/server.log</string>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Service running (starts at login). Logs: ~/.lupa/logs/server.log"
else
    echo "Run the server:  lupa serve"
    echo "Always-on:       re-run this installer with --service"
fi

cat <<'EOF'

Configure ~/.lupa/config.yaml (created on first run):

  server:
    port: 54321
    listen_on_network: true     # serve on your LAN (default: localhost only)
    collections:                # folders to index and serve
      - /Volumes/images/photos
EOF
