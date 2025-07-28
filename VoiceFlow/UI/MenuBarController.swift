import Cocoa
import Foundation

/// Manages the menu bar interface with Fast/Smart mode toggle support
/// Provides a clean interface for all UI-related functionality
class MenuBarController: NSObject {
    
    // MARK: - Types
    
    enum Status {
        case ready, listening, processing, sending, success, error
    }
    
    // MARK: - Delegate Protocol
    
    weak var delegate: MenuBarControllerDelegate?
    
    // MARK: - Properties
    
    private var statusBarItem: NSStatusItem!
    
    // Dependencies
    private weak var appTargetManager: AppTargetManager?
    private weak var vocabularyManager: VocabularyManager?
    
    // MARK: - Initialization
    
    init(appTargetManager: AppTargetManager, vocabularyManager: VocabularyManager) {
        self.appTargetManager = appTargetManager
        self.vocabularyManager = vocabularyManager
        super.init()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Interface
    
    /// Setup the menu bar interface
    func setupMenuBar() {
        setupStatusBarItem()
        setupMenu()
        print("🖥️ MenuBarController: Menu bar setup complete")
    }
    
    /// Update the status bar with current dictation state
    func updateStatus(_ status: Status) {
        let (icon, title) = statusInfo(for: status)
        statusBarItem.button?.title = icon
        statusBarItem.menu?.items[0].title = title
        print("🖥️ MenuBarController: Status updated to \(status)")
    }
    
    /// Play system sound for feedback
    func playSound(_ soundName: String) {
        if let sound = NSSound(named: soundName) {
            sound.volume = 0.3
            sound.play()
        }
    }
    
    /// Update menu items to reflect current state
    func refreshMenu() {
        guard statusBarItem.menu != nil else { return }
        
        updateTargetAppMenu()
        updateVocabularyMenu()
        updatePerformanceModeMenu()
        print("🖥️ MenuBarController: Menu refreshed")
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "🎤"
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Main dictation toggle
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Right Option)", action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Performance mode toggle
        setupPerformanceModeMenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Target app submenu
        setupTargetAppSubmenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Medical vocabulary submenu
        setupVocabularySubmenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Additional actions
        menu.addItem(NSMenuItem(title: "Test Dictation", action: #selector(testDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
           menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About MantaScribe Pro", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
        
        // Set targets for menu items
        for item in menu.items {
            item.target = self
        }
    }
    
    private func setupPerformanceModeMenu(in menu: NSMenu) {
        let performanceMenu = NSMenu()
        
        let smartModeItem = NSMenuItem(title: "Smart Mode (Full Features)", action: #selector(selectSmartMode), keyEquivalent: "")
        smartModeItem.target = self
        smartModeItem.state = .on // Default to Smart Mode
        performanceMenu.addItem(smartModeItem)
        
        let fastModeItem = NSMenuItem(title: "Fast Mode (Performance Optimized)", action: #selector(selectFastMode), keyEquivalent: "")
        fastModeItem.target = self
        fastModeItem.state = .off
        performanceMenu.addItem(fastModeItem)
        
        performanceMenu.addItem(NSMenuItem.separator())
        
        let infoItem = NSMenuItem(title: "Fast Mode disables smart text processing", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        performanceMenu.addItem(infoItem)
        
        let performanceMenuItem = NSMenuItem(title: "Performance Mode", action: nil, keyEquivalent: "")
        performanceMenuItem.submenu = performanceMenu
        menu.addItem(performanceMenuItem)
    }
    
    private func setupTargetAppSubmenu(in menu: NSMenu) {
        guard let appTargetManager = appTargetManager else { return }
        
        let targetMenu = NSMenu()
        for app in appTargetManager.getAvailableApps() {
            let item = NSMenuItem(title: app.displayName, action: #selector(selectTargetApp(_:)), keyEquivalent: "")
            item.representedObject = app
            item.state = (app == appTargetManager.selectedTargetApp) ? .on : .off
            item.target = self
            targetMenu.addItem(item)
        }
        
        let targetMenuItem = NSMenuItem(title: "Target App", action: nil, keyEquivalent: "")
        targetMenuItem.submenu = targetMenu
        menu.addItem(targetMenuItem)
    }
    
    private func setupVocabularySubmenu(in menu: NSMenu) {
        guard let vocabularyManager = vocabularyManager else { return }
        
        let vocabularyMenu = NSMenu()
        
        // Add contextual categories
        setupContextualCategoriesMenu(in: vocabularyMenu, vocabularyManager: vocabularyManager)
        
        // Add legacy vocabulary categories
        setupLegacyCategoriesMenu(in: vocabularyMenu, vocabularyManager: vocabularyManager)
        
        // Handle empty vocabulary menu
        if vocabularyMenu.items.isEmpty {
            let item = NSMenuItem(title: "No vocabularies loaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            vocabularyMenu.addItem(item)
        }
        
        let vocabularyMenuItem = NSMenuItem(title: "Medical Vocabulary", action: nil, keyEquivalent: "")
        vocabularyMenuItem.submenu = vocabularyMenu
        menu.addItem(vocabularyMenuItem)
    }
    
    private func setupContextualCategoriesMenu(in vocabularyMenu: NSMenu, vocabularyManager: VocabularyManager) {
        let contextualCategories = vocabularyManager.getAvailableContextualCategories()
        if !contextualCategories.isEmpty {
            let headerItem = NSMenuItem(title: "Enhanced Recognition:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            vocabularyMenu.addItem(headerItem)
            
            for category in contextualCategories {
                let item = NSMenuItem(title: "  \(formatCategoryName(category))",
                                    action: #selector(toggleContextualCategory(_:)),
                                    keyEquivalent: "")
                item.representedObject = category
                item.state = vocabularyManager.getEnabledContextualCategories().contains(category) ? .on : .off
                item.target = self
                vocabularyMenu.addItem(item)
            }
            
            vocabularyMenu.addItem(NSMenuItem.separator())
        }
    }
    
    private func setupLegacyCategoriesMenu(in vocabularyMenu: NSMenu, vocabularyManager: VocabularyManager) {
        let legacyCategories = vocabularyManager.getAvailableCategories()
        if !legacyCategories.isEmpty {
            let headerItem = NSMenuItem(title: "Fallback Corrections:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            vocabularyMenu.addItem(headerItem)
            
            for category in legacyCategories {
                let item = NSMenuItem(title: "  \(category.capitalized)",
                                    action: #selector(toggleVocabularyCategory(_:)),
                                    keyEquivalent: "")
                item.representedObject = category
                item.state = vocabularyManager.getEnabledCategories().contains(category) ? .on : .off
                item.target = self
                vocabularyMenu.addItem(item)
            }
        }
    }
    
    // MARK: - Private Methods - Menu Updates
    
    private func updateTargetAppMenu() {
        guard let appTargetManager = appTargetManager,
              let targetMenu = findTargetAppMenuItem()?.submenu else { return }
        
        for item in targetMenu.items {
            if let app = item.representedObject as? AppTargetManager.TargetApp {
                item.state = (app == appTargetManager.selectedTargetApp) ? .on : .off
            }
        }
    }
    
    private func updateVocabularyMenu() {
        guard let vocabularyManager = vocabularyManager,
              let vocabularyMenuItem = findVocabularyMenuItem(),
              let vocabularyMenu = vocabularyMenuItem.submenu else { return }
        
        // Update contextual categories
        for item in vocabularyMenu.items {
            if let category = item.representedObject as? String {
                if item.action == #selector(toggleContextualCategory(_:)) {
                    item.state = vocabularyManager.getEnabledContextualCategories().contains(category) ? .on : .off
                } else if item.action == #selector(toggleVocabularyCategory(_:)) {
                    item.state = vocabularyManager.getEnabledCategories().contains(category) ? .on : .off
                }
            }
        }
    }
    
    private func updatePerformanceModeMenu() {
        guard let performanceMenuItem = findPerformanceModeMenuItem(),
              let performanceMenu = performanceMenuItem.submenu else { return }
        
        let isSmartMode = delegate?.menuBarControllerCurrentPerformanceMode(self) ?? true
        
        for item in performanceMenu.items {
            if item.action == #selector(selectSmartMode) {
                item.state = isSmartMode ? .on : .off
            } else if item.action == #selector(selectFastMode) {
                item.state = isSmartMode ? .off : .on
            }
        }
    }
    
    private func findTargetAppMenuItem() -> NSMenuItem? {
        guard let menu = statusBarItem.menu else { return nil }
        
        for item in menu.items {
            if item.title == "Target App" {
                return item
            }
        }
        return nil
    }
    
    private func findVocabularyMenuItem() -> NSMenuItem? {
        guard let menu = statusBarItem.menu else { return nil }
        
        for item in menu.items {
            if item.title == "Medical Vocabulary" {
                return item
            }
        }
        return nil
    }
    
    private func findPerformanceModeMenuItem() -> NSMenuItem? {
        guard let menu = statusBarItem.menu else { return nil }
        
        for item in menu.items {
            if item.title == "Performance Mode" {
                return item
            }
        }
        return nil
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleDictation() {
        delegate?.menuBarControllerDidRequestToggleDictation(self)
    }
    
    @objc private func selectSmartMode() {
        delegate?.menuBarControllerDidRequestTogglePerformanceMode(self)
        updatePerformanceModeMenu()
    }
    
    @objc private func selectFastMode() {
        delegate?.menuBarControllerDidRequestTogglePerformanceMode(self)
        updatePerformanceModeMenu()
    }
    
    @objc private func selectTargetApp(_ sender: NSMenuItem) {
        guard let targetApp = sender.representedObject as? AppTargetManager.TargetApp else { return }
        
        delegate?.menuBarController(self, didSelectTargetApp: targetApp)
        
        // Update menu checkmarks
        if let targetMenu = findTargetAppMenuItem()?.submenu {
            for item in targetMenu.items {
                item.state = .off
            }
            sender.state = .on
        }
        
        print("🎯 MenuBarController: Target app selected: \(targetApp.displayName)")
    }
    
    @objc private func testDictation() {
        delegate?.menuBarControllerDidRequestTestDictation(self)
    }
    
    @objc private func showAbout() {
        guard let appTargetManager = appTargetManager,
              let vocabularyManager = vocabularyManager else { return }
        
        let contextualCount = vocabularyManager.getContextualStrings().count
        let enabledCategories = vocabularyManager.getEnabledContextualCategories().count
        let isSmartMode = delegate?.menuBarControllerCurrentPerformanceMode(self) ?? true
        let performanceMode = isSmartMode ? "Smart Mode (Full Features)" : "Fast Mode (Performance Optimized)"
        
        let alert = NSAlert()
        alert.messageText = "MantaScribe Pro"
        alert.informativeText = """
        Professional medical dictation with enhanced speech recognition.
        
        ⚡ Performance Mode: \(performanceMode)
        🎯 Enhanced Recognition: \(contextualCount) medical terms available
        📚 Active Categories: \(enabledCategories) medical specialties
        🎤 Background Operation: Works while other apps have focus
        💬 Smart Processing: \(isSmartMode ? "Enabled" : "Disabled for speed")
        🏥 Multi-App Support: TextEdit, Pages, Notes, Word
        
        Target App: \(appTargetManager.selectedTargetApp.displayName)
        
        Fast Mode: Optimized for maximum speed with basic dictation
        Smart Mode: Full features with intelligent text processing
        
        Created for medical professionals, analysts, and researchers.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        print("🖥️ MenuBarController: About dialog shown")
    }
    
    @objc private func toggleContextualCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? String,
              let vocabularyManager = vocabularyManager else { return }
        
        var enabled = vocabularyManager.getEnabledContextualCategories()
        
        if enabled.contains(category) {
            enabled.removeAll { $0 == category }
            sender.state = .off
        } else {
            enabled.append(category)
            sender.state = .on
        }
        
        vocabularyManager.setEnabledContextualCategories(enabled)
        
        delegate?.menuBarController(self, didToggleContextualCategory: category, enabled: enabled.contains(category))
        
        print("🎯 MenuBarController: Contextual categories: \(enabled.joined(separator: ", "))")
    }
    
    @objc private func toggleVocabularyCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? String,
              let vocabularyManager = vocabularyManager else { return }
        
        var enabled = vocabularyManager.getEnabledCategories()
        
        if enabled.contains(category) {
            enabled.removeAll { $0 == category }
            sender.state = .off
        } else {
            enabled.append(category)
            sender.state = .on
        }
        
        vocabularyManager.setEnabledCategories(enabled)
        
        delegate?.menuBarController(self, didToggleVocabularyCategory: category, enabled: enabled.contains(category))
        
        print("🎯 MenuBarController: Legacy vocabulary categories: \(enabled.joined(separator: ", "))")
    }
    
    
    @objc private func quitApplication() {
        delegate?.menuBarControllerDidRequestQuit(self)
    }
    
    // MARK: - Private Methods - Utilities
    
    private func statusInfo(for status: Status) -> (String, String) {
        switch status {
        case .ready:
            return ("🎤", "Toggle Dictation (Right Option)")
        case .listening:
            return ("🔴", "Stop Dictation (Right Option)")
        case .processing:
            return ("⚡", "Processing...")
        case .sending:
            return ("📤", "Sending...")
        case .success:
            return ("✅", "Sent!")
        case .error:
            return ("❌", "Error")
        }
    }
    
    private func formatCategoryName(_ category: String) -> String {
        return category
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Delegate Protocol

protocol MenuBarControllerDelegate: AnyObject {
    /// Called when user requests to toggle dictation
    func menuBarControllerDidRequestToggleDictation(_ controller: MenuBarController)
    
    /// Called when user requests to toggle performance mode
    func menuBarControllerDidRequestTogglePerformanceMode(_ controller: MenuBarController)
    
    /// Called to get current performance mode state
    func menuBarControllerCurrentPerformanceMode(_ controller: MenuBarController) -> Bool
    
    /// Called when user selects a target app
    func menuBarController(_ controller: MenuBarController, didSelectTargetApp app: AppTargetManager.TargetApp)
    
    /// Called when user requests test dictation
    func menuBarControllerDidRequestTestDictation(_ controller: MenuBarController)
    
    /// Called when user toggles a contextual vocabulary category
    func menuBarController(_ controller: MenuBarController, didToggleContextualCategory category: String, enabled: Bool)
    
    /// Called when user toggles a legacy vocabulary category
    func menuBarController(_ controller: MenuBarController, didToggleVocabularyCategory category: String, enabled: Bool)
    
    /// Called when user requests to quit the application
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController)
}

// Add this to your existing MenuBarController.swift file

// MARK: - Preferences Integration
// Add these methods to your existing MenuBarController class

extension MenuBarController {
    
    // MARK: - Updated Menu Setup
    
    private func setupMenuWithPreferences() {
        // Updated version of your setupMenu() method to include preferences
        let menu = NSMenu()
        
        // Main dictation toggle
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Right Option)", action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Performance mode toggle
        setupPerformanceModeMenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Target app submenu
        setupTargetAppSubmenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Medical vocabulary submenu
        setupVocabularySubmenu(in: menu)
        menu.addItem(NSMenuItem.separator())
        
        // Additional actions
        menu.addItem(NSMenuItem(title: "Test Dictation", action: #selector(testDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // PREFERENCES MENU ITEM
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About MantaScribe Pro", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
        
        // Set targets for menu items
        for item in menu.items {
            item.target = self
        }
    }
    
    // MARK: - Preferences Action
    
    @objc private func showPreferences() {
        PreferencesWindowController.shared.showPreferences()
        print("🔧 MenuBarController: Preferences opened from menu bar")
    }
    
    // MARK: - Preference-aware Menu Updates
    
    private func updateMenuForPreferences() {
        // Update menu items based on current preferences
        
        // Update performance mode display
        updatePerformanceModeMenuFromPreferences()
        
        // Update other menu items based on preferences
        // TODO: Add other preference-aware menu updates as needed
    }
    
    private func updatePerformanceModeMenuFromPreferences() {
        guard let performanceMenuItem = findPerformanceModeMenuItem(),
              let performanceMenu = performanceMenuItem.submenu else { return }
        
        let currentMode = PreferencesManager.shared.performanceMode
        let isSmartMode = (currentMode == .smart)
        
        for item in performanceMenu.items {
            if item.action == #selector(selectSmartMode) {
                item.state = isSmartMode ? .on : .off
            } else if item.action == #selector(selectFastMode) {
                item.state = isSmartMode ? .off : .on
            }
        }
    }
    
    // MARK: - Updated Performance Mode Actions
    
    @objc private func selectSmartModeUpdated() {
        // Update the preference instead of just notifying delegate
        PreferencesManager.shared.performanceMode = .smart
        delegate?.menuBarControllerDidRequestTogglePerformanceMode(self)
        updatePerformanceModeMenuFromPreferences()
    }
    
    @objc private func selectFastModeUpdated() {
        // Update the preference instead of just notifying delegate
        PreferencesManager.shared.performanceMode = .fast
        delegate?.menuBarControllerDidRequestTogglePerformanceMode(self)
        updatePerformanceModeMenuFromPreferences()
    }
    
    // MARK: - Preference Change Handling
    
    private func setupPreferenceObservers() {
        // Call this from your init method
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferenceDidChange(_:)),
            name: PreferencesManager.preferenceDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func preferenceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateMenuForPreferences()
        }
    }
    

}

// MARK: - Integration Instructions

/*
To integrate preferences into your existing MenuBarController.swift:

1. Add this extension to your MenuBarController.swift file

2. In your MenuBarController init method, add:
   setupPreferenceObservers()

3. Replace your existing setupMenu() call with:
   setupMenuWithPreferences()

4. Optional: Replace your performance mode action methods with the updated versions:
   - Replace selectSmartMode with selectSmartModeUpdated
   - Replace selectFastMode with selectFastModeUpdated
   
   This will make the menu automatically save the user's performance mode preference.

5. The menu bar will now:
   - Include a "Preferences…" menu item
   - Automatically update when preferences change
   - Save performance mode selections to preferences
   - Show the standard Mac shortcut (⌘,) for preferences

Example menu structure:
┌─────────────────────────────┐
│ Toggle Dictation           │
├─────────────────────────────┤
│ Performance Mode        ►  │
│ Target App             ►  │
│ Medical Vocabulary     ►  │
├─────────────────────────────┤
│ Test Dictation            │
├─────────────────────────────┤
│ Preferences…           ⌘, │  ← New item
├─────────────────────────────┤
│ About MantaScribe Pro      │
│ Quit                   ⌘Q │
└─────────────────────────────┘
*/
