/*
 * MantaScribe - AppDelegate.swift - Phase 7 Complete
 *
 * REFACTORING STATUS: Phase 7 Complete - MenuBarController Extracted
 *
 * COMPLETED EXTRACTIONS:
 * ✅ Phase 1: VocabularyManager
 * ✅ Phase 2: HotkeyManager
 * ✅ Phase 3: TextProcessor
 * ✅ Phase 4: AppTargetManager
 * ✅ Phase 5: SmartText Components (SpacingEngine, CapitalizationEngine, CursorDetector)
 * ✅ Phase 6: DictationEngine (speech recognition, audio engine, buffering)
 * ✅ Phase 7: MenuBarController (UI management, status updates, menu actions)
 *
 * REMAINING PHASES:
 * - Phase 8: Final AppDelegate cleanup and optimization
 */

import Cocoa
import Speech
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Core Components (Phases 1-7)
    
    private var hotkeyManager: HotkeyManager!
    private var textProcessor: TextProcessor!
    private var appTargetManager: AppTargetManager!
    private var dictationEngine: DictationEngine!
    private var menuBarController: MenuBarController!
    
    // MARK: - SmartText Components (Phase 5)
    
    private let cursorDetector = CursorDetector()
    private let capitalizationEngine = CapitalizationEngine()
    private let spacingEngine = SpacingEngine()
    
    // MARK: - State Properties
    
    var selectedTargetApp: AppTargetManager.TargetApp {
        get { return appTargetManager.selectedTargetApp }
        set { appTargetManager.setTargetApp(newValue) }
    }
    private var lastProcessedText = ""
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupComponents()
        setupMenuBarController()
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
        print("⌨️ HotkeyManager: Initialized")
    }
    
    private func setupTextProcessor() {
        textProcessor = TextProcessor()
        print("📝 TextProcessor: Initialized")
    }
    
    private func setupAppTargetManager() {
        appTargetManager = AppTargetManager()
        print("🎯 AppTargetManager: Initialized")
    }
    
    private func setupDictationEngine() {
        dictationEngine = DictationEngine()
        dictationEngine.delegate = self
        print("🎤 DictationEngine: Initialized")
    }
    
    private func setupMenuBarController() {
        menuBarController = MenuBarController(
            appTargetManager: appTargetManager,
            vocabularyManager: VocabularyManager.shared
        )
        menuBarController.delegate = self
        menuBarController.setupMenuBar()
        print("🖥️ MenuBarController: Initialized")
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
                    self.menuBarController.updateStatus(.success)
                case .appNotFound:
                    print("❌ Target app not found")
                    self.menuBarController.updateStatus(.error)
                case .launchFailed(let error):
                    print("❌ Failed to launch app: \(error)")
                    self.menuBarController.updateStatus(.error)
                case .focusRestoreFailed:
                    print("⚠️ Focus restore failed but text sent")
                    self.menuBarController.updateStatus(.success)
                }
            }
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
            menuBarController.updateStatus(.listening)
            return
        }
        
        lastProcessedText = finalText
        menuBarController.playSound("Purr")
        
        // Process and send using SmartText components
        processAndSendTextWithSmartComponents(finalText)
    }
    
    func dictationEngineDidStart(_ engine: DictationEngine) {
        print("🎤 Dictation started")
        menuBarController.playSound("Glass")
        menuBarController.updateStatus(.listening)
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(true)
    }
    
    func dictationEngineDidStop(_ engine: DictationEngine) {
        print("⏹️ Dictation stopped")
        menuBarController.updateStatus(.ready)
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(false)
    }
    
    func dictationEngine(_ engine: DictationEngine, didEncounterError error: Error) {
        print("❌ DictationEngine error: \(error.localizedDescription)")
        menuBarController.updateStatus(.error)
        
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

// MARK: - MenuBarControllerDelegate

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestToggleDictation(_ controller: MenuBarController) {
        if dictationEngine.isDictating {
            dictationEngine.stopDictation()
        } else {
            dictationEngine.startDictation()
        }
    }
    
    func menuBarController(_ controller: MenuBarController, didSelectTargetApp app: AppTargetManager.TargetApp) {
        selectedTargetApp = app
        print("🎯 Target changed to: \(app.displayName)")
    }
    
    func menuBarControllerDidRequestTestDictation(_ controller: MenuBarController) {
        let testText = "Test from MantaScribe with complete component architecture"
        processAndSendTextWithSmartComponents(testText)
    }
    
    func menuBarController(_ controller: MenuBarController, didToggleContextualCategory category: String, enabled: Bool) {
        let action = enabled ? "enabled" : "disabled"
        print("🎯 Contextual category '\(category)' \(action)")
        
        if dictationEngine.isDictating {
            print("⚠️ Contextual string changes will apply to next dictation session")
        }
    }
    
    func menuBarController(_ controller: MenuBarController, didToggleVocabularyCategory category: String, enabled: Bool) {
        let action = enabled ? "enabled" : "disabled"
        print("🎯 Legacy vocabulary category '\(category)' \(action)")
    }
    
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - App Lifecycle

extension AppDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
