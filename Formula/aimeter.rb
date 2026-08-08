class Aimeter < Formula
  desc "Real-time AI API usage and cost monitor for macOS"
  homepage "https://github.com/smriti-memcore/aimeter"
  # URL and sha256 updated after each release by the release workflow
  url "https://github.com/smriti-memcore/aimeter/releases/download/v0.1.3/aimeter-v0.1.3.tar.gz"
  sha256 "UPDATE_AFTER_RELEASE"
  license "MIT"

  depends_on :macos
  depends_on "python@3"

  def install
    libexec.install "aimeter", "aimeter_daemon.py", "aimeter_cli.py"
    libexec.install "index.html", "index.css", "dashboard.js"
    libexec.install "com.aimeter.app.plist"

    bin.install_symlink libexec/"aimeter"
  end

  def post_install
    plist_src = libexec/"com.aimeter.app.plist"
    plist_dst = Dir.home + "/Library/LaunchAgents/com.aimeter.app.plist"

    if File.exist?(plist_src) && !File.exist?(plist_dst)
      content = File.read(plist_src)
      content = content.gsub("__AIMETER_BIN__", (opt_libexec/"aimeter").to_s)
      content = content.gsub("__HOME__", Dir.home)
      File.write(plist_dst, content)
    end
  end

  service do
    run ["python3", opt_libexec/"aimeter_daemon.py"]
    keep_alive crashed: true
    log_path var/"log/aimeter.log"
    error_log_path var/"log/aimeter.log"
  end

  def caveats
    <<~EOS
      AIMeter is installed!

      Start the daemon (API proxy + dashboard):
        brew services start aimeter

      Start the menu bar app (runs in your GUI session):
        launchctl load ~/Library/LaunchAgents/com.aimeter.app.plist

      Or launch manually:
        aimeter &

      Configure your AI tools:
        aimeter setup

      Dashboard: http://127.0.0.1:5333

      To uninstall cleanly:
        aimeter setup --undo
        launchctl unload ~/Library/LaunchAgents/com.aimeter.app.plist
        rm ~/Library/LaunchAgents/com.aimeter.app.plist
        brew services stop aimeter
        brew uninstall aimeter
    EOS
  end
end
