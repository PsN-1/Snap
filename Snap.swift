import Cocoa
import Carbon

class SnapApp: NSObject {
    private var hotkeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 9)
    private var hotkeyIDs: [EventHotKeyID] = []
    private var appPositions: [Int: String] = [:]
    private var hotkeyCallbacks: [Int: () -> Void] = [:]
    private var hotkeyCount = 0
    
    override init() {
        super.init()
        setupHotkeyHandler()
    }
    
    private func setupHotkeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        
        let callback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let theEvent = theEvent,
                  let app = Unmanaged<SnapApp>.fromOpaque(userData!).takeUnretainedValue() as SnapApp? else {
                return OSStatus(eventNotHandledErr)
            }
            return app.handleHotkeyEvent(theEvent)
        }
        
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        if status != noErr {
            print("Warning: Failed to install event handler, error: \(status)")
        }
    }
    
    private func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        var hotkeyID = EventHotKeyID()
        let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
        
        guard err == noErr else {
            print("Error getting hotkey ID: \(err)")
            return err
        }
        
        let position = Int(hotkeyID.id)
        print("🔥 Hotkey pressed: Ctrl+\(position)")
        hotkeyCallbacks[position]?()
        
        return noErr
    }
    
    func registerHotkey(keyCode: UInt32, modifiers: UInt32, position: Int) -> Bool {
        guard hotkeyCount < 9 else { return false }
        
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = FourCharCode(fromString: "snap")
        hotkeyID.id = UInt32(position)
        
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        
        guard status == noErr, let ref = hotkeyRef else {
            print("Failed to register hotkey for position \(position), error: \(status)")
            return false
        }
        
        hotkeyRefs[hotkeyCount] = ref
        hotkeyIDs.append(hotkeyID)
        hotkeyCount += 1
        
        return true
    }
    
    func unregisterHotkeys() {
        for i in 0..<hotkeyCount {
            if let ref = hotkeyRefs[i] {
                UnregisterEventHotKey(ref)
                hotkeyRefs[i] = nil
            }
        }
        hotkeyCount = 0
        hotkeyIDs.removeAll()
    }
    
    func refreshDockApps() {
        let script = """
        tell application "System Events"
            set dockApps to {}
            tell process "Dock"
                tell list 1
                    repeat with i from 1 to (count of UI elements)
                        try
                            set elem to UI element i
                            set appName to name of elem
                            if appName is not "" then
                                set end of dockApps to appName
                            end if
                        end try
                    end repeat
                end tell
            end tell
        end tell
        return dockApps
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if output.isEmpty {
                print("Warning: No dock apps found")
                return
            }
            
            let apps = output.components(separatedBy: ", ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            
            // Filter out Finder - it can't be moved and we skip it
            let filteredApps = apps.filter { $0 != "Finder" }
            
            appPositions.removeAll()
            for (index, app) in filteredApps.enumerated() {
                if index >= 9 { break }
                appPositions[index + 1] = app
            }
            
            print("\n📌 Current dock mapping:")
            for i in 1...9 {
                if let app = appPositions[i] {
                    print("  Ctrl+\(i) → \(app)")
                }
            }
            print()
            
        } catch {
            print("Error getting dock apps: \(error)")
        }
    }
    
    func launchAppAtPosition(_ position: Int) {
        guard let appName = appPositions[position] else {
            print("❌ No app at position \(position)")
            return
        }
        
        // Use NSWorkspace for much faster app launching (no AppleScript overhead)
        let workspace = NSWorkspace.shared
        
        // First, check if the app is already running - this is instant
        let runningApps = workspace.runningApplications
        if let runningApp = runningApps.first(where: { $0.localizedName == appName }) {
            // App is already running, just activate it (very fast)
            runningApp.activate()
            return
        }
        
        // App is not running, find and launch it
        // Try common locations first (fastest path - no searching needed)
        let commonPaths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                // Fire and forget - don't wait for completion (faster)
                workspace.openApplication(at: url, configuration: config, completionHandler: nil)
                return
            }
        }
        
        // Fallback: try to find app by bundle identifier
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            workspace.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }
    }
    
    func setupHotkeys() {
        // Key codes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9
        let keyCodes: [Int: UInt32] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25
        ]
        
        print("Registering hotkeys...")
        var successCount = 0
        
        for i in 1...9 {
            let position = i
            hotkeyCallbacks[position] = { [weak self] in
                self?.launchAppAtPosition(position)
            }
            
            guard let keyCode = keyCodes[position] else { continue }
            let modifiers = UInt32(controlKey) // Control key modifier
            
            if registerHotkey(keyCode: keyCode, modifiers: modifiers, position: position) {
                successCount += 1
            }
        }
        
        print("✓ Registered \(successCount)/9 hotkeys\n")
        
        if successCount == 0 {
            print("⚠️  Warning: No hotkeys were registered successfully!")
            print("This might be due to:")
            print("  - Missing accessibility permissions")
            print("  - Conflicts with system shortcuts")
            print("  - Another app using the same hotkeys")
            print()
        }
    }
    
    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func run() {
        if !checkAccessibility() {
            print("⚠️  Accessibility permissions are required!")
            print("Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility")
            print("Press Enter to continue anyway...")
            _ = readLine()
        }
        
        print("🚀 Snap - Dock App Launcher")
        print("Press Ctrl+1-9 to launch apps from your dock")
        print("Press Ctrl+C to quit")
        print()
        
        refreshDockApps()
        setupHotkeys()
        
        // Refresh dock apps periodically
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshDockApps()
        }
        
        print("✅ App is running. Press Ctrl+1-9 to launch apps, or Ctrl+C to quit.")
        print("   (Note: If running in Terminal, Control keys may be intercepted by Terminal)")
        
        // Process Carbon events in the run loop
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            var event: EventRef?
            let target = GetEventDispatcherTarget()
            ReceiveNextEvent(0, nil, 0.0, true, &event)
            if let event = event {
                SendEventToEventTarget(event, target)
                ReleaseEvent(event)
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        
        // Keep the app running
        RunLoop.current.run()
    }
}

// Extension to convert string to FourCharCode
extension FourCharCode {
    init(fromString string: String) {
        var result: FourCharCode = 0
        for (index, char) in string.utf8.prefix(4).enumerated() {
            result |= FourCharCode(char) << (8 * (3 - index))
        }
        self = result
    }
}

// Main entry point
let app = SnapApp()
app.run()

