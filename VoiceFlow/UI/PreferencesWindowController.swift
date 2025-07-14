import Cocoa

/// Window controller for the MantaScribe preferences window
/// Manages window lifecycle, positioning, and coordination between preference panes
class PreferencesWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var preferencesViewController: PreferencesViewController!
    
    // MARK: - Initialization
    
    convenience init() {
        // Create the preferences view controller
        let preferencesVC = PreferencesViewController()
        
        // Create the window with proper Mac preferences styling
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = "MantaScribe Preferences"
        window.contentViewController = preferencesVC
        window.isReleasedWhenClosed = false
        window.center()
        
        // Set minimum and maximum size (fixed for now, expandable later for tabs)
        window.minSize = NSSize(width: 480, height: 360)
        window.maxSize = NSSize(width: 480, height: 360)
        
        // Initialize with the window
        self.init(window: window)
        
        // Store reference to view controller
        self.preferencesViewController = preferencesVC
        
        // Set up window delegate
        window.delegate = self
        
        // Restore window position if saved
        restoreWindowPosition()
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Interface
    
    /// Show the preferences window, bringing it to front
    func showPreferences() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("🔧 Preferences window shown")
    }
    
    /// Hide the preferences window
    func hidePreferences() {
        window?.orderOut(nil)
        print("🔧 Preferences window hidden")
    }
    
    // MARK: - Window Position Management
    
    private func restoreWindowPosition() {
        guard let window = self.window else { return }
        
        guard let savedFrame = PreferencesManager.shared.preferencesWindowFrame else {
            // No saved position, center the window
            window.center()
            return
        }
        
        // Validate the saved frame is still on screen
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        if screenFrame.contains(savedFrame) {
            window.setFrame(savedFrame, display: false)
        } else {
            // Saved position is off-screen, center it
            window.center()
        }
    }
    
    private func saveWindowPosition() {
        guard let window = window else { return }
        PreferencesManager.shared.preferencesWindowFrame = window.frame
    }
    
    // MARK: - Toolbar Setup (for future expansion)
    
    private func setupToolbarForTabs() {
        // This method will be used when we add multiple preference panes
        // For now, we have a single general preferences pane
        
        guard let window = window else { return }
        
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PreferencesToolbar"))
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.delegate = self
        
        window.toolbar = toolbar
        window.toolbarStyle = .preference
    }
}

// MARK: - NSWindowDelegate

extension PreferencesWindowController: NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        saveWindowPosition()
        print("🔧 Preferences window will close, position saved")
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        print("🔧 Preferences window became key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        print("🔧 Preferences window resigned key")
    }
    
    // Prevent the window from being resized (for now)
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        return sender.frame.size // Keep current size
    }
}

// MARK: - NSToolbarDelegate (for future tabs)

extension PreferencesWindowController: NSToolbarDelegate {
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // This will be implemented when we add multiple preference panes
        return nil
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Future: return identifiers for different preference panes
        return []
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Future: return default preference pane identifiers
        return []
    }
}

// MARK: - Singleton Access

extension PreferencesWindowController {
    
    /// Shared instance for app-wide access
    static let shared = PreferencesWindowController()
}
