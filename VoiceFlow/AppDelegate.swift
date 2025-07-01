import Cocoa
import Speech
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusBarItem: NSStatusItem!
    var speechRecognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    var audioEngine = AVAudioEngine()
    var isRecording = false
    var bufferTimer: Timer?
    var currentBuffer = ""
    var hasProcessedBuffer = false
    var lastProcessedText = ""
    var lastSentenceEnded = true // Track if last sentence ended with punctuation
    var rightOptionPressed = false // Track right option state
    
    // Target app selection
    enum TargetApp: String, CaseIterable {
        case textEdit = "TextEdit"
        case pages = "Pages"
        case notes = "Notes"
        case word = "Microsoft Word"
        
        var displayName: String { return self.rawValue }
        var bundleId: String {
            switch self {
            case .textEdit: return "com.apple.TextEdit"
            case .pages: return "com.apple.iWork.Pages"
            case .notes: return "com.apple.Notes"
            case .word: return "com.microsoft.Word"
            }
        }
    }
    
    var selectedTargetApp: TargetApp = .textEdit
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMenuBar()
        setupSpeechRecognition()
        
        print("🎤 VoiceFlow Ready! (Speed Optimized)")
        print("Target: \(selectedTargetApp.displayName)")
        print("Press Right Option key to toggle dictation")
    }
    
    func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "🎤"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Right Option)", action: #selector(toggleDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Target app submenu
        let targetMenu = NSMenu()
        for app in TargetApp.allCases {
            let item = NSMenuItem(title: app.displayName, action: #selector(selectTargetApp(_:)), keyEquivalent: "")
            item.representedObject = app
            item.state = (app == selectedTargetApp) ? .on : .off
            targetMenu.addItem(item)
        }
        
        let targetMenuItem = NSMenuItem(title: "Target App", action: nil, keyEquivalent: "")
        targetMenuItem.submenu = targetMenu
        menu.addItem(targetMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Test Dictation", action: #selector(testDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About VoiceFlow", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusBarItem.menu = menu
        
        // Setup RIGHT OPTION with ENHANCED detection for background apps
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let rawFlags = event.modifierFlags.rawValue
            
            // Be more aggressive about detecting Right Option from background
            if rawFlags == 524608 {
                if !self.rightOptionPressed {
                    self.rightOptionPressed = true
                    print("🎤 RIGHT OPTION DETECTED FROM BACKGROUND - toggling dictation")
                    // Add small delay to ensure event is fully processed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.toggleDictation()
                    }
                }
            } else if self.rightOptionPressed && rawFlags != 524608 {
                self.rightOptionPressed = false
                print("🎤 Right Option released from background")
            }
        }
        
        // Local event monitor for when app has focus
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let rawFlags = event.modifierFlags.rawValue
            
            if rawFlags == 524608 && !self.rightOptionPressed {
                self.rightOptionPressed = true
                print("🎤 RIGHT OPTION DETECTED LOCALLY - toggling dictation")
                self.toggleDictation()
            } else if rawFlags != 524608 && self.rightOptionPressed {
                self.rightOptionPressed = false
            }
            
            return event
        }
    }
    
    @objc func selectTargetApp(_ sender: NSMenuItem) {
        guard let targetApp = sender.representedObject as? TargetApp else { return }
        
        selectedTargetApp = targetApp
        print("🎯 Target changed to: \(targetApp.displayName)")
        
        // Update menu checkmarks
        if let targetMenu = statusBarItem.menu?.item(at: 2)?.submenu {
            for item in targetMenu.items {
                item.state = .off
            }
            sender.state = .on
        }
    }
    
    @objc func testDictation() {
        sendText("Test from VoiceFlow - \(Date())")
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "VoiceFlow"
        alert.informativeText = "Professional background dictation for macOS.\n\nTarget: \(selectedTargetApp.displayName)\n\nPress Right Option to dictate while focused on other apps.\n\nCreated for medical professionals, analysts, and researchers who need to document findings while examining visual data."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
                    print("❌ Speech recognition denied - check Settings > Privacy & Security > Speech Recognition")
                case .restricted:
                    print("⚠️ Speech recognition restricted on this device")
                case .notDetermined:
                    print("⏳ Speech recognition permission pending")
                @unknown default:
                    print("❓ Unknown speech recognition status")
                }
            }
        }
    }
    
    @objc func toggleDictation() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }
    
    func startDictation() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            return
        }
        
        print("🎙️ Starting dictation...")
        
        playSound("Glass")
        updateStatus(.listening)
        
        // Reset buffer state
        currentBuffer = ""
        hasProcessedBuffer = false
        lastProcessedText = ""
        lastSentenceEnded = true // Start fresh - first word should be capitalized
        
        // Clean up previous session
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Failed to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // OPTIMIZED AUDIO SETUP - smaller buffer for lower latency
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        // Reduced buffer size: 512 instead of 1024 for faster processing
        inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { [weak self] buffer, _ in
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
        
        // OPTIMIZED RECOGNITION with confidence-based timing
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                
                // Calculate confidence from available segments
                let confidence = self.calculateConfidence(from: result.bestTranscription)
                
                if result.isFinal {
                    // Final result - process immediately
                    DispatchQueue.main.async {
                        self.bufferTimer?.invalidate()
                        if !self.hasProcessedBuffer && !text.isEmpty {
                            self.currentBuffer = text
                            self.flushBuffer()
                        }
                    }
                } else {
                    // Partial result with CONFIDENCE-BASED early flushing
                    if !self.hasProcessedBuffer && !text.isEmpty {
                        self.currentBuffer = text
                        
                        DispatchQueue.main.async {
                            self.updateStatus(.processing)
                        }
                        
                        self.bufferTimer?.invalidate()
                        
                        // SPEED IMPROVEMENT: Dynamic timeout based on confidence and content
                        var timeout: TimeInterval
                        
                        if confidence > 0.9 && (text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")) {
                            timeout = 0.3 // Very confident punctuation = fast flush
                        } else if confidence > 0.8 {
                            timeout = 0.8 // High confidence = medium speed
                        } else if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
                            timeout = 1.0 // Punctuation ending
                        } else if self.isProbablyComplete(text) {
                            timeout = 1.2 // Seems complete based on content
                        } else {
                            timeout = 1.5 // Default for uncertain text
                        }
                        
                        print("🧠 Confidence: \(String(format: "%.2f", confidence)), Timeout: \(timeout)s")
                        
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
        guard !currentBuffer.isEmpty && !hasProcessedBuffer else { return }
        
        // SPEED IMPROVEMENT: Immediate visual feedback
        updateStatus(.sending)
        
        let processedText = processPunctuationCommands(currentBuffer)
        
        if isPunctuationDuplicate(processedText) {
            print("🔄 Skipping duplicate punctuation: '\(processedText)'")
            hasProcessedBuffer = true
            updateStatus(.listening)
            return
        }
        
        // Handle capitalization based on sentence continuation
        let finalText = handleContinuationCapitalization(processedText)
        
        hasProcessedBuffer = true
        print("📝 Sending: \(finalText)")
        lastProcessedText = finalText
        
        // Update sentence state - check if this text ends with punctuation
        lastSentenceEnded = finalText.hasSuffix(".") || finalText.hasSuffix("!") || finalText.hasSuffix("?") || finalText.hasSuffix(":") || finalText.hasSuffix(";")
        
        // SPEED IMPROVEMENT: Audio feedback is async, don't wait
        playSound("Purr")
        
        currentBuffer = ""
        bufferTimer?.invalidate()
        
        // Send immediately
        sendText(finalText)
        
        // Faster reset for next sentence
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasProcessedBuffer = false
            if !self.isRecording {
                self.updateStatus(.ready)
            } else {
                self.updateStatus(.listening)
            }
        }
    }
    
    // Process punctuation commands with context awareness
    func processPunctuationCommands(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        
        // Handle punctuation commands ONLY if they're standalone
        let words = trimmed.split(separator: " ")
        
        // Only process as punctuation if it's a single word command
        if words.count == 1 {
            switch lowercased {
            case "period", "full stop":
                return "."
            case "comma":
                return ","
            case "question mark":
                return "?"
            case "exclamation point", "exclamation mark":
                return "!"
            case "colon":
                return ":"
            case "semicolon":
                return ";"
            default:
                return text
            }
        } else {
            // Multi-word phrases - check if it ends with punctuation command
            if lowercased.hasSuffix(" period") {
                let baseText = String(trimmed.dropLast(7)) // Remove " period"
                return baseText + "."
            }
            if lowercased.hasSuffix(" comma") {
                let baseText = String(trimmed.dropLast(6)) // Remove " comma"
                return baseText + ","
            }
            if lowercased.hasSuffix(" question mark") {
                let baseText = String(trimmed.dropLast(14)) // Remove " question mark"
                return baseText + "?"
            }
            if lowercased.hasSuffix(" exclamation point") || lowercased.hasSuffix(" exclamation mark") {
                let suffixLength = lowercased.hasSuffix(" exclamation point") ? 18 : 16
                let baseText = String(trimmed.dropLast(suffixLength))
                return baseText + "!"
            }
            
            return text
        }
    }
    
    // Check if this punctuation was just sent
    func isPunctuationDuplicate(_ text: String) -> Bool {
        let punctuation = [".", ",", "?", "!", ":", ";"]
        
        // If current text is punctuation and matches last processed
        if punctuation.contains(text) && text == lastProcessedText {
            return true
        }
        
        // Also check if we just sent this punctuation within the last few characters
        if punctuation.contains(text) && lastProcessedText.hasSuffix(text) {
            return true
        }
        
        return false
    }
    
    // Handle capitalization for sentence continuation
    func handleContinuationCapitalization(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return text }
        
        // If last sentence ended with punctuation, keep original capitalization
        if lastSentenceEnded {
            return trimmed
        }
        
        // If continuing mid-sentence, check if first word should be lowercase
        let words = trimmed.split(separator: " ")
        guard let firstWord = words.first else { return trimmed }
        
        let firstWordString = String(firstWord)
        let lowercaseFirstWord = firstWordString.lowercased()
        
        // Words that should typically be lowercase mid-sentence
        let midSentenceWords = [
            "for", "but", "and", "or", "so", "yet", "nor",
            "with", "without", "about", "after", "before", "during",
            "in", "on", "at", "by", "from", "to", "of", "the",
            "a", "an", "this", "that", "these", "those",
            "he", "she", "it", "they", "we", "you", "his", "her",
            "then", "when", "where", "while", "since", "because"
        ]
        
        // If the first word is typically lowercase mid-sentence, convert it
        if midSentenceWords.contains(lowercaseFirstWord) {
            let lowercaseFirst = lowercaseFirstWord + trimmed.dropFirst(firstWordString.count)
            print("🔤 Capitalization fix: '\(trimmed)' → '\(lowercaseFirst)'")
            return lowercaseFirst
        }
        
        // Keep original capitalization for proper nouns, medical terms, etc.
        return trimmed
    }
    
    // Calculate confidence from transcription segments
    func calculateConfidence(from transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        // Average confidence across all segments
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(segments.count)
    }
    
    // Smart completion detection based on content patterns
    func isProbablyComplete(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Medical/professional phrase patterns that often indicate completion
        let completionPatterns = [
            "years old",
            "was normal",
            "was abnormal",
            "follow up",
            "discharged",
            "admitted",
            "prescribed",
            "advised",
            "recommended",
            "working",
            "not working"
        ]
        
        // Check if text ends with any completion patterns
        for pattern in completionPatterns {
            if lowercased.hasSuffix(pattern) {
                return true
            }
        }
        
        // Check for common sentence structures
        if lowercased.contains(" and ") && text.count > 20 {
            return true // Longer sentences with "and" are often complete thoughts
        }
        
        return false
    }
    
    func stopDictation() {
        print("⏹️ Stopping dictation")
        
        // IMPORTANT: Clear buffer state FIRST to prevent re-processing
        let hadBuffer = !currentBuffer.isEmpty && !hasProcessedBuffer
        currentBuffer = ""  // Clear immediately
        hasProcessedBuffer = true  // Prevent any processing
        
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
        
        // Only flush if there was actually unprocessed content AND we want to send it
        // For now, let's NOT auto-send on stop to prevent the duplication issue
        if hadBuffer {
            print("🗑️ Discarded unprocessed buffer to prevent duplication")
        }
        
        // Reset for next session
        hasProcessedBuffer = false
    }
    
    // ENHANCED TEXT SENDING with forced app activation
    func sendText(_ text: String) {
        // Smart spacing: don't add space before punctuation
        let isPunctuation = [".", ",", "?", "!", ":", ";"].contains(text)
        let textWithSpace = isPunctuation ? text : " " + text
        
        print("🎯 ATTEMPTING TO SEND: '\(textWithSpace)' to \(selectedTargetApp.displayName)")
        
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textWithSpace, forType: .string)
        print("📋 Clipboard set successfully")
        
        // ENHANCED: Multiple activation methods
        let bundleId = selectedTargetApp.bundleId
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        print("🔍 Found \(runningApps.count) instances of \(selectedTargetApp.displayName)")
        
        if let app = runningApps.first {
            print("📱 App is running, trying multiple activation methods...")
            
            // Method 1: Try standard activation
            let success1 = app.activate(options: [.activateIgnoringOtherApps])
            print("✅ Standard activation result: \(success1)")
            
            // Method 2: Try with all windows
            let success2 = app.activate(options: [.activateAllWindows])
            print("✅ All windows activation result: \(success2)")
            
            // Method 3: Force using NSWorkspace
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleId,
                                               options: [.default],
                                               additionalEventParamDescriptor: nil,
                                               launchIdentifier: nil)
            print("✅ NSWorkspace activation attempted")
            
            // Wait longer and try paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📝 Sending Cmd+V...")
                self.simulatePaste()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateStatus(.success)
                    print("✅ Paste operation completed")
                }
            }
            
        } else {
            print("🚀 App not running, launching...")
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                do {
                    try NSWorkspace.shared.launchApplication(at: appURL, options: [.default], configuration: [:])
                    print("✅ App launched")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("📝 Sending Cmd+V to new app...")
                        self.simulatePaste()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.updateStatus(.success)
                        }
                    }
                } catch {
                    print("❌ Failed to launch app: \(error)")
                    updateStatus(.error)
                }
            }
        }
    }
    
    func simulatePaste() {
        // Create Cmd+V key events
        let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        
        cmdVDown?.flags = .maskCommand
        cmdVUp?.flags = .maskCommand
        
        // Send the paste command
        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
    }
    
    // ENHANCED STATUS with new sending state
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
