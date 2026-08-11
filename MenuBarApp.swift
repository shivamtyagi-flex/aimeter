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
        
        menu.addItem(NSMenuItem.separator())
        
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
    
    func pollStats() {
        let url = URL(string: "http://127.0.0.1:5333/api/stats")!
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
            } else if period == "year" {
                displaySuffix = " (Y)"
                targetBudget = budget * 365
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
        
        spendLabel.stringValue = String(format: "AI Spend Today: $%.2f", todayCost)
        budgetLabel.stringValue = String(format: "Daily Budget: $%.2f", budget)
        
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
