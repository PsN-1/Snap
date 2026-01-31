import Cocoa
import Carbon
import Darwin.C

class SnapApp: NSObject {
    private var hotkeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 9)
    private var hotkeyIDs: [EventHotKeyID] = []
    private var appPositions: [Int: String] = [:]
    private var hotkeyCallbacks: [Int: () -> Void] = [:]
    private var hotkeyCount = 0
    
    // Pre-computed app URLs and bundle IDs for maximum speed
    private var appURLs: [Int: URL] = [:]
    private var appBundleIDs: [Int: String] = [:]
    private var runningAppRefs: [Int: NSRunningApplication] = [:]
    
    // Cached workspace reference (avoid repeated access)
    private let workspace = NSWorkspace.shared
    
    // Cancellation mechanism - optimized for speed
    private var lastLaunchTime: UInt64 = 0
    private var pendingPosition: Int? = nil
    
    // Dedicated high-priority queue for launches
    private let launchQueue = DispatchQueue(label: "com.snap.launch", qos: .userInteractive, attributes: [])
    
    // Keep reference to event processing timer
    private var eventTimer: Timer?
    
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
    
    @inline(__always)
    private func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        var hotkeyID = EventHotKeyID()
        let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
        
        guard err == noErr else { return err }
        
        let position = Int(hotkeyID.id)
        print("🔥 Hotkey pressed: Ctrl+\(position)")
        hotkeyCallbacks[position]?()
        
        return noErr
    }
    
    @inline(__always)
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
            appURLs.removeAll()
            appBundleIDs.removeAll()
            runningAppRefs.removeAll()
            
            let runningApps = workspace.runningApplications
            
            print("\n📌 Current dock mapping:")
            for (index, app) in filteredApps.enumerated() {
                if index >= 9 { break }
                let position = index + 1
                appPositions[position] = app
                
                // Pre-compute app URL for maximum speed
                let commonPaths = [
                    "/Applications/\(app).app",
                    "/System/Applications/\(app).app",
                    "/System/Applications/Utilities/\(app).app"
                ]
                
                var foundURL = false
                for path in commonPaths {
                    if FileManager.default.fileExists(atPath: path) {
                        appURLs[position] = URL(fileURLWithPath: path)
                        foundURL = true
                        break
                    }
                }
                
                // Pre-compute bundle ID and running app reference if available
                var status = foundURL ? "📦" : "⚠️"
                if let runningApp = runningApps.first(where: { $0.localizedName == app }) {
                    appBundleIDs[position] = runningApp.bundleIdentifier
                    runningAppRefs[position] = runningApp
                    status = "✅"
                }
                
                print("  \(status) Ctrl+\(position) → \(app)")
            }
            print()
            
        } catch {
            print("Error getting dock apps: \(error)")
        }
    }
    
    @inline(__always)
    func launchAppAtPosition(_ position: Int) {
        guard let appName = appPositions[position] else {
            print("❌ No app at position \(position)")
            return
        }
        
        // Ultra-fast path 1: Direct reference to running app (fastest - no lookup needed)
        if let runningApp = runningAppRefs[position] {
            if !runningApp.isTerminated {
                print("✅ Activating: \(appName)")
                runningApp.activate()
                return
            } else {
                // App terminated, remove from cache
                print("⚠️ App \(appName) terminated, removing from cache")
                runningAppRefs.removeValue(forKey: position)
            }
        }
        
        // Ultra-fast path 2: Pre-computed URL (instant launch)
        if let url = appURLs[position] {
            print("🚀 Launching: \(appName)")
            let currentTime = mach_absolute_time()
            lastLaunchTime = currentTime
            pendingPosition = position
            
            // Use dedicated high-priority queue, minimal delay (3ms for cancellation)
            launchQueue.asyncAfter(deadline: .now() + 0.003) { [weak self] in
                guard let self = self else { return }
                guard self.pendingPosition == position, self.lastLaunchTime == currentTime else {
                    print("⏭️ Launch cancelled for: \(appName)")
                    return
                }
                
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = false
                self.workspace.openApplication(at: url, configuration: config, completionHandler: nil)
            }
            return
        }
        
        // Fallback: try to find running app by bundle ID (one-time lookup)
        if let bundleID = appBundleIDs[position],
           let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            print("✅ Found and activating: \(appName)")
            runningAppRefs[position] = runningApp
            runningApp.activate()
            return
        }
        
        print("❌ Could not launch \(appName) - not found")
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
        // Check if running from terminal (has stdin) or from Xcode/GUI
        let isTerminal = isatty(STDIN_FILENO) != 0
        let isAppBundle = Bundle.main.bundleIdentifier != nil
        
        if !checkAccessibility() {
            print("⚠️  Accessibility permissions are required!")
            print("Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility")
            if isTerminal {
                print("Press Enter to continue anyway...")
                _ = readLine()
            } else {
                print("Continuing anyway...")
            }
        }
        
        print("🚀 Snap - Dock App Launcher")
        print("Press Ctrl+1-9 to launch apps from your dock")
        if isTerminal {
            print("Press Ctrl+C to quit")
        }
        print()
        
        refreshDockApps()
        setupHotkeys()
        
        print("✅ App is running. Press Ctrl+1-9 to launch apps", terminator: "")
        if isTerminal {
            print(", or Ctrl+C to quit.")
        } else {
            print(".")
        }
        if isTerminal {
            print("   (Note: If running in Terminal, Control keys may be intercepted by Terminal)")
        }
        
        // Process Carbon events in the run loop - optimized frequency (50ms instead of 100ms)
        // Store timer reference to prevent deallocation
        eventTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
            var event: EventRef?
            let target = GetEventDispatcherTarget()
            ReceiveNextEvent(0, nil, 0.0, true, &event)
            if let event = event {
                SendEventToEventTarget(event, target)
                ReleaseEvent(event)
            }
        }
        RunLoop.current.add(eventTimer!, forMode: .common)
        RunLoop.current.add(eventTimer!, forMode: .default)
        
        // Only run the run loop if not in an app bundle (terminal mode)
        // GUI apps already have a running run loop
        if !isAppBundle {
            RunLoop.current.run()
        }
    }
}

// Extension to convert string to FourCharCode - optimized
extension FourCharCode {
    @inline(__always)
    init(fromString string: String) {
        let bytes = string.utf8.prefix(4)
        var result: FourCharCode = 0
        var shift = 24
        for byte in bytes {
            result |= FourCharCode(byte) << shift
            shift -= 8
        }
        self = result
    }
}


