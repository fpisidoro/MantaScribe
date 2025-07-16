import Foundation
import Speech
import AVFoundation

/// Clean dictation engine with separated mode logic and future smart feature integration points
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case listening
        case processing
        case error
    }
    
    enum DictationMode {
        case toggle        // Continuous listening with pause detection
        case pushToTalk    // Accumulate until stop
    }
    
    enum ProcessingMode {
        case fast          // Current: minimal processing for speed
        case smart         // Future: full smart features
    }
    
    enum DictationError: Error {
        case speechRecognizerUnavailable
        case audioEngineFailure(Error)
        case recognitionRequestCreationFailed
        case recognitionTaskFailed(Error)
    }
    
    // MARK: - Delegate Protocol
    
    weak var delegate: DictationEngineDelegate?
    
    // MARK: - Properties
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var smartTextCoordinator: SmartTextCoordinator?
    
    // Mode Management
    private var dictationMode: DictationMode = .toggle
    private var processingMode: ProcessingMode = .fast
    
    // Core Buffer Management
    private var bufferTimer: Timer?
    private var currentBuffer = ""
    private var hasProcessedBuffer = false
    private var isCurrentlyProcessing = false
    
    // Incremental Processing (Toggle Mode)
    private var lastProcessedText = ""
    private var lastProcessedTimestamp = Date.distantPast
    private var consecutiveSkips = 0
    
    // Push-to-Talk Final Result Handling
    private var isWaitingForFinalResult = false
    
    // State
    private(set) var state: DictationState = .idle
    private(set) var isRecording = false
    
    // Configuration
    private let enableOnDeviceRecognition = true
    private let bufferSize: AVAudioFrameCount = 1024
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSpeechRecognizer()
    }
    
    // MARK: - Mode Management
    
    /// Set dictation mode (how we dictate: toggle vs push-to-talk)
    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
        print("🎤 DictationEngine: Mode set to \(mode)")
    }
    
    /// Set processing mode (what processing we do: fast vs smart)
    func updatePerformanceMode(_ smartModeEnabled: Bool) {
        processingMode = smartModeEnabled ? .smart : .fast
        print("🎤 DictationEngine: Processing mode set to \(processingMode)")
    }
    
    // MARK: - Public Interface
    
    /// Start dictation with current mode settings
    func startDictation() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            let error = DictationError.speechRecognizerUnavailable
            delegate?.dictationEngine(self, didEncounterError: error)
            return
        }
        
        print("🎙️ DictationEngine: Starting \(dictationMode) dictation with \(processingMode) processing")
        
        setState(.listening)
        resetBuffer()
        setupRecognitionRequest()
        setupAudioEngine()
        startAudioEngine()
        startRecognitionTask()
        
        isRecording = true
        delegate?.dictationEngineDidStart(self)
    }
    
    /// Stop dictation with mode-specific processing
    func stopDictation() {
        print("⏹️ DictationEngine: Stopping \(dictationMode) dictation")
        
        // Mode-specific stop behavior
        switch dictationMode {
        case .toggle:
            handleToggleStop()
        case .pushToTalk:
            handlePushToTalkStop()
        }
        
        cleanupRecognition()
        setState(.idle)
        
        isRecording = false
        delegate?.dictationEngineDidStop(self)
    }
    
    func setSmartTextCoordinator(_ coordinator: SmartTextCoordinator) {
        self.smartTextCoordinator = coordinator
    }

    /// Check if dictation is currently active
    var isDictating: Bool {
        return isRecording
    }
    
    /// Get current dictation state
    var currentState: DictationState {
        return state
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        print("🎤 DictationEngine: Speech recognizer initialized")
    }
    
    private func resetBuffer() {
        currentBuffer = ""
        hasProcessedBuffer = false
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        lastProcessedText = ""
        bufferTimer?.invalidate()
    }
    
    private func setupRecognitionRequest() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            let error = DictationError.recognitionRequestCreationFailed
            delegate?.dictationEngine(self, didEncounterError: error)
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Enable on-device recognition if available
        if #available(macOS 13.0, *), enableOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
            print("🎯 DictationEngine: On-device recognition enabled")
        }
        
        // Apply smart features only in smart processing mode
        if processingMode == .smart {
            applySmartFeatures(to: recognitionRequest)
        } else {
            print("⚡ DictationEngine: Fast processing - skipping smart features")
        }
    }
    
    private func applySmartFeatures(to request: SFSpeechAudioBufferRecognitionRequest) {
        // Apply contextual strings only if enabled in SmartTextCoordinator
        let shouldApplyContextualStrings = smartTextCoordinator?.enableContextualStrings ?? true
        
        if shouldApplyContextualStrings {
            let contextualStrings = VocabularyManager.shared.getContextualStrings()
            if !contextualStrings.isEmpty {
                request.contextualStrings = contextualStrings
                print("🎯 DictationEngine: Applied \(contextualStrings.count) contextual strings")
            } else {
                print("⚠️ DictationEngine: No contextual strings available!")
            }
        } else {
            print("⚡ DictationEngine: Contextual strings DISABLED for performance testing")
        }
    }
    
    private func setupAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        print("🎤 DictationEngine: Audio engine configured")
    }
    
    private func startAudioEngine() {
        do {
            try audioEngine.start()
            print("🎤 DictationEngine: Audio engine started")
        } catch {
            print("❌ DictationEngine: Audio engine failed: \(error)")
            setState(.error)
            let dictationError = DictationError.audioEngineFailure(error)
            delegate?.dictationEngine(self, didEncounterError: dictationError)
        }
    }
    
    private func startRecognitionTask() {
        guard let speechRecognizer = speechRecognizer,
              let recognitionRequest = recognitionRequest else {
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.handleRecognitionResult(result)
            }
            
            if let error = error {
                print("❌ DictationEngine: Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    let dictationError = DictationError.recognitionTaskFailed(error)
                    self.delegate?.dictationEngine(self, didEncounterError: dictationError)
                    self.stopDictation()
                }
            }
        }
        
        print("🎤 DictationEngine: Recognition task started")
    }
    
    // MARK: - Recognition Result Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        
        // Always update buffer for partial results (future UI features)
        currentBuffer = text
        
        if result.isFinal {
            handleFinalResult(text: text)
        } else {
            handlePartialResult(text: text)
        }
    }
    
    private func handleFinalResult(text: String) {
        DispatchQueue.main.async {
            self.bufferTimer?.invalidate()
            
            switch self.dictationMode {
            case .toggle:
                self.handleToggleFinalResult(text: text)
            case .pushToTalk:
                self.handlePushToTalkFinalResult(text: text)
            }
        }
    }
    
    private func handlePartialResult(text: String) {
        switch dictationMode {
        case .toggle:
            handleTogglePartialResult(text: text)
        case .pushToTalk:
            handlePushToTalkPartialResult(text: text)
        }
    }
    
    // MARK: - Toggle Mode Logic (Incremental Processing)
    
    private func handleToggleFinalResult(text: String) {
        // In toggle mode, we primarily use partial results with timers
        // Final results are backup in case partial results stop
        print("🔄 Toggle final result (backup): '\(text)'")
        if !hasProcessedBuffer && !text.isEmpty {
            processIncrementalText(text)
        }
    }
    
    private func handleTogglePartialResult(text: String) {
        if !hasProcessedBuffer && !text.isEmpty {
            currentBuffer = text
            bufferTimer?.invalidate()
            
            DispatchQueue.main.async {
                self.setState(.processing)
            }
            
            // Fast timeout for incremental processing
            let timeout = getProcessingTimeout(for: text)
            
            bufferTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if !self.hasProcessedBuffer && self.isRecording && !self.currentBuffer.isEmpty {
                        self.processIncrementalText(self.currentBuffer)
                    }
                }
            }
        }
    }
    
    private func handleToggleStop() {
        // Toggle mode: Process any remaining text incrementally
        if !hasProcessedBuffer && !currentBuffer.isEmpty {
            print("🔄 Toggle stop: Processing remaining buffer incrementally: '\(currentBuffer)'")
            processIncrementalText(currentBuffer)
        }
    }
    
    // EXISTING METHOD: Only modify the parts shown below
    private func processIncrementalText(_ newText: String) {
        guard !isCurrentlyProcessing else {
            print("🚫 Skipping incremental processing - already processing")
            return
        }
        
        isCurrentlyProcessing = true
        hasProcessedBuffer = true
        bufferTimer?.invalidate()
        
        let textToSend = extractIncrementalText(newText)
        
        if !textToSend.isEmpty {
            print("📝 Incremental processing (toggle): '\(textToSend)'")
            lastProcessedText = newText
            lastProcessedTimestamp = Date()  // NEW: Track successful processing time
            consecutiveSkips = 0  // NEW: Reset skip counter on success
            
            // Send incremental text to delegate
            delegate?.dictationEngine(self, didProcessText: textToSend)
        } else {
            print("🔄 No new text to send (duplicate or subset)")
            
            // NEW: Escape valve - prevent infinite stuck states
            consecutiveSkips += 1
            if consecutiveSkips >= 3 {
                print("🚨 Escape valve triggered after \(consecutiveSkips) consecutive skips")
                print("🚨 Forcing reset to prevent stuck state")
                lastProcessedText = ""
                lastProcessedTimestamp = Date.distantPast
                consecutiveSkips = 0
                // Don't process current text, just reset for next attempt
            }
        }
        
        isCurrentlyProcessing = false
        
        // Quick reset for next incremental update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.hasProcessedBuffer = false
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    // MARK: - REFINED: Smart Sentence Boundary Detection + Improved Mid-Sentence Correction Filtering
    
    // ENHANCED METHOD: Add temporal logic to existing word comparison
     private func extractIncrementalText(_ newText: String) -> String {
         let now = Date()
         
         // Handle incremental text extraction with smart sentence boundary detection
         if lastProcessedText.isEmpty {
             // First text, send everything
             lastProcessedTimestamp = now
             return newText
         }
         
         // KEEP ALL EXISTING LOGIC - Split into words for smart comparison
         let previousWords = lastProcessedText.split(separator: " ")
         let currentWords = newText.split(separator: " ")
         
         print("🔍 Word extraction - Previous: \(previousWords.count) words, Current: \(currentWords.count) words")
         
         // Find longest common word sequence from the start
         var commonWordCount = 0
         let minWordCount = min(previousWords.count, currentWords.count)
         
         for i in 0..<minWordCount {
             if previousWords[i] == currentWords[i] {
                 commonWordCount += 1
             } else {
                 print("🔍 Word difference at position \(i): '\(previousWords[i])' vs '\(currentWords[i])'")
                 break
             }
         }
         
         print("🔍 Common words from start: \(commonWordCount)")
         
         // KEEP EXISTING: Check for mid-sentence corrections during pauses
         if isLikelyPauseCorrection(previousWords, currentWords, commonWordCount) {
             print("📝 Mid-sentence correction detected - skipping to avoid partial phrases")
             return ""
         }
         
         // KEEP EXISTING: Better sentence boundary detection
         if commonWordCount == 0 && previousWords.count > 0 {
             // User started completely new sentence - send the entire new sentence
             print("📝 New sentence detected - sending complete new sentence: '\(newText)'")
             lastProcessedTimestamp = now
             return newText
         } else if currentWords.count > commonWordCount {
             // User added to existing sentence - send only new words
             let newWords = Array(currentWords[commonWordCount...])
             let result = newWords.joined(separator: " ")
             print("📝 Sending new words: '\(result)'")
             lastProcessedTimestamp = now
             return result
         } else if currentWords.count == previousWords.count && commonWordCount < currentWords.count {
             // Same number of words but some changed in the middle (revision)
             // Don't send anything to avoid duplicates
             print("📝 Word revision detected - skipping to avoid duplicate")
             return ""
         } else if currentWords.count < previousWords.count {
             // Current text is shorter - likely a recognition correction
             // Don't send anything to avoid duplicates
             print("📝 Text got shorter - likely recognition correction, skipping")
             return ""
         } else {
             // ENHANCED: Same length, all words match - check if this is a processing artifact
             let timeSinceLastProcessed = now.timeIntervalSince(lastProcessedTimestamp)
             
             // Most Apple recognition artifacts happen within 3-5 seconds
             // Only allow "duplicates" if there's been a significant pause (5+ seconds)
             if timeSinceLastProcessed < 5.0 {
                 // Likely Apple re-processing the same audio - skip it
                 print("📝 True duplicate detected (within \(String(format: "%.2f", timeSinceLastProcessed))s) - skipping")
                 return ""
             } else {
                 // Very long gap + same words = probably intentional repeat by user
                 print("📝 Intentional duplicate after \(String(format: "%.2f", timeSinceLastProcessed))s gap - allowing")
                 lastProcessedTimestamp = now
                 return newText
             }
         }
     }
    
    /// REFINED: Detect mid-sentence corrections with improved punctuation handling
    private func isLikelyPauseCorrection(_ previousWords: [String.SubSequence], _ currentWords: [String.SubSequence], _ commonWordCount: Int) -> Bool {
        // Only flag if we have a change in the middle AND it's not just punctuation
        guard commonWordCount > 0 && commonWordCount < previousWords.count else {
            return false
        }
        
        // Check what actually changed at the difference point
        if commonWordCount < currentWords.count {
            let previousWord = String(previousWords[commonWordCount])
            let currentWord = String(currentWords[commonWordCount])
            
            // If it's just punctuation/symbols being added, allow it
            if currentWord.hasPrefix(previousWord) &&
               currentWord.count <= previousWord.count + 3 &&  // Allow up to 3 chars of punctuation
               isPunctuationAddition(from: previousWord, to: currentWord) {
                print("📝 Punctuation addition detected: '\(previousWord)' → '\(currentWord)' - allowing")
                return false
            }
            
            // If it's a real word substitution, flag it
            if previousWord != currentWord && !currentWord.hasPrefix(previousWord) {
                print("📝 Real word substitution: '\(previousWord)' → '\(currentWord)' - flagging as correction")
                return true
            }
        }
        
        // For changes in middle with word additions (not substitutions)
        if currentWords.count > previousWords.count {
            print("📝 Words added to middle of existing sentence - likely pause correction")
            return true
        }
        
        return false
    }
    
    /// Check if the change is just punctuation/symbol addition
    private func isPunctuationAddition(from old: String, to new: String) -> Bool {
        guard new.hasPrefix(old) else { return false }
        let addition = String(new.dropFirst(old.count))
        
        // Allow any non-alphanumeric addition (punctuation, spaces, symbols)
        return !addition.isEmpty && addition.allSatisfy { !$0.isLetter && !$0.isNumber }
    }
    
    // OPTIONAL: Add state reset method for manual recovery
      func resetDuplicateDetectionState() {
          print("🔄 Manual reset of duplicate detection state")
          lastProcessedText = ""
          lastProcessedTimestamp = Date.distantPast
          consecutiveSkips = 0
      }
    
    // MARK: - Push-to-Talk Mode Logic (Final Results Only)
    
    private func handlePushToTalkFinalResult(text: String) {
        if isWaitingForFinalResult && !text.isEmpty {
            print("📱 Push-to-talk final result (Apple finalized): '\(text)'")
            isWaitingForFinalResult = false
            
            // Process Apple's complete final result and finalize session
            finalizePushToTalkSession(with: text)
        } else if !isWaitingForFinalResult {
            // Still accumulating during active push-to-talk
            print("📱 Push-to-talk final result accumulated: '\(text)'")
        }
    }
    
    // New method to properly finalize push-to-talk sessions
    private func finalizePushToTalkSession(with text: String) {
        if !text.isEmpty {
            processCompleteText(text)
        }
        
        // Now do the cleanup that was deferred from stopDictation()
        cleanupRecognition()
        setState(.idle)
        delegate?.dictationEngineDidStop(self)
    }
    
    private func handlePushToTalkPartialResult(text: String) {
        // Push-to-talk: Just accumulate, no processing until key release
        currentBuffer = text
        print("📱 Push-to-talk accumulating: '\(text)'")
    }
    
    private func handlePushToTalkStop() {
        // Push-to-talk: Check if user is still speaking before stopping
        if !currentBuffer.isEmpty {
            print("📝 Push-to-talk stop: Checking for ongoing speech...")
            
            // Get the most recent transcription segments to check speech activity
            let wasRecentlySpeaking = checkRecentSpeechActivity()
            
            if wasRecentlySpeaking {
                print("📝 Push-to-talk: Recent speech detected - delaying stop for 800ms")
                // User was recently speaking, delay the stop to catch tail words
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.finalizeStopPushToTalk()
                }
            } else {
                print("📝 Push-to-talk: No recent speech - stopping immediately")
                finalizeStopPushToTalk()
            }
        } else {
            print("📝 Push-to-talk stop: No buffer to process")
            finalizePushToTalkSession(with: "")
        }
    }
    
    private func checkRecentSpeechActivity() -> Bool {
        // Check if there's been recent speech activity by looking at buffer changes
        // This is a simple heuristic - if the buffer is growing, user is likely still speaking
        let bufferLength = currentBuffer.count
        
        if bufferLength > 0 {
            // If we have substantial content, assume there might be tail words
            print("📝 Buffer analysis: \(bufferLength) characters - assuming potential tail speech")
            return bufferLength > 10  // Threshold for "substantial content"
        }
        
        return false
    }
    
    private func finalizeStopPushToTalk() {
        print("📝 Push-to-talk: Finalizing stop sequence")
        isWaitingForFinalResult = true
        
        // Signal end of audio input
        recognitionRequest?.endAudio()
        
        // Wait for Apple's final result
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.isWaitingForFinalResult && !self.currentBuffer.isEmpty {
                print("📝 Push-to-talk: Final result timeout - processing current buffer")
                self.isWaitingForFinalResult = false
                self.finalizePushToTalkSession(with: self.currentBuffer)
            }
        }
    }
    
    private func processCompleteText(_ text: String) {
        guard !isCurrentlyProcessing else {
            print("🚫 Skipping complete text processing - already processing")
            return
        }
        
        isCurrentlyProcessing = true
        
        let textToProcess = text.trimmingCharacters(in: .whitespaces)
        print("📝 Complete processing (push-to-talk): '\(textToProcess)'")
        
        hasProcessedBuffer = true
        currentBuffer = ""
        bufferTimer?.invalidate()
        
        // Send complete text to delegate
        delegate?.dictationEngine(self, didProcessText: textToProcess)
        
        isCurrentlyProcessing = false
        
        // Reset for next session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasProcessedBuffer = false
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    // MARK: - Timing Configuration
    
    private enum TimingType {
        case partial
        case final
    }
    
    private func getProcessingTimeout(for text: String) -> TimeInterval {
        let hasPunctuation = text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
        
        switch processingMode {
        case .fast:
            return hasPunctuation ? 0.3 : 0.6
        case .smart:
            // Future: confidence-based timing
            return hasPunctuation ? 0.5 : 1.0
        }
    }
    
    private func getProcessingDelay(_ type: TimingType) -> TimeInterval {
        switch processingMode {
        case .fast:
            return type == .final ? 0.1 : 0.2
        case .smart:
            return type == .final ? 0.3 : 0.5
        }
    }
    
    private func getResetDelay() -> TimeInterval {
        switch processingMode {
        case .fast:
            return 0.5
        case .smart:
            return 1.0
        }
    }
    
    // MARK: - State Management
    
    private func setState(_ newState: DictationState) {
        state = newState
        print("🎤 DictationEngine (\(dictationMode)/\(processingMode)): State → \(newState)")
    }
    
    private func cleanupRecognition() {
        currentBuffer = ""
        hasProcessedBuffer = true
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        lastProcessedText = ""
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        bufferTimer?.invalidate()
        
        hasProcessedBuffer = false
        print("🎤 DictationEngine: Recognition cleaned up")
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension DictationEngine: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isRecording {
                print("⚠️ DictationEngine: Speech recognizer became unavailable")
                self.stopDictation()
            }
        }
    }
}

// MARK: - Delegate Protocol

protocol DictationEngineDelegate: AnyObject {
    /// Called when the dictation engine has processed text and is ready to send it
    func dictationEngine(_ engine: DictationEngine, didProcessText text: String)
    
    /// Called when dictation starts
    func dictationEngineDidStart(_ engine: DictationEngine)
    
    /// Called when dictation stops
    func dictationEngineDidStop(_ engine: DictationEngine)
    
    /// Called when an error occurs
    func dictationEngine(_ engine: DictationEngine, didEncounterError error: Error)
}
