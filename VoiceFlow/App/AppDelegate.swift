/*
 * MantaScribe - AppDelegate.swift - Clean Mode Integration with Voice Commands
 *
 * CLEAN ARCHITECTURE: Separated dictation modes and processing modes
 *
 * DICTATION MODES:
 * - Toggle: Continuous listening with pause detection
 * - Push-to-Talk: Accumulate until key release
 *
 * PROCESSING MODES:
 * - Fast: Minimal processing for maximum speed
 * - Smart: Full features (future re-integration point)
 *
 * VOICE COMMANDS:
 * - Processed before text transcription
 * - Extensible system for "scratch that", templates, navigation
 *
 * BENEFITS:
 * - No double transcription
 * - Clean mode separation
 * - Voice command architecture ready
 * - Future-ready for smart features
 * - Optimized performance
 */

import Cocoa
import Speech

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Performance Mode Management
    
    /// Performance mode selection
    private var isSmartModeEnabled = true {
        didSet {
            let mode = isSmartModeEnabled ? "Smart Mode" : "Fast Mode"
            print("⚡ Performance mode changed to: \(mode)")
            componentManager?.updatePerformanceMode(isSmartModeEnabled)
        }
    }
    
    // MARK: - Architecture Components
    
    /// Manages all core application components with clean dependency injection
    private var componentManager: ComponentManager!
    
    /// Processes voice commands before text transcription
    private var voiceCommandProcessor: VoiceCommandProcessor!
    
    /// Coordinates SmartText processing (only used in Smart Mode)
    private var smartTextCoordinator: SmartTextCoordinator!
    
    /// Tracks processed text for duplicate detection and workflow continuity
    private var lastProcessedText = ""
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        initializeArchitecture()
        requestRequiredPermissions()
        logApplicationReady()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Menu bar app - don't quit when no windows
    }
    
    // MARK: - Architecture Initialization
    
    private func initializeArchitecture() {
        // Initialize voice command processing system
        voiceCommandProcessor = VoiceCommandProcessor()
        voiceCommandProcessor.delegate = self
        
        // Initialize component management system
        componentManager = ComponentManager()
        componentManager.delegate = self
        componentManager.initializeAllComponents()
        componentManager.updatePerformanceMode(isSmartModeEnabled)
        
        // Connect voice commands to app target manager
        voiceCommandProcessor.setAppTargetManager(componentManager.appTargetManager)
        
        // Initialize SmartText coordination system (for future Smart Mode)
        smartTextCoordinator = SmartTextCoordinator()
        
        print("🏗️ MantaScribe: Clean architecture initialized with \(componentManager.componentCount) components + voice commands")
    }
    
    private func requestRequiredPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                let statusMessage = self.formatAuthorizationStatus(authStatus)
                print("🔒 Speech Recognition: \(statusMessage)")
            }
        }
    }
    
    private func logApplicationReady() {
        let targetApp = componentManager.currentTargetApp
        let vocabularyCount = VocabularyManager.shared.getContextualStrings().count
        let modeStatus = isSmartModeEnabled ? "Smart Mode (Future Features)" : "Fast Mode (Performance Optimized)"
        let commandCount = voiceCommandProcessor.getAvailableCommands().count
        
        print("""
        
        🎤 MantaScribe Pro - Professional Medical Dictation
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📱 Target: \(targetApp.displayName)
        🎯 Medical Terms: \(vocabularyCount) enhanced recognition terms
        ⌨️ Hotkey: Right Option (toggle & push-to-talk modes)
        ⚡ Performance: \(modeStatus)
        🎤 Voice Commands: \(commandCount) commands available
        🏗️ Architecture: Clean mode separation
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Ready for professional medical dictation workflows!
        
        """)
    }
    
    // MARK: - Text Processing Workflow
    
    private func processTextWithOptimalPath(_ rawText: String) {
        print("📝 Processing (\(isSmartModeEnabled ? "Smart" : "Fast")): '\(rawText)'")
        
        // STEP 1: Check for voice commands first
        let commandResult = voiceCommandProcessor.processText(rawText)
        
        switch commandResult {
        case .commandExecuted(let message):
            print("🎤 Voice command executed: \(message)")
            // Command executed, don't send as text
            return
            
        case .textToSend(let processedText):
            // Not a command, continue with normal text processing
            if isSmartModeEnabled {
                processWithSmartMode(processedText)
            } else {
                processWithFastMode(processedText)
            }
            
        case .commandNotRecognized:
            print("🎤 Unknown command attempted: '\(rawText)'")
            // Could show user feedback or just ignore
            return
        }
    }
    
    private func processWithSmartMode(_ rawText: String) {
        // Future: Full smart processing pipeline
        let processedText = applyBasicProcessing(to: rawText)
        
        // Future: SmartText intelligence
        smartTextCoordinator.processAndSend(
            text: processedText,
            targetApp: componentManager.currentTargetApp,
            appTargetManager: componentManager.appTargetManager
        ) { [weak self] result in
            self?.handleTextSendResult(result)
        }
        
        lastProcessedText = processedText
    }
    
    private func processWithFastMode(_ rawText: String) {
        // Fast mode: minimal processing, direct send
        let processedText = componentManager.textProcessor.processPunctuationCommands(rawText)
        
        // Direct send with minimal formatting
        componentManager.appTargetManager.sendText(
            processedText,
            shouldCapitalize: false,  // No smart capitalization
            needsLeadingSpace: true,  // Simple default spacing
            needsTrailingSpace: false,
            completion: { [weak self] result in
                self?.handleTextSendResult(result)
            }
        )
        
        lastProcessedText = processedText
    }
    
    private func applyBasicProcessing(to text: String) -> String {
        // Basic processing for both modes
        return componentManager.textProcessor.processPunctuationCommands(text)
    }
    
    private func handleTextSendResult(_ result: AppTargetManager.AppSwitchResult) {
        DispatchQueue.main.async {
            switch result {
            case .success:
                self.componentManager.updateStatus(.success)
            case .appNotFound, .launchFailed, .focusRestoreFailed:
                self.componentManager.updateStatus(.error)
            }
        }
    }
    
    // MARK: - Performance Mode Toggle
    
    private func togglePerformanceMode() {
        isSmartModeEnabled.toggle()
        componentManager.refreshMenu()
        
        let newMode = isSmartModeEnabled ? "Smart Mode" : "Fast Mode"
        let description = isSmartModeEnabled ?
            "Future features: smart text, medical vocabulary, intelligent formatting" :
            "Performance optimized: basic dictation with minimal processing"
            
        showModeChangeAlert(mode: newMode, description: description)
    }
    
    private func showModeChangeAlert(mode: String, description: String) {
        let alert = NSAlert()
        alert.messageText = "Performance Mode Changed"
        alert.informativeText = "Now using: \(mode)\n\n\(description)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Utility Methods
    
    private func formatAuthorizationStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "✅ Authorized"
        case .denied: return "❌ Denied"
        case .restricted: return "⚠️ Restricted"
        case .notDetermined: return "⏳ Pending"
        @unknown default: return "❓ Unknown"
        }
    }
}

// MARK: - Component Manager Delegate

extension AppDelegate: ComponentManagerDelegate {
    fileprivate func componentManagerDidRequestToggleDictation(_ manager: ComponentManager) {
        if manager.isDictating {
            manager.stopDictation()
        } else {
            manager.startDictation()
        }
    }
    
    fileprivate func componentManagerDidRequestTogglePerformanceMode(_ manager: ComponentManager) {
        togglePerformanceMode()
    }
    
    fileprivate func componentManagerCurrentPerformanceMode(_ manager: ComponentManager) -> Bool {
        return isSmartModeEnabled
    }
    
    fileprivate func componentManager(_ manager: ComponentManager, didProcessText text: String) {
        processTextWithOptimalPath(text)
    }
    
    fileprivate func componentManagerDidStartDictation(_ manager: ComponentManager) {
        print("🎤 Dictation started")
    }
    
    fileprivate func componentManagerDidStopDictation(_ manager: ComponentManager) {
        print("⏹️ Dictation stopped")
    }
    
    fileprivate func componentManager(_ manager: ComponentManager, didEncounterError error: Error) {
        print("❌ Component error: \(error.localizedDescription)")
    }
}

// MARK: - Voice Command Processor Delegate

extension AppDelegate: VoiceCommandProcessorDelegate {
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didExecuteUndo count: Int) {
        let countText = count == 1 ? "command" : "\(count) commands"
        print("🎤 Undo executed: \(countText)")
        
        // Optional: Show brief status feedback
        if isSmartModeEnabled {
            componentManager?.updateStatus(.success)
        }
    }
    
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didExecuteNavigation command: String) {
        print("🎤 Navigation command: \(command)")
        // Future: Handle navigation commands
    }
    
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didEncounterUnknownCommand text: String) {
        print("🎤 Unknown command: \(text)")
        // Future: Could show user feedback for unrecognized commands
    }
}

// MARK: - Component Manager

/// Manages all application components with clean mode coordination
fileprivate class ComponentManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: ComponentManagerDelegate?
    
    // Core components
    private(set) var hotkeyManager: HotkeyManager!
    private(set) var textProcessor: TextProcessor!
    private(set) var appTargetManager: AppTargetManager!
    private(set) var dictationEngine: DictationEngine!
    private(set) var menuBarController: MenuBarController!
    
    // Performance mode state
    private var isSmartModeEnabled = true
    
    var componentCount: Int { return 5 }
    var isDictating: Bool { return dictationEngine.isDictating }
    var currentTargetApp: AppTargetManager.TargetApp { return appTargetManager.selectedTargetApp }
    
    // MARK: - Initialization
    
    func initializeAllComponents() {
        initializeCoreComponents()
        initializeUIComponents()
        connectComponentDelegates()
    }
    
    private func initializeCoreComponents() {
        hotkeyManager = HotkeyManager()
        textProcessor = TextProcessor()
        appTargetManager = AppTargetManager()
        dictationEngine = DictationEngine()
        print("🔧 Core components initialized")
    }
    
    private func initializeUIComponents() {
        menuBarController = MenuBarController(
            appTargetManager: appTargetManager,
            vocabularyManager: VocabularyManager.shared
        )
        menuBarController.setupMenuBar()
        print("🖥️ UI components initialized")
    }
    
    private func connectComponentDelegates() {
        hotkeyManager.delegate = self
        dictationEngine.delegate = self
        menuBarController.delegate = self
        print("🔗 Component delegates connected")
    }
    
    // MARK: - Performance Mode Management
    
    func updatePerformanceMode(_ smartModeEnabled: Bool) {
        isSmartModeEnabled = smartModeEnabled
        
        // Update DictationEngine for performance mode
        if let engine = dictationEngine {
            engine.updatePerformanceMode(smartModeEnabled)
        }
        
        print("⚡ Components updated for \(smartModeEnabled ? "Smart" : "Fast") mode")
    }
    
    func refreshMenu() {
        menuBarController.refreshMenu()
    }
    
    // MARK: - Component Coordination
    
    func startDictation() {
        dictationEngine.startDictation()
    }
    
    func stopDictation() {
        dictationEngine.stopDictation()
    }
    
    func updateStatus(_ status: MenuBarController.Status) {
        if isSmartModeEnabled {
            menuBarController.updateStatus(status)
        } else {
            // Fast mode: minimal status updates
            if status == .error {
                menuBarController.updateStatus(status)
            }
        }
    }
    
    func playSound(_ soundName: String) {
        if isSmartModeEnabled {
            menuBarController.playSound(soundName)
        }
        // Fast mode: no audio feedback for speed
    }
}

// MARK: - Component Manager Delegates

extension ComponentManager: HotkeyManagerDelegate {
    func hotkeyManager(_ manager: HotkeyManager, didDetectAction action: HotkeyManager.HotkeyAction) {
        switch action {
        case .startDictation(let mode):
            // Communicate mode to dictation engine before starting
            dictationEngine.setDictationMode(mode)
            delegate?.componentManagerDidRequestToggleDictation(self)
            
        case .stopDictation:
            delegate?.componentManagerDidRequestToggleDictation(self)
        }
    }
}

extension ComponentManager: DictationEngineDelegate {
    func dictationEngine(_ engine: DictationEngine, didProcessText text: String) {
        delegate?.componentManager(self, didProcessText: text)
    }
    
    func dictationEngineDidStart(_ engine: DictationEngine) {
        if isSmartModeEnabled {
            playSound("Glass")
            updateStatus(.listening)
        }
        hotkeyManager.updateRecordingState(true)
        delegate?.componentManagerDidStartDictation(self)
    }
    
    func dictationEngineDidStop(_ engine: DictationEngine) {
        updateStatus(.ready)
        hotkeyManager.updateRecordingState(false)
        delegate?.componentManagerDidStopDictation(self)
    }
    
    func dictationEngine(_ engine: DictationEngine, didEncounterError error: Error) {
        updateStatus(.error)
        delegate?.componentManager(self, didEncounterError: error)
    }
}

extension ComponentManager: MenuBarControllerDelegate {
    func menuBarControllerDidRequestToggleDictation(_ controller: MenuBarController) {
        delegate?.componentManagerDidRequestToggleDictation(self)
    }
    
    func menuBarControllerDidRequestTogglePerformanceMode(_ controller: MenuBarController) {
        delegate?.componentManagerDidRequestTogglePerformanceMode(self)
    }
    
    func menuBarControllerCurrentPerformanceMode(_ controller: MenuBarController) -> Bool {
        return delegate?.componentManagerCurrentPerformanceMode(self) ?? true
    }
    
    func menuBarController(_ controller: MenuBarController, didSelectTargetApp app: AppTargetManager.TargetApp) {
        appTargetManager.setTargetApp(app)
        print("🎯 Target: \(app.displayName)")
    }
    
    func menuBarControllerDidRequestTestDictation(_ controller: MenuBarController) {
        let mode = isSmartModeEnabled ? "Smart" : "Fast"
        delegate?.componentManager(self, didProcessText: "Test from MantaScribe Pro - \(mode) Mode")
    }
    
    func menuBarController(_ controller: MenuBarController, didToggleContextualCategory category: String, enabled: Bool) {
        let action = enabled ? "enabled" : "disabled"
        print("🎯 Contextual category '\(category)' \(action)")
    }
    
    func menuBarController(_ controller: MenuBarController, didToggleVocabularyCategory category: String, enabled: Bool) {
        let action = enabled ? "enabled" : "disabled"
        print("🎯 Vocabulary category '\(category)' \(action)")
    }
    
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - SmartText Coordinator (Future Smart Mode Integration)

/// Coordinates all SmartText components for future smart mode re-integration
fileprivate class SmartTextCoordinator {
    
    // Future smart mode integration point
    // Will be re-enabled when smart mode is fully implemented
    
    /// Process text with future SmartText intelligence
    func processAndSend(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager,
        completion: @escaping (AppTargetManager.AppSwitchResult) -> Void
    ) {
        
        print("🧠 SmartText processing (future): '\(text)'")
        
        // Future: Smart analysis and processing
        // For now: Direct send with basic formatting
        appTargetManager.sendText(
            text,
            shouldCapitalize: false,
            needsLeadingSpace: true,
            needsTrailingSpace: false,
            completion: completion
        )
    }
}

// MARK: - Supporting Types

fileprivate protocol ComponentManagerDelegate: AnyObject {
    func componentManagerDidRequestToggleDictation(_ manager: ComponentManager)
    func componentManagerDidRequestTogglePerformanceMode(_ manager: ComponentManager)
    func componentManagerCurrentPerformanceMode(_ manager: ComponentManager) -> Bool
    func componentManager(_ manager: ComponentManager, didProcessText text: String)
    func componentManagerDidStartDictation(_ manager: ComponentManager)
    func componentManagerDidStopDictation(_ manager: ComponentManager)
    func componentManager(_ manager: ComponentManager, didEncounterError error: Error)
}
