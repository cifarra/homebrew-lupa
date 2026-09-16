class Lupa < Formula
  desc "Local-first semantic image search server: CLI + REST API + MCP (CLIP + Qdrant)"
  homepage "https://github.com/cifarra/homebrew-lupa"
  url "https://github.com/cifarra/homebrew-lupa/releases/download/v0.7.7/lupa-server-0.7.7-aarch64-apple-darwin.tar.gz"
  sha256 "c6a226b0566807d8c6cc9376113b71ba03355a660ca9682c32f6ce8c84740f17"
  version "0.7.7"

  depends_on arch: :arm64
  depends_on :macos

  def install
    libexec.install "python-sidecar", "qdrant"
    (bin/"lupa").write_env_script libexec/"python-sidecar/python-sidecar-aarch64-apple-darwin",
                                  QDRANT_PATH: libexec/"qdrant/qdrant"
  end

  service do
    run [opt_bin/"lupa", "serve"]
    keep_alive true
    log_path var/"log/lupa.log"
    error_log_path var/"log/lupa.log"
  end

  def caveats
    <<~EOS
      Configure the server in ~/.lupa/config.yaml (created on first run):

        server:
          port: 54321
          listen_on_network: false    # true = serve on your network — the API
                                      # has NO auth; trusted networks only
          collections:                # folders to index and serve
            - /Volumes/images/photos

      Then start it (always-on from login, restarts automatically):

        brew services start lupa

      For boot-time start with no login (headless minis), use the curl
      installer's --daemon mode instead — see the tap README.

      MCP endpoint: http://127.0.0.1:54321/mcp (guarded against browser/DNS
      rebinding; from another machine: ssh -N -L 54322:127.0.0.1:54321 <host>)

      CLI: lupa search "golden hour"   (see lupa --help)
    EOS
  end

  test do
    assert_match "lupa", shell_output("#{bin}/lupa --help")
  end
end
