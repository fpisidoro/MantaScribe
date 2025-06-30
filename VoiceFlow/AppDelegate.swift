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
        
        print("🎤 VoiceFlow Ready!")
        print("Press Space bar to toggle dictation")
        print("Target: \(selectedTargetApp.displayName)")
    }
    
    func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "🎤"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Space)", action: #selector(toggleDictation), keyEquivalent: " "))
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
        menu.addItem(NSMenuItem(title: "Test Current Target", action: #selector(testCurrentTarget), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About VoiceFlow", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusBarItem.menu = menu
        
        // Setup global hotkey monitoring
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 { // Space bar
                self.toggleDictation()
            }
        }
        
        // Local event monitor (when app has focus)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 { // Space bar
                self.toggleDictation()
                return nil // Consume the event
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
    
    @objc func testCurrentTarget() {
        // Force launch TextEdit first to ensure it's running
        launchApp(selectedTargetApp)
        
        // Wait a moment for launch, then test
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.sendTextToApp("Test message from VoiceFlow - \(Date())")
        }
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "VoiceFlow"
        alert.informativeText = "Background dictation for professionals.\n\nTarget: \(selectedTargetApp.displayName)\nPress Space to dictate while focused on other apps."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Check if speech recognizer is available
        guard let speechRecognizer = speechRecognizer else {
            print("❌ Speech recognizer not available for locale en-US")
            return
        }
        
        // Set delegate to monitor availability changes
        speechRecognizer.delegate = self
        
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Speech recognition authorized")
                    self?.checkDictationSetup()
                case .denied:
                    print("❌ Speech recognition authorization denied")
                    self?.showSpeechPermissionAlert()
                case .restricted:
                    print("⚠️ Speech recognition restricted on this device")
                case .notDetermined:
                    print("⏳ Speech recognition not yet authorized")
                @unknown default:
                    print("❓ Unknown authorization status")
                }
            }
        }
    }
    
    func checkDictationSetup() {
        print("ℹ️ For best results, ensure:")
        print("   1. System Preferences > Keyboard > Dictation is ON")
        print("   2. Language is set to English (US)")
        print("   3. Enhanced Dictation is enabled for offline use")
    }
    
    func showSpeechPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Speech Recognition Permission Required"
        alert.informativeText = """
        VoiceFlow needs permission to use speech recognition.
        
        Please grant permission in:
        System Preferences > Security & Privacy > Privacy > Speech Recognition
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
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
            showDictationSetupAlert()
            return
        }
        
        print("🎙️ Starting dictation to \(selectedTargetApp.displayName)...")
        
        // Audio feedback
        playSound("Glass")
        updateStatus(.listening)
        
        // Cancel previous task if running
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Create recognition request with on-device processing
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Unable to create recognition request")
            showError("Unable to create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        // Try to use on-device recognition to avoid server issues
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Remove any existing tap first
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started successfully")
        } catch {
            print("❌ Audio engine failed to start: \(error)")
            showMicrophoneAlert()
            return
        }
        
        // Start recognition task with improved error handling
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                let confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
                
                if !result.isFinal {
                    // Update buffer and reset timer
                    self.currentBuffer = transcribedText
                    self.bufferTimer?.invalidate()
                    
                    // Show processing status
                    DispatchQueue.main.async {
                        self.updateStatus(.processing)
                    }
                    
                    // Adaptive timeout based on confidence and sentence structure
                    let timeout = self.calculateBufferTimeout(text: transcribedText, confidence: confidence)
                    
                    self.bufferTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                        DispatchQueue.main.async {
                            self.flushBuffer()
                        }
                    }
                } else {
                    // Final result - flush immediately
                    DispatchQueue.main.async {
                        self.currentBuffer = transcribedText
                        self.flushBuffer()
                    }
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                let errorCode = nsError.code
                let errorDomain = nsError.domain
                
                print("❌ Recognition error: \(error.localizedDescription)")
                print("   Domain: \(errorDomain), Code: \(errorCode)")
                
                DispatchQueue.main.async {
                    self.handleRecognitionError(errorCode, domain: errorDomain)
                }
            }
        }
        
        isRecording = true
    }
    
    func handleRecognitionError(_ errorCode: Int, domain: String) {
        if domain == "kAFAssistantErrorDomain" {
            switch errorCode {
            case 1101:
                // Dictation service setup issue
                showDictationSetupAlert()
            case 1107:
                // No speech detected - this is normal, just continue
                print("ℹ️ No speech detected, continuing...")
                return
            case 203:
                // Timeout or rate limiting
                showError("Speech recognition timeout. Please try again.")
            case 216:
                // Locale/language issue
                showError("Language setup issue. Check dictation language settings.")
            default:
                showError("Speech recognition error (\(errorCode))")
            }
        } else {
            showError("Recognition failed")
        }
        
        stopDictation()
    }
    
    func showDictationSetupAlert() {
        let alert = NSAlert()
        alert.messageText = "Dictation Setup Required"
        alert.informativeText = """
        VoiceFlow requires dictation to be properly configured:
        
        1. Open System Preferences > Keyboard
        2. Turn ON "Enable Dictation"
        3. Set language to "English (United States)"
        4. Enable "Use Enhanced Dictation" for offline use
        5. Restart VoiceFlow after making changes
        
        This ensures reliable speech recognition.
        """
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!)
        }
    }
    
    func showMicrophoneAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = """
        VoiceFlow needs microphone access for speech recognition.
        
        Please grant permission in:
        System Preferences > Security & Privacy > Privacy > Microphone
        
        Add VoiceFlow to the list and check the box.
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
    
    func calculateBufferTimeout(text: String, confidence: Float) -> TimeInterval {
        // Base timeout
        var timeout = 2.0
        
        // Extend timeout for sentence endings
        if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
            timeout = 1.0 // Shorter for completed sentences
        }
        
        // Adjust for confidence
        if confidence < 0.5 {
            timeout += 0.5 // Wait longer for uncertain text
        }
        
        return timeout
    }
    
    func flushBuffer() {
        guard !currentBuffer.isEmpty else { return }
        
        print("📝 Sending to \(selectedTargetApp.displayName): \(currentBuffer)")
        
        // Audio feedback and visual update
        playSound("Purr")
        updateStatus(.success)
        
        // Send to selected app
        sendTextToApp(currentBuffer)
        
        // Clear buffer
        currentBuffer = ""
        bufferTimer?.invalidate()
        
        // Reset status after brief success indication
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if !self.isRecording {
                self.updateStatus(.ready)
            }
        }
    }
    
    func stopDictation() {
        print("⏹️ Stopping dictation")
        
        // Stop audio engine safely
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
        
        // Flush any remaining buffer
        if !currentBuffer.isEmpty {
            flushBuffer()
        }
    }
    
    enum Status {
        case ready, listening, processing, success, error
    }
    
    func updateStatus(_ status: Status) {
        let (icon, title) = statusInfo(for: status)
        statusBarItem.button?.title = icon
        statusBarItem.menu?.items[0].title = title
    }
    
    func statusInfo(for status: Status) -> (String, String) {
        switch status {
        case .ready:
            return ("🎤", "Toggle Dictation (Space)")
        case .listening:
            return ("🔴", "Stop Dictation (Space)")
        case .processing:
            return ("⚡", "Processing...")
        case .success:
            return ("✅", "Sent!")
        case .error:
            return ("❌", "Error - Try Again")
        }
    }
    
    func playSound(_ soundName: String) {
        if let sound = NSSound(named: soundName) {
            sound.volume = 0.3
            sound.play()
        }
    }
    
    func showError(_ message: String) {
        updateStatus(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateStatus(.ready)
        }
    }
    
    func sendTextToApp(_ text: String) {
        // Check if target app is running, launch if needed
        if !isAppRunning(selectedTargetApp) {
            launchApp(selectedTargetApp)
            // Give app time to launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.executeAppleScript(text)
            }
        } else {
            executeAppleScript(text)
        }
    }
    
    func isAppRunning(_ app: TargetApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == app.bundleId }
    }
    
    func launchApp(_ app: TargetApp) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            do {
                try NSWorkspace.shared.launchApplication(at: appURL,
                                                       options: [.withoutActivation],
                                                       configuration: [:])
                print("📱 Launched \(app.displayName)")
            } catch {
                print("❌ Failed to launch \(app.displayName): \(error)")
            }
        }
    }
    
    func executeAppleScript(_ text: String) {
        let script = createAppleScriptForApp(selectedTargetApp, text: text)
        
        print("🔧 Executing AppleScript for \(selectedTargetApp.displayName)")
        print("📝 Script content preview: tell application \"\(selectedTargetApp.rawValue)\"...")
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if let error = error {
                let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? 0
                print("❌ AppleScript error \(errorCode): \(error)")
                handleAppleScriptError(errorCode, error: error)
            } else {
                print("✅ Text successfully sent to \(selectedTargetApp.displayName)")
                print("📊 AppleScript result: \(result.stringValue ?? "no result")")
            }
        } else {
            print("❌ Failed to create AppleScript object")
        }
    }
    
    func handleAppleScriptError(_ errorCode: Int, error: NSDictionary) {
        switch errorCode {
        case -1743:
            // Not authorized to send Apple events
            showAutomationPermissionAlert()
        case -10003:
            // Access not allowed - specific app permission needed
            showAppControlPermissionAlert()
        case -1719:
            // Assistive access required
            showAccessibilityAlert()
        case -10810:
            // Application not running
            print("📱 App not running, attempting to launch...")
            launchApp(selectedTargetApp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.executeAppleScript(self.currentBuffer)
            }
        default:
            print("❌ AppleScript error \(errorCode): \(error)")
            showError("Script error: \(errorCode)")
        }
    }
    
    func showAutomationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Automation Permission Required"
        alert.informativeText = """
        VoiceFlow needs permission to send text to \(selectedTargetApp.displayName).
        
        Steps to fix:
        1. Open System Preferences > Security & Privacy
        2. Click Privacy tab > Automation
        3. Find VoiceFlow in the list
        4. Check the box next to \(selectedTargetApp.displayName)
        
        If VoiceFlow doesn't appear, try dictating again first.
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
    
    func showAppControlPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "App Control Permission Required"
        alert.informativeText = """
        VoiceFlow needs permission to control \(selectedTargetApp.displayName).
        
        This error (-10003) means automation permission is required.
        
        Steps to fix:
        1. Open System Preferences > Security & Privacy
        2. Go to Privacy tab > Automation
        3. Look for VoiceFlow and check \(selectedTargetApp.displayName)
        4. If VoiceFlow isn't listed, try dictating once more to trigger the permission request
        
        You may also need to restart \(selectedTargetApp.displayName) after granting permission.
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Restart \(selectedTargetApp.displayName)")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        } else if response == .alertSecondButtonReturn {
            restartTargetApp()
        }
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        VoiceFlow needs Accessibility permissions to control other applications.
        
        1. Open System Preferences > Security & Privacy
        2. Go to Privacy tab > Accessibility
        3. Add VoiceFlow to the list and check the box
        
        Then try dictating again.
        """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    func restartTargetApp() {
        // Quit the target app
        let quitScript = """
        tell application "\(selectedTargetApp.rawValue)"
            quit
        end tell
        """
        
        if let scriptObject = NSAppleScript(source: quitScript) {
            var error: NSDictionary?
            scriptObject.executeAndReturnError(&error)
        }
        
        // Wait a moment then relaunch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.launchApp(self.selectedTargetApp)
        }
    }
    
    func createAppleScriptForApp(_ app: TargetApp, text: String) -> String {
        // Escape quotes and backslashes in text
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        switch app {
        case .textEdit:
            return """
            tell application "TextEdit"
                try
                    if not (exists document 1) then
                        make new document
                    end if
                    tell front document
                        set current_text to get text
                        if current_text is not "" and not (current_text ends with " ") and not (current_text ends with "\\n") then
                            set text to current_text & " " & "\(escapedText)"
                        else
                            set text to current_text & "\(escapedText)"
                        end if
                    end tell
                on error errMsg number errNum
                    error "TextEdit control failed: " & errMsg number errNum
                end try
            end tell
            """
            
        case .pages:
            return """
            tell application "Pages"
                try
                    if not (exists document 1) then
                        make new document
                    end if
                    tell front document
                        set current_text to body text
                        if current_text is not "" and not (current_text ends with " ") then
                            set body text to current_text & " " & "\(escapedText)"
                        else
                            set body text to current_text & "\(escapedText)"
                        end if
                    end tell
                on error errMsg number errNum
                    error "Pages control failed: " & errMsg number errNum
                end try
            end tell
            """
            
        case .notes:
            return """
            tell application "Notes"
                try
                    if not (exists note 1) then
                        make new note
                    end if
                    tell note 1
                        set current_body to body
                        if current_body is not "" and not (current_body ends with " ") then
                            set body to current_body & " " & "\(escapedText)"
                        else
                            set body to current_body & "\(escapedText)"
                        end if
                    end tell
                on error errMsg number errNum
                    error "Notes control failed: " & errMsg number errNum
                end try
            end tell
            """
            
        case .word:
            return """
            tell application "Microsoft Word"
                try
                    if not (exists document 1) then
                        make new document
                    end if
                    tell active document
                        set current_content to content of text object
                        if current_content is not "" and not (current_content ends with " ") then
                            set content of text object to current_content & " " & "\(escapedText)"
                        else
                            set content of text object to current_content & "\(escapedText)"
                        end if
                    end tell
                on error errMsg number errNum
                    error "Word control failed: " & errMsg number errNum
                end try
            end tell
            """
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension AppDelegate: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if available {
                print("✅ Speech recognizer became available")
            } else {
                print("❌ Speech recognizer became unavailable")
                if self.isRecording {
                    self.stopDictation()
                }
            }
        }
    }
}

// Make sure the app doesn't terminate when all windows are closed
extension AppDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
