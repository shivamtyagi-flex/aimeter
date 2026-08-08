class Aimeter < Formula
  desc "Real-time AI API usage and cost monitor for macOS"
  homepage "https://github.com/smriti-memcore/aimeter"
  # URL and sha256 updated after each release by the release workflow
  url "https://github.com/smriti-memcore/aimeter/releases/download/v0.1.2/aimeter-v0.1.2.tar.gz"
  sha256 "UPDATE_AFTER_RELEASE"
  license "MIT"

  depends_on :macos
  depends_on "python@3"

  def install
    libexec.install "aimeter", "aimeter_daemon.py", "aimeter_cli.py"
    libexec.install "index.html", "index.css", "dashboard.js"
    libexec.install "com.aimeter.app.plist"

    (bin/"aimeter").write_env_script libexec/"aimeter"
  end

  service do
    run [opt_libexec/"aimeter"]
    keep_alive crashed: true
    log_path var/"log/aimeter.log"
    error_log_path var/"log/aimeter.log"
  end

  def caveats
    <<~EOS
      AIMeter is installed!

      ⚠️ Gatekeeper Note: Since the binary is pre-compiled, macOS may quarantine it.
      If you get a verification/developer error, trust the binary by running:
        xattr -d com.apple.quarantine $(brew --prefix)/opt/aimeter/libexec/aimeter

      To start the background service on login:
        brew services start aimeter

      Then configure your AI tools:
        aimeter setup

      Dashboard: http://127.0.0.1:5333

      To uninstall cleanly:
        aimeter setup --undo
        brew services stop aimeter
        brew uninstall aimeter
    EOS
  end
end
