import Cocoa
import Carbon

class SnapApp: NSObject {
    private var hotkeyRefs: [EventHotKeyRef?] = Array(repeating: nil, count: 11)
    private var hotkeyIDs: [EventHotKeyID] = []
    private var appPositions: [Int: String] = [:]
    private var hotkeyCallbacks: [Int: () -> Void] = [:]
    private var hotkeyCount = 0
    private var modifierKey: Int = controlKey
    private var modifierName: String = "Ctrl"
    private var ignoreFinder: Bool = true
    private var finderPosition: Int? = nil
    
    // Combo shortcut: one key launches multiple apps (e.g. Control+E or Control+5 → Notes, Reminders)
    // When combo uses a number (1-0), it takes that position and dock apps shift down
    private var comboHotkeyKey: String? = nil
    private var comboPosition: Int? = nil  // When combo uses a number, this is 1-10
    private var comboApps: [String] = []
    
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
    
    init(modifier: String = "control", ignoreFinder: Bool = true, finderPosition: Int? = nil, comboShortcut: String? = nil) {
        super.init()
        switch modifier.lowercased() {
        case "control", "ctrl":
            modifierKey = controlKey
            modifierName = "Ctrl"
        case "command", "cmd":
            modifierKey = cmdKey
            modifierName = "Cmd"
        case "option", "opt", "alt":
            modifierKey = optionKey
            modifierName = "Option"
        default:
            modifierKey = controlKey
            modifierName = "Ctrl"
        }
        self.ignoreFinder = ignoreFinder
        self.finderPosition = finderPosition
        if let combo = comboShortcut, !combo.isEmpty {
            let parts = combo.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                comboApps = String(parts[1]).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                if key.count == 1 && key.first?.isNumber == true {
                    // Number key: combo takes that position, dock apps shift down
                    comboHotkeyKey = key == "0" ? "0" : key
                    comboPosition = key == "0" ? 10 : Int(key)
                } else {
                    // Letter key: separate hotkey, no position shift
                    comboHotkeyKey = key.uppercased()
                    comboPosition = nil
                }
            }
        }
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
        
        let id = Int(hotkeyID.id)
        if id == 99 {
            // Combo shortcut
            print("🔥 Hotkey pressed: \(modifierName)+\(comboHotkeyKey ?? "?")")
            launchApps(comboApps)
        } else {
            let displayKey = id == 10 ? "0" : "\(id)"
            print("🔥 Hotkey pressed: \(modifierName)+\(displayKey)")
            hotkeyCallbacks[id]?()
        }
        
        return noErr
    }
    
    @inline(__always)
    func registerHotkey(keyCode: UInt32, modifiers: UInt32, position: Int) -> Bool {
        registerHotkey(keyCode: keyCode, modifiers: modifiers, hotkeyId: position)
    }
    
    @inline(__always)
    func registerHotkey(keyCode: UInt32, modifiers: UInt32, hotkeyId: Int) -> Bool {
        guard hotkeyCount < 11 else { return false }
        
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = FourCharCode(fromString: "snap")
        hotkeyID.id = UInt32(hotkeyId)
        
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        
        guard status == noErr, let ref = hotkeyRef else {
            print("Failed to register hotkey for id \(hotkeyId), error: \(status)")
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
            
            appPositions.removeAll()
            appURLs.removeAll()
            appBundleIDs.removeAll()
            runningAppRefs.removeAll()
            
            let runningApps = workspace.runningApplications
            
            print("\n📌 Current dock mapping:")
            
            // Reserved positions: combo (takes a slot) and Finder (if not ignored)
            let reservedPositions = [comboPosition, ignoreFinder ? nil : finderPosition].compactMap { $0 }
            var nextPosition = 1
            
            // Map non-Finder dock apps, skipping reserved slots (combo position, Finder position)
            for app in apps {
                if nextPosition > 10 { break }
                
                if app == "Finder" {
                    continue
                }
                
                while nextPosition <= 10 && reservedPositions.contains(nextPosition) {
                    nextPosition += 1
                }
                if nextPosition > 10 { break }
                
                let position = nextPosition
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
                
                let displayKey = position == 10 ? "0" : "\(position)"
                print("  \(status) \(modifierName)+\(displayKey) → \(app)")
                
                nextPosition += 1
            }
            
            // Show combo at its position if it uses a number
            if let pos = comboPosition, !comboApps.isEmpty {
                let displayKey = pos == 10 ? "0" : "\(pos)"
                print("  🔗 \(modifierName)+\(displayKey) → \(comboApps.joined(separator: ", ")) (combo)")
            }
            
            // Optionally insert Finder at the user-selected key
            if !ignoreFinder, let reserved = finderPosition,
               reserved >= 1, reserved <= 10,
               apps.contains("Finder") {
                
                let position = reserved
                let app = "Finder"
                appPositions[position] = app
                
                // Common locations for Finder
                let finderPaths = [
                    "/System/Library/CoreServices/Finder.app",
                    "/System/Applications/Finder.app",
                    "/Applications/Finder.app"
                ]
                
                var foundURL = false
                for path in finderPaths {
                    if FileManager.default.fileExists(atPath: path) {
                        appURLs[position] = URL(fileURLWithPath: path)
                        foundURL = true
                        break
                    }
                }
                
                var status = foundURL ? "📦" : "⚠️"
                if let runningApp = runningApps.first(where: { $0.localizedName == app }) {
                    appBundleIDs[position] = runningApp.bundleIdentifier
                    runningAppRefs[position] = runningApp
                    status = "✅"
                }
                
                let displayKey = position == 10 ? "0" : "\(position)"
                print("  \(status) \(modifierName)+\(displayKey) → \(app)")
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
    
    func launchApps(_ appNames: [String]) {
        for (index, appName) in appNames.enumerated() {
            let delay = 0.05 * Double(index)  // Stagger by 200ms each to avoid activation race
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.launchApp(named: appName)
            }
        }
    }
    
    private func launchApp(named appName: String) {
        let runningApps = workspace.runningApplications
        
        // Try to activate if already running
        if let runningApp = runningApps.first(where: { $0.localizedName == appName }) {
            if !runningApp.isTerminated {
                print("✅ Activating: \(appName)")
                runningApp.activate()
                return
            }
        }
        
        // Try to launch by path
        let commonPaths = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("🚀 Launching: \(appName)")
                let url = URL(fileURLWithPath: path)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = false
                workspace.openApplication(at: url, configuration: config, completionHandler: nil)
                return
            }
        }
        
        print("❌ Could not launch \(appName) - not found")
    }
    
    func setupHotkeys() {
        // Key codes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9, 29=0
        let keyCodes: [Int: UInt32] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25, 10: 29
        ]
        
        print("Registering hotkeys...")
        var successCount = 0
        
        for i in 1...10 {
            let position = i
            let modifiers = UInt32(modifierKey)
            
            if position == comboPosition {
                // This position is for combo - register combo hotkey instead of dock
                hotkeyCallbacks[99] = { [weak self] in
                    self?.launchApps(self?.comboApps ?? [])
                }
                if let keyCode = keyCodes[position],
                   registerHotkey(keyCode: keyCode, modifiers: modifiers, hotkeyId: 99) {
                    successCount += 1
                    let displayKey = position == 10 ? "0" : "\(position)"
                    print("✓ Combo shortcut: \(modifierName)+\(displayKey) → \(comboApps.joined(separator: ", "))")
                }
            } else {
                hotkeyCallbacks[position] = { [weak self] in
                    self?.launchAppAtPosition(position)
                }
                if let keyCode = keyCodes[position],
                   registerHotkey(keyCode: keyCode, modifiers: modifiers, position: position) {
                    successCount += 1
                }
            }
        }
        
        // Register letter combo shortcut if configured (e.g. Control+E → Notes, Reminders)
        if let keyName = comboHotkeyKey, comboPosition == nil, !comboApps.isEmpty {
            let letterKeyCodes: [String: UInt32] = [
                "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4,
                "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35,
                "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6
            ]
            if let keyCode = letterKeyCodes[keyName.uppercased()] {
                hotkeyCallbacks[99] = { [weak self] in
                    self?.launchApps(self?.comboApps ?? [])
                }
                if registerHotkey(keyCode: keyCode, modifiers: UInt32(modifierKey), hotkeyId: 99) {
                    successCount += 1
                    print("✓ Combo shortcut: \(modifierName)+\(keyName) → \(comboApps.joined(separator: ", "))")
                }
            }
        }
        
        print("✓ Registered \(successCount) hotkeys\n")
        
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
        print("Press \(modifierName)+1-0 to launch apps from your dock")
        if let key = comboHotkeyKey, !comboApps.isEmpty {
            print("Press \(modifierName)+\(key) to launch: \(comboApps.joined(separator: ", "))")
        }
        print("Press Ctrl+C to quit")
        print()
        
        refreshDockApps()
        setupHotkeys()
        
        var msg = "✅ App is running. Press \(modifierName)+1-0 to launch apps"
        if let key = comboHotkeyKey, !comboApps.isEmpty {
            msg += ", \(modifierName)+\(key) for combo"
        }
        print("\(msg), or Ctrl+C to quit.")
        print("   (Note: If running in Terminal, Control keys may be intercepted by Terminal)")
        
        // Process Carbon events in the run loop - optimized frequency (50ms instead of 100ms)
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
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

// Main entry point
let args = CommandLine.arguments
let modifier = args.count > 1 ? args[1] : "control"

// Parse Finder configuration from command-line arguments
var ignoreFinder = true
var finderPosition: Int? = nil

if args.count > 2 {
    let finderArg = args[2]
    if finderArg.lowercased() == "ignore" {
        ignoreFinder = true
    } else if let pos = Int(finderArg), (1...10).contains(pos) {
        ignoreFinder = false
        finderPosition = pos
    }
}

var comboShortcut: String? = nil
if args.count > 3 {
    comboShortcut = args[3]
}

let app = SnapApp(modifier: modifier, ignoreFinder: ignoreFinder, finderPosition: finderPosition, comboShortcut: comboShortcut)
app.run()


