import AppKit
import Foundation

class DaemonManager {
    static let shared = DaemonManager()
    private var process: Process?
    
    func startDaemonIfNeeded() {
        if isPortOpen(port: 5333) {
            print("Daemon is already running on port 5333.")
            return
        }
        
        print("Starting Python daemon...")
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let exeDir = exeURL.deletingLastPathComponent()
        var scriptPath = exeDir.appendingPathComponent("aimeter_daemon.py").path
        
        if !FileManager.default.fileExists(atPath: scriptPath) {
            let resourcesPath = exeDir.deletingLastPathComponent().appendingPathComponent("Resources/aimeter_daemon.py").path
            if FileManager.default.fileExists(atPath: resourcesPath) {
                scriptPath = resourcesPath
            }
        }
        
        if !FileManager.default.fileExists(atPath: scriptPath) {
            let fallbackPath = FileManager.default.currentDirectoryPath + "/aimeter_daemon.py"
            if FileManager.default.fileExists(atPath: fallbackPath) {
                runProcess(scriptPath: fallbackPath)
            } else {
                print("Could not find aimeter_daemon.py in executable dir, resources dir, or fallback path.")
            }
        } else {
            runProcess(scriptPath: scriptPath)
        }
    }
    
    private func runProcess(scriptPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", scriptPath]
        
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        
        do {
            try proc.run()
            self.process = proc
            print("Daemon process started with PID: \(proc.processIdentifier)")
        } catch {
            print("Failed to run daemon process: \(error)")
        }
    }
    
    func stopDaemon() {
        if let proc = process, proc.isRunning {
            print("Terminating Python daemon...")
            proc.terminate()
            proc.waitUntilExit()
            print("Daemon terminated.")
        }
    }
    
    private func isPortOpen(port: Int) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var isOpen = false
        
        let url = URL(string: "http://127.0.0.1:\(port)/api/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isOpen = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.2)
        return isOpen
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var CURRENT_VERSION: String {
        if let dict = Bundle.main.infoDictionary,
           let version = dict["CFBundleShortVersionString"] as? String {
            return version
        }
        return "0.3.5"
    }
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    
    var spendLabel: NSTextField!
    var budgetLabel: NSTextField!
    var anthropicLabel: NSTextField!
    var openaiLabel: NSTextField!
    var geminiLabel: NSTextField!
    var claudeCodeLabel: NSTextField!
    var openrouterLabel: NSTextField!
    
    var timer: Timer?
    var currentPollRange: String = "day"
    
    func createLabelItem(title: String, isHeader: Bool = false) -> (NSMenuItem, NSTextField) {
        let item = NSMenuItem()
        let label = NSTextField(labelWithString: title)
        label.font = isHeader ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 13)
        label.textColor = isHeader ? NSColor.secondaryLabelColor : NSColor.labelColor
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        let leftIndent: CGFloat = isHeader ? 12 : 24
        label.frame = NSRect(x: leftIndent, y: 2, width: 216, height: 18)
        label.autoresizingMask = [.width]
        
        container.addSubview(label)
        item.view = container
        item.isEnabled = false // Non-clickable, but view text remains high contrast and readable
        return (item, label)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        DaemonManager.shared.startDaemonIfNeeded()

        createStatusItem()
        setupMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.ensureStatusItem()
            self?.pollStats()
        }

        pollStats()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "$0.00"
            button.imagePosition = .imageLeft
            if let img = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AI Spend") {
                img.isTemplate = true
                button.image = img
            }
            button.target = self
        }
    }

    func ensureStatusItem() {
        if statusItem.button == nil {
            createStatusItem()
            setupMenu()
        }
    }

    @objc func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ensureStatusItem()
            self?.pollStats()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        DaemonManager.shared.stopDaemon()
    }
    
    func setupMenu() {
        menu = NSMenu()
        
        let (spendItem, sLabel) = createLabelItem(title: "AI Spend Today: $0.00")
        self.spendLabel = sLabel
        menu.addItem(spendItem)
        
        let (budgetItem, bLabel) = createLabelItem(title: "Daily Budget: $5.00")
        self.budgetLabel = bLabel
        menu.addItem(budgetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let (headerItem, _) = createLabelItem(title: "Provider Breakdown:", isHeader: true)
        menu.addItem(headerItem)
        
        let (anthropicItem, aLabel) = createLabelItem(title: "  Anthropic: $0.00")
        self.anthropicLabel = aLabel
        menu.addItem(anthropicItem)
        
        let (openaiItem, oLabel) = createLabelItem(title: "  OpenAI: $0.00")
        self.openaiLabel = oLabel
        menu.addItem(openaiItem)
        
        let (geminiItem, gLabel) = createLabelItem(title: "  Google Gemini: $0.00")
        self.geminiLabel = gLabel
        menu.addItem(geminiItem)
        
        let (claudeCodeItem, ccLabel) = createLabelItem(title: "  Claude Code: $0.00")
        self.claudeCodeLabel = ccLabel
        menu.addItem(claudeCodeItem)
        
        let (openrouterItem, orLabel) = createLabelItem(title: "  OpenRouter: $0.00")
        self.openrouterLabel = orLabel
        menu.addItem(openrouterItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let dashboardItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        
        let syncItem = NSMenuItem(title: "Force Sync Claude Logs", action: #selector(forceSyncLogs), keyEquivalent: "s")
        syncItem.target = self
        menu.addItem(syncItem)
        
        let resetItem = NSMenuItem(title: "Reset Today's Spend", action: #selector(resetSpend), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        
        let setupItem = NSMenuItem(title: "Configure Shell & IDEs...", action: #selector(runSetupWizard), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        
        let securityItem = NSMenuItem(title: "Security & Privacy Info...", action: #selector(showSecurityInfo), keyEquivalent: "")
        securityItem.target = self
        menu.addItem(securityItem)
        
        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesManually), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let versionItem = NSMenuItem(title: "Version \(CURRENT_VERSION)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        let quitItem = NSMenuItem(title: "Quit AI Cost Tracker", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func openDashboard() {
        if let url = URL(string: "http://127.0.0.1:5333/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func runSetupWizard() {
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let exeDir = exeURL.deletingLastPathComponent()
        var cliPath = exeDir.appendingPathComponent("aimeter_cli.py").path
        
        if !FileManager.default.fileExists(atPath: cliPath) {
            let resourcesPath = exeDir.deletingLastPathComponent().appendingPathComponent("Resources/aimeter_cli.py").path
            if FileManager.default.fileExists(atPath: resourcesPath) {
                cliPath = resourcesPath
            }
        }
        
        let script = "tell application \"Terminal\" to do script \"python3 \\\"\(cliPath)\\\" setup\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript execution error: \(err)")
            }
        }
    }
    
    @objc func showSecurityInfo() {
        let alert = NSAlert()
        alert.messageText = "Security & Privacy Guarantees"
        alert.informativeText = """
        🔒 100% Local-First:
        All token counts, spent limits, and logs reside in your local folder (~/.ai_usage_tracker). There are no cloud servers, remote databases, or telemetry analytics.
        
        🔑 Key Safety:
        Your provider API keys are passed directly and transparently. AIMeter never intercepts, saves, or stores your keys on disk.
        
        📝 Payload Privacy:
        Only token count metrics and model names are recorded. Your prompts, source code, and completion texts are never captured or logged.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close")
        alert.runModal()
    }
    
    @objc func checkForUpdatesManually() {
        // Use redirect-based check to avoid GitHub API rate limits
        let url = URL(string: "https://github.com/smriti-memcore/aimeter/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("AIMeter-Updater-Swift", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if error != nil {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Check for Updates"
                    alert.informativeText = "Unable to connect to GitHub. Please check your internet connection."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }

            // The URL redirects to /releases/tag/v0.3.6 — extract version from final URL
            guard let httpResponse = response as? HTTPURLResponse,
                  let finalUrl = httpResponse.url?.absoluteString else { return }

            let ver = finalUrl.components(separatedBy: "/").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: "v")) ?? ""

            guard !ver.isEmpty else { return }

            let dmgUrl = "https://github.com/smriti-memcore/aimeter/releases/download/v\(ver)/AIMeter.dmg"

            DispatchQueue.main.async {
                let latestParts = ver.split(separator: ".").compactMap { Int($0) }
                let currentParts = self.CURRENT_VERSION.split(separator: ".").compactMap { Int($0) }

                var hasUpdate = false
                if latestParts.count == 3 && currentParts.count == 3 {
                    if latestParts[0] > currentParts[0] { hasUpdate = true }
                    else if latestParts[0] == currentParts[0] && latestParts[1] > currentParts[1] { hasUpdate = true }
                    else if latestParts[0] == currentParts[0] && latestParts[1] == currentParts[1] && latestParts[2] > currentParts[2] { hasUpdate = true }
                } else {
                    hasUpdate = (ver != self.CURRENT_VERSION)
                }

                if hasUpdate {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "A new stable version of AIMeter is available (v\(ver)). Would you like to download and install it in one click?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Update Now")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        self.performOneStepUpdate(downloadUrl: dmgUrl)
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Up to Date"
                    alert.informativeText = "AIMeter (v\(self.CURRENT_VERSION)) is already at the latest version."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
        task.resume()
    }
    
    func performOneStepUpdate(downloadUrl: String) {
        let appPath = Bundle.main.bundlePath
        let isHomebrew = appPath.contains("/Cellar/") || appPath.contains("/opt/homebrew/")
        let isDiskImage = appPath.contains("/Volumes/")
        
        if isDiskImage {
            let alert = NSAlert()
            alert.messageText = "Run from Applications"
            alert.informativeText = "AIMeter is currently running from a Disk Image (.dmg). To enable one-click updates, please drag AIMeter.app to your /Applications folder, then launch it from there."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        if isHomebrew {
            // Homebrew installation - run brew upgrade in Terminal
            let script = "tell application \"Terminal\" to do script \"brew update && brew upgrade aimeter && brew services restart aimeter\""
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            return
        }
        
        // Direct DMG/App execution - mount DMG, swap, and restart.
        let shellScript = """
        (
          sleep 1
          echo "=== Starting Update ==="
          echo "App path: \(appPath)"
          echo "Download URL: \(downloadUrl)"
          
          # Clean temp mount point if exists
          rm -rf /tmp/aimeter_mount
          mkdir -p /tmp/aimeter_mount
          
          # Download DMG
          echo "Downloading DMG..."
          curl -L -o /tmp/AIMeter_new.dmg "\(downloadUrl)"
          
          # Mount DMG
          echo "Mounting DMG..."
          hdiutil attach -mountpoint /tmp/aimeter_mount -nobrowse -readonly /tmp/AIMeter_new.dmg
          
          # Replace running bundle
          echo "Swapping app bundles..."
          mv "\(appPath)" "\(appPath).old"
          cp -R /tmp/aimeter_mount/AIMeter.app "\(appPath)"
          
          # Unmount and clean up
          echo "Unmounting and cleaning up..."
          hdiutil detach /tmp/aimeter_mount
          rm -f /tmp/AIMeter_new.dmg
          rm -rf /tmp/aimeter_mount
          
          # Launch new app
          echo "Launching updated app..."
          open "\(appPath)"
          
          # Delete backup app
          rm -rf "\(appPath).old"
          
          # Terminate this old app instance
          echo "Terminating old instance..."
          kill \(ProcessInfo.processInfo.processIdentifier)
        ) > /tmp/aimeter_update.log 2>&1 &
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", shellScript]
        
        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(self)
            }
        } catch {
            print("Failed to run update process: \(error)")
        }
    }
    
    @objc func forceSyncLogs() {
        let url = URL(string: "http://127.0.0.1:5333/api/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if error != nil {
                    print("Force sync failed.")
                } else {
                    print("Force sync completed.")
                    self.pollStats()
                }
            }
        }
        task.resume()
    }
    
    @objc func resetSpend() {
        let alert = NSAlert()
        alert.messageText = "Reset Today's AI Spend?"
        alert.informativeText = "Are you sure you want to delete today's tracked costs? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "http://127.0.0.1:5333/api/reset")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if error == nil {
                        self.pollStats()
                    }
                }
            }
            task.resume()
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc func openUpdateUrl(_ sender: NSMenuItem) {
        if let urlStr = sender.representedObject as? String, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func pollStats() {
        let url = URL(string: "http://127.0.0.1:5333/api/stats?range=\(currentPollRange)")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if error != nil {
                DispatchQueue.main.async {
                    self.updateMenuOffline()
                }
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    DispatchQueue.main.async {
                        self.updateMenuOnline(json: json)
                    }
                }
            } catch {
                print("JSON parsing error: \(error)")
            }
        }
        task.resume()
    }
    
    func updateMenuOffline() {
        if let button = statusItem.button {
            button.title = "$?.??"
            button.imagePosition = .imageLeft
            if let img = NSImage(systemSymbolName: "cpu.slash", accessibilityDescription: "Daemon Offline") {
                img.isTemplate = true
                button.image = img
            }
            button.contentTintColor = nil
        }
        spendLabel.stringValue = "AI Spend Today: Offline"
        anthropicLabel.stringValue = "  Anthropic: --"
        openaiLabel.stringValue = "  OpenAI: --"
        geminiLabel.stringValue = "  Google Gemini: --"
        claudeCodeLabel.stringValue = "  Claude Code: --"
        openrouterLabel.stringValue = "  OpenRouter: --"
    }
    
    func updateMenuOnline(json: [String: Any]) {
        guard let today = json["today"] as? [String: Any],
              let todayCost = today["cost"] as? Double,
              let config = json["config"] as? [String: Any],
              let providers = json["providers"] as? [String: Any] else {
            updateMenuOffline()
            return
        }
        
        let budgetString = config["daily_budget"] as? String ?? "5.00"
        let budget = Double(budgetString) ?? 5.0
        
        // Determine what to display in status bar based on daemon configuration
        var displayCost = todayCost
        var displaySuffix = ""
        var targetBudget = budget
        
        if let menuBar = json["menu_bar"] as? [String: Any],
           let mbCost = menuBar["cost"] as? Double,
           let period = menuBar["period"] as? String {
            displayCost = mbCost
            if period == "month" {
                displaySuffix = " (M)"
                targetBudget = budget * 30
                currentPollRange = "month"
            } else if period == "year" {
                displaySuffix = " (Y)"
                targetBudget = budget * 365
                currentPollRange = "year"
            } else {
                currentPollRange = "day"
            }
        }
        
        if let button = statusItem.button {
            button.title = String(format: "$%.2f%@", displayCost, displaySuffix)
            button.imagePosition = .imageLeft
            
            let symbolName: String

            if displayCost >= targetBudget {
                symbolName = "exclamationmark.triangle.fill"
            } else if displayCost >= targetBudget * 0.8 {
                symbolName = "cpu.fill"
            } else {
                symbolName = "cpu"
            }

            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName) {
                img.isTemplate = true
                button.image = img
            }
            button.contentTintColor = nil
        }
        var periodLabel = "Today"
        var budgetPeriod = "Daily"
        if let menuBar = json["menu_bar"] as? [String: Any],
           let period = menuBar["period"] as? String {
            if period == "month" {
                periodLabel = "This Month"
                budgetPeriod = "Monthly"
            } else if period == "year" {
                periodLabel = "This Year"
                budgetPeriod = "Yearly"
            }
        }
        
        spendLabel.stringValue = String(format: "AI Spend %@: $%.2f", periodLabel, displayCost)
        budgetLabel.stringValue = String(format: "%@ Budget: $%.2f", budgetPeriod, targetBudget)
        
        if let anthropic = providers["Anthropic"] as? [String: Any], let cost = anthropic["cost"] as? Double {
            anthropicLabel.stringValue = String(format: "  Anthropic: $%.3f", cost)
        }
        if let openai = providers["OpenAI"] as? [String: Any], let cost = openai["cost"] as? Double {
            openaiLabel.stringValue = String(format: "  OpenAI: $%.3f", cost)
        }
        if let gemini = providers["Google Gemini"] as? [String: Any], let cost = gemini["cost"] as? Double {
            geminiLabel.stringValue = String(format: "  Google Gemini: $%.3f", cost)
        }
        if let claudeCode = providers["Claude Code"] as? [String: Any], let cost = claudeCode["cost"] as? Double {
            claudeCodeLabel.stringValue = String(format: "  Claude Code: $%.3f", cost)
        }
        if let openrouter = providers["OpenRouter"] as? [String: Any], let cost = openrouter["cost"] as? Double {
            openrouterLabel.stringValue = String(format: "  OpenRouter: $%.3f", cost)
        }
        
        // Dynamic Update Available Menu Item Injection
        if let updateAvailable = json["update_available"] as? [String: Any],
           let ver = updateAvailable["version"] as? String,
           let urlStr = updateAvailable["url"] as? String {
            
            if let menu = statusItem.menu {
                if menu.item(withTitle: "⚡ Update Available (v\(ver))...") == nil {
                    // Clean up any old update items
                    for item in menu.items {
                        if item.title.contains("Update Available") {
                            menu.removeItem(item)
                        }
                    }
                    
                    let uItem = NSMenuItem(title: "⚡ Update Available (v\(ver))...", action: #selector(openUpdateUrl), keyEquivalent: "")
                    uItem.target = self
                    uItem.representedObject = urlStr
                    // Insert at index 0 (top of the dropdown)
                    menu.insertItem(uItem, at: 0)
                    
                    // Add a separator below the update item if needed
                    if menu.items.count > 1 && !menu.items[1].isSeparatorItem {
                        menu.insertItem(NSMenuItem.separator(), at: 1)
                    }
                }
            }
        } else {
            // Remove update item if not available
            if let menu = statusItem.menu {
                for (index, item) in menu.items.enumerated().reversed() {
                    if item.title.contains("Update Available") {
                        menu.removeItem(item)
                        if index < menu.items.count && menu.items[index].isSeparatorItem {
                            menu.removeItem(at: index)
                        }
                    }
                }
            }
        }
    }
}

// Check for CLI subcommands before starting GUI
let cliArgs = CommandLine.arguments
if cliArgs.count > 1 && cliArgs[1] == "setup" {
    let exePath = ProcessInfo.processInfo.arguments[0]
    let resolvedExe = URL(fileURLWithPath: exePath).resolvingSymlinksInPath()
    let exeDir = resolvedExe.deletingLastPathComponent()
    var cliPath = exeDir.appendingPathComponent("aimeter_cli.py").path

    if !FileManager.default.fileExists(atPath: cliPath) {
        // Try resolving via which
        let whichProc = Process()
        let whichPipe = Pipe()
        whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProc.arguments = ["aimeter"]
        whichProc.standardOutput = whichPipe
        try? whichProc.run()
        whichProc.waitUntilExit()
        let whichOutput = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !whichOutput.isEmpty {
            let resolved = URL(fileURLWithPath: whichOutput).resolvingSymlinksInPath()
            let resolvedDir = resolved.deletingLastPathComponent()
            let candidate = resolvedDir.appendingPathComponent("aimeter_cli.py").path
            if FileManager.default.fileExists(atPath: candidate) {
                cliPath = candidate
            }
        }
    }

    if FileManager.default.fileExists(atPath: cliPath) {
        let pythonArgs = ["python3", cliPath] + Array(cliArgs.dropFirst(1))
        let cStrings = pythonArgs.map { strdup($0) } + [nil]
        execvp("python3", cStrings)
        perror("execvp failed")
        exit(1)
    } else {
        print("Error: aimeter_cli.py not found at \(cliPath)")
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) {
    app.run()
}
