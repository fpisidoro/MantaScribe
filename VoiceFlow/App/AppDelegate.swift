/*
 * MantaScribe - AppDelegate.swift - Phase 5 Complete
 *
 * REFACTORING STATUS: Phase 5 Complete - SmartText Components Integrated
 *
 * COMPLETED EXTRACTIONS:
 * ✅ Phase 1: VocabularyManager
 * ✅ Phase 2: HotkeyManager
 * ✅ Phase 3: TextProcessor
 * ✅ Phase 4: AppTargetManager
 * ✅ Phase 5: SmartText Components (SpacingEngine, CapitalizationEngine, CursorDetector)
 *
 * REMAINING PHASES:
 * - Phase 6: DictationEngine extraction
 * - Phase 7: MenuBarController extraction
 * - Phase 8: Final AppDelegate cleanup
 */

import Cocoa
import Speech
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - UI Properties
    
    var statusBarItem: NSStatusItem!
    
    // MARK: - Speech Recognition Properties (Phase 6 - to be extracted)
    
    var speechRecognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    var audioEngine = AVAudioEngine()
    var isRecording = false
    var bufferTimer: Timer?
    var currentBuffer = ""
    var hasProcessedBuffer = false
    var isCurrentlyProcessing = false
    
    // MARK: - Core Components (Phases 1-4)
    
    private var hotkeyManager: HotkeyManager!
    private var textProcessor: TextProcessor!
    private var appTargetManager: AppTargetManager!
    
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
        setupHotkeyManager()
        setupTextProcessor()
        setupAppTargetManager()
        setupMenuBar()
        setupSpeechRecognition()
        
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
    
    func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        
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
        let testText = "Test from MantaScribe with enhanced SmartText processing"
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
        
        if isRecording {
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
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }
    
    // MARK: - Dictation Methods (Phase 6 - to be extracted)
    
    func startDictation() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            return
        }
        
        print("🎙️ Starting enhanced medical dictation...")
        
        playSound("Glass")
        updateStatus(.listening)
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(true)
        
        currentBuffer = ""
        hasProcessedBuffer = false
        isCurrentlyProcessing = false
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Failed to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Apply contextual strings for enhanced medical recognition
        let contextualStrings = VocabularyManager.shared.getContextualStrings()
        if !contextualStrings.isEmpty {
            recognitionRequest.contextualStrings = contextualStrings
            print("🎯 Applied \(contextualStrings.count) contextual strings for enhanced medical recognition")
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("❌ Audio engine failed: \(error)")
            updateStatus(.error)
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                let confidence = self.calculateConfidence(from: result.bestTranscription)
                
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.bufferTimer?.invalidate()
                        
                        if !self.hasProcessedBuffer && !text.isEmpty {
                            if self.textProcessor.isSubstantiallySimilar(text, to: self.lastProcessedText) {
                                print("🔄 Final result skipped - too similar to recent text: '\(text)'")
                            } else {
                                self.currentBuffer = text
                                print("🎯 Final result - processing buffer: '\(text)'")
                                
                                self.bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                                    DispatchQueue.main.async {
                                        guard let self = self else { return }
                                        if !self.hasProcessedBuffer && !self.currentBuffer.isEmpty {
                                            self.flushBuffer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if !self.hasProcessedBuffer && !text.isEmpty {
                        self.currentBuffer = text
                        
                        DispatchQueue.main.async {
                            self.updateStatus(.processing)
                        }
                        
                        self.bufferTimer?.invalidate()
                        
                        var timeout: TimeInterval
                        if confidence > 0.9 && (text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")) {
                            timeout = 0.3
                        } else if confidence > 0.8 {
                            timeout = 0.8
                        } else if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
                            timeout = 1.0
                        } else {
                            timeout = 1.5
                        }
                        
                        self.bufferTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                if !self.hasProcessedBuffer && self.isRecording && !self.currentBuffer.isEmpty {
                                    self.flushBuffer()
                                }
                            }
                        }
                    }
                }
            }
            
            if let error = error {
                print("❌ Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.stopDictation()
                }
            }
        }
        
        isRecording = true
    }
    
    func flushBuffer() {
        guard !currentBuffer.isEmpty && !hasProcessedBuffer && !isCurrentlyProcessing else {
            print("🚫 Skipping flush - already processed or processing")
            return
        }
        
        isCurrentlyProcessing = true
        
        let textToProcess = currentBuffer.trimmingCharacters(in: .whitespaces)
        updateStatus(.sending)
        
        // Process text using TextProcessor
        let vocabularyProcessed = VocabularyManager.shared.processText(textToProcess)
        let processedText = textProcessor.processPunctuationCommands(vocabularyProcessed)
        
        hasProcessedBuffer = true
        currentBuffer = ""
        bufferTimer?.invalidate()
        
        print("📝 Final output: '\(processedText)'")
        
        if textProcessor.isSubstantiallySimilar(processedText, to: lastProcessedText) {
            print("🔄 Skipping - too similar to recent: '\(lastProcessedText)'")
            isCurrentlyProcessing = false
            updateStatus(.listening)
            return
        }
        
        lastProcessedText = processedText
        playSound("Purr")
        
        // PHASE 5: Process and send using SmartText components
        processAndSendTextWithSmartComponents(processedText)
        
        isCurrentlyProcessing = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasProcessedBuffer = false
            if !self.isRecording {
                self.updateStatus(.ready)
            } else {
                self.updateStatus(.listening)
            }
        }
    }
    
    func stopDictation() {
        print("⏹️ Stopping dictation")
        
        // Update hotkey manager with recording state
        hotkeyManager.updateRecordingState(false)
        
        if !currentBuffer.isEmpty && !hasProcessedBuffer && !isCurrentlyProcessing {
            print("📝 Processing final buffer: '\(currentBuffer)'")
            flushBuffer()
        } else {
            print("✅ No buffer to process or already handled")
        }
        
        currentBuffer = ""
        hasProcessedBuffer = true
        isCurrentlyProcessing = false
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        bufferTimer?.invalidate()
        
        updateStatus(.ready)
        hasProcessedBuffer = false
    }
    
    // MARK: - PHASE 5: SmartText Processing & Sending
    
    private func processAndSendTextWithSmartComponents(_ text: String) {
        print("🚨 PROCESSING TEXT WITH SMARTTEXT COMPONENTS")
        
        let isPunctuation = spacingEngine.isPunctuation(text)
        
        print("🎯 Sending: '\(text)' to \(selectedTargetApp.displayName)")
        
        // PHASE 5: Use SmartText components for context analysis
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
    
    private func calculateConfidence(from transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(segments.count)
    }
    
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
            if !isRecording {
                startDictation()
            } else {
                // If already recording, this is a toggle to stop
                stopDictation()
            }
        case .stopDictation:
            if isRecording {
                stopDictation()
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension AppDelegate: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isRecording {
                self.stopDictation()
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
