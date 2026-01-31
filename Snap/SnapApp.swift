//
//  SnapApp.swift
//  Snap
//
//  Created by Pedro Neto on 31/01/26.
//

import Cocoa
import SwiftUI

// Import the SnapApp class from Snap.swift
// Note: Make sure Snap.swift is added to the Xcode project target

@main
struct SnapAppWrapper: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var snapApp: SnapApp?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from dock (runs in background)
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize and run the Snap app
        snapApp = SnapApp()
        snapApp?.run()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        snapApp?.unregisterHotkeys()
    }
}
