/*
 * MantaScribe - AppDelegate.swift - Phase 6 Complete
 *
 * REFACTORING STATUS: Phase 6 Complete - DictationEngine Extracted
 *
 * COMPLETED EXTRACTIONS:
 * ✅ Phase 1: VocabularyManager
 * ✅ Phase 2: HotkeyManager
 * ✅ Phase 3: TextProcessor
 * ✅ Phase 4: AppTargetManager
 * ✅ Phase 5: SmartText Components (SpacingEngine, CapitalizationEngine, CursorDetector)
 * ✅ Phase 6: DictationEngine (speech recognition, audio engine, buffering)
 *
 * REMAINING PHASES:
 * - Phase 7: MenuBarController extraction
 * - Phase 8: Final AppDelegate cleanup
 */

import Cocoa
import Speech
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - UI Properties (Phase 7 - to be extracted)
    
    var statusBarItem: NSStatusItem!
    
    // MARK: - Core Components (Phases 1-6)
    
    private var hotkeyManager: HotkeyManager!
    private var textProcessor: TextProcessor!
    private var appTargetManager: AppTargetManager!
    private var dictationEngine: DictationEngine!
    
    // MARK: - SmartText Components (Phase 5)
    
    private let cursorDetector = CursorDetector()
    private let capitalizationEngine = CapitalizationEngine()
    private let spacingEngine = SpacingEngine()
    
    // MARK: - State Properties
    
    var selectedTargetApp: AppTargetManager.TargetApp {
        get { return appTargetManager.selectedTargetApp }
        set { appTargetManager.setTargetApp(newValue) }
    }
    var lastDetectedChars = ""
    var lastProcessedText = ""
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupComponents()
        setupMenuBar()
        requestSpeechPermissions()
        
        print("🎤 MantaScribe Pro Ready!")
        print("Target: \(selectedTargetApp.displayName)")
        print("Press Right Option key to toggle dictation")
        
        // Initialize vocabulary manager
        _ = VocabularyManager.shared
        
        // Log contextual strings status
        let contextualCount = VocabularyManager.shared.getContextualStrings().count
        print("🎯 Enhanced medical recognition: \(contextualCount) contextual terms loaded")
    }
    
    // MARK: - Setup Methods
    
    private func setupComponents() {
        setupHotkeyManager()
        setupTextProcessor()
        setupAppTargetManager()
        setupDictationEngine()
    }
    
    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self
    }
    
    private func setupTextProcessor() {
        textProcessor = TextProcessor()
    }
    
    private func setupAppTargetManager() {
        appTargetManager = AppTargetManager()
    }
    
    private func setupDictationEngine() {
        dictationEngine = DictationEngine()
        dictationEngine.delegate = self
    }
    
    private func requestSpeechPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    print("❌ Speech recognition denied")
                case .restricted:
                    print("⚠️ Speech recognition restricted")
                case .notDetermined:
                    print("⏳ Speech recognition pending")
                @unknown default:
                    print("❓ Unknown speech recognition status")
                }
            }
        }
    }
    
    // MARK: - Menu Bar Setup (Phase 7 - to be extracted)
    
    func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "🎤"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Right Option)", action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Target app submenu
        let targetMenu = NSMenu()
        for app in appTargetManager.getAvailableApps() {
            let item = NSMenuItem(title: app.displayName, action: #selector(selectTargetApp(_:)), keyEquivalent: "")
            item.representedObject = app
            item.state = (app == selectedTargetApp) ? .on : .off
            targetMenu.addItem(item)
        }
        
        let targetMenuItem = NSMenuItem(title: "Target App", action: nil, keyEquivalent: "")
        targetMenuItem.submenu = targetMenu
        menu.addItem(targetMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Medical Vocabulary submenu
        let vocabularyMenu = NSMenu()
        
        // Add contextual categories
        let contextualCategories = VocabularyManager.shared.getAvailableContextualCategories()
        if !contextualCategories.isEmpty {
            let headerItem = NSMenuItem(title: "Enhanced Recognition:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            vocabularyMenu.addItem(headerItem)
            
            for category in contextualCategories {
                let item = NSMenuItem(title: "  \(formatCategoryName(category))",
                                    action: #selector(toggleContextualCategory(_:)),
                                    keyEquivalent: "")
                item.representedObject = category
                item.state = VocabularyManager.shared.getEnabledContextualCategories().contains(category) ? .on : .off
                vocabularyMenu.addItem(item)
            }
            
            vocabularyMenu.addItem(NSMenuItem.separator())
        }
        
        // Add legacy vocabulary categories
        let legacyCategories = VocabularyManager.shared.getAvailableCategories()
        if !legacyCategories.isEmpty {
            let headerItem = NSMenuItem(title: "Fallback Corrections:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            vocabularyMenu.addItem(headerItem)
            
            for category in legacyCategories {
                let item = NSMenuItem(title: "  \(category.capitalized)",
                                    action: #selector(toggleVocabularyCategory(_:)),
                                    keyEquivalent: "")
                item.representedObject = category
                item.state = VocabularyManager.shared.getEnabledCategories().contains(category) ? .on : .off
                vocabularyMenu.addItem(item)
            }
        }
        
        if vocabularyMenu.items.isEmpty {
            let item = NSMenuItem(title: "No vocabularies loaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            vocabularyMenu.addItem(item)
        }
        
        let vocabularyMenuItem = NSMenuItem(title: "Medical Vocabulary", action: nil, keyEquivalent: "")
        vocabularyMenuItem.submenu = vocabularyMenu
        menu.addItem(vocabularyMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Test Dictation", action: #selector(testDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About MantaScribe Pro", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusBarItem.menu = menu
    }
    
    // MARK: - Menu Actions
    
    @objc func selectTargetApp(_ sender: NSMenuItem) {
        guard let targetApp = sender.representedObject as? AppTargetManager.TargetApp else { return }
        
        selectedTargetApp = targetApp
        print("🎯 Target changed to: \(targetApp.displayName)")
        
        if let targetMenu = statusBarItem.menu?.item(at: 2)?.submenu {
            for item in targetMenu.items {
                item.state = .off
            }
            sender.state = .on
        }
    }
    
    @objc func testDictation() {
        let testText = "Test from MantaScribe with DictationEngine integration"
        processAndSendTextWithSmartComponents(testText)
    }
    
    @objc func showAbout() {
        let contextualCount = VocabularyManager.shared.getContextualStrings().count
        let enabledCategories = VocabularyManager.shared.getEnabledContextualCategories().count
        
        let alert = NSAlert()
        alert.messageText = "MantaScribe Pro"
        alert.informativeText = """
        Professional medical dictation with enhanced speech recognition.
        
        🎯 Enhanced Recognition: \(contextualCount) medical terms active
        📚 Active Categories: \(enabledCategories) medical specialties
        🎤 Background Operation: Works while other apps have focus
        💬 Smart Processing: Intelligent capitalization and spacing
        🏥 Multi-App Support: TextEdit, Pages, Notes, Word
        
        Target App: \(selectedTargetApp.displayName)
        
        Created for medical professionals, analysts, and researchers.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func toggleContextualCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? String else { return }
        
        var enabled = VocabularyManager.shared.getEnabledContextualCategories()
        
        if enabled.contains(category) {
            enabled.removeAll { $0 == category }
            sender.state = .off
        } else {
            enabled.append(category)
            sender.state = .on
        }
        
        VocabularyManager.shared.setEnabledContextualCategories(enabled)
        print("🎯 Contextual categories: \(enabled.joined(separator: ", "))")
        
        if dictationEngine.isDictating {
            print("⚠️ Contextual string changes will apply to next dictation session")
        }
    }
    
    @objc func toggleVocabularyCategory(_ sender: NSMenuItem) {
        guard let category = sender.representedObject as? String else { return }
        
        var enabled = VocabularyManager.shared.getEnabledCategories()
        
        if enabled.contains(category) {
            enabled.removeAll { $0 == category }
            sender.state = .off
        } else {
            enabled.append(category)
            sender.state = .on
        }
        
        VocabularyManager.shared.setEnabledCategories(enabled)
        print("🎯 Legacy vocabulary categories: \(enabled.joined(separator: ", "))")
    }
    
    @objc func toggleDictation() {
        if dictationEngine.isDictating {
            dictationEngine.stopDictation()
        } else {
            dictationEngine.startDictation()
        }
    }
    
    // MARK: - SmartText Processing & Sending
    
    private func processAndSendTextWithSmartComponents(_ text: String) {
        print("🚨 PROCESSING TEXT WITH SMARTTEXT COMPONENTS")
        
        let isPunctuation = spacingEngine.isPunctuation(text)
        
        print("🎯 Sending: '\(text)' to \(selectedTargetApp.displayName)")
        
        // Use SmartText components for context analysis
        let cursorResult = cursorDetector.detectCursorContext()
        let shouldCapitalize = cursorResult.context.shouldCapitalize
        
        // Apply smart capitalization
        let capitalizationResult = capitalizationEngine.applyCapitalization(
            to: text,
            shouldCapitalizeStart: shouldCapitalize
        )
        
        // Determine spacing needs
        let spacingDecision = spacingEngine.determineSpacing(
            for: capitalizationResult.text,
            detectedChars: cursorResult.detectedChars,
            isPunctuation: isPunctuation
        )
        
        print("📝 SmartText analysis complete:")
        print("   Cursor context: \(cursorResult.context)")
        print("   Detected chars: '\(cursorResult.detectedChars.debugDescription)'")
        print("   Capitalization: \(capitalizationResult.reason)")
        print("   Spacing: \(spacingDecision.reason)")
        
        // Send via AppTargetManager with SmartText results
        appTargetManager.sendText(
            capitalizationResult.text,
            shouldCapitalize: shouldCapitalize,
            needsLeadingSpace: spacingDecision.needsLeadingSpace,
            needsTrailingSpace: spacingDecision.needsTrailingSpace
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.updateStatus(.success)
                case .appNotFound:
                    print("❌ Target app not found")
                    self.updateStatus(.error)
                case .launchFailed(let error):
                    print("❌ Failed to launch app: \(error)")
                    self.updateStatus(.error)
                case .focusRestoreFailed:
                    print("⚠️ Focus restore failed but text sent")
                    self.updateStatus(.success)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatCategoryName(_ category: String) -> String {
        return category
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    // MARK: - Status Management (Phase 7 - to be extracted)
    
    enum Status {
        case ready, listening, processing, sending, success, error
    }
    
    func updateStatus(_ status: Status) {
        let (icon, title) = statusInfo(for: status)
        statusBarItem.button?.title = icon
        statusBarItem.menu?.items[0].title = title
    }
    
    func statusInfo(for status: Status) -> (String, String) {
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
    
    func playSound(_ soundName: String) {
        if let sound = NSSound(named: soundName) {
            sound.volume = 0.3
            sound.play()
        }
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate: HotkeyManagerDelegate {
    func hotkeyManager(_ manager: HotkeyManager, didDetectToggle action: HotkeyManager.HotkeyAction) {
        switch action {
        case .startDictation:
            if !dictationEngine.isDictating {
                dictationEngine.startDictation()
            } else {
                // If already dictating, this is a toggle to stop
                dictationEngine.stopDictation()
            }
        case .stopDictation:
            if dictationEngine.isDictating {
                dictationEngine.stopDictation()
            }
        }
    }
}

// MARK: - DictationEngineDelegate

extension AppDelegate: DictationEngineDelegate {
    func dictationEngine(_ engine: DictationEngine, didProcessText text: String) {
        print("📝 DictationEngine processed text: '\(text)'")
        
        // Process text using TextProcessor and VocabularyManager
        let vocabularyProcessed = VocabularyManager.shared.processText(text)
        let finalText = textProcessor.processPunctuationCommands(vocabularyProcessed)
        
        print("📝 Final processed text: '\(finalText)'")
        
        // Check for similarity to recent text
        if textProcessor.isSubstantiallySimilar(finalText, to: lastProcessedText) {
            print("🔄 Skipping - too similar to recent: '\(lastProcessedText)'")
            updateStatus(.listening)
            return
        }
        
        lastProcessedText = finalText
        playSound("Purr")
        
        // Process and send using SmartText components
        processAndSendTextWithSmartComponents(finalText)
    }
    
    func dictationEngineDidStart(_ engine: DictationEngine) {
        print("🎤 Dictation started")
        playSound("Glass")
        updateStatus(.listening)
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(true)
    }
    
    func dictationEngineDidStop(_ engine: DictationEngine) {
        print("⏹️ Dictation stopped")
        updateStatus(.ready)
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(false)
    }
    
    func dictationEngine(_ engine: DictationEngine, didEncounterError error: Error) {
        print("❌ DictationEngine error: \(error.localizedDescription)")
        updateStatus(.error)
        
        // Show user-friendly error if needed
        if let dictationError = error as? DictationEngine.DictationError {
            switch dictationError {
            case .speechRecognizerUnavailable:
                print("❌ Speech recognizer not available")
            case .audioEngineFailure(let audioError):
                print("❌ Audio engine failed: \(audioError)")
            case .recognitionRequestCreationFailed:
                print("❌ Failed to create recognition request")
            case .recognitionTaskFailed(let taskError):
                print("❌ Recognition task failed: \(taskError)")
            }
        }
    }
}

// Prevent app termination when no windows
extension AppDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
