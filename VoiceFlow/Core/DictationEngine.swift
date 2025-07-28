import Foundation
import Speech
import AVFoundation

/// Clean dictation engine with Smart Completion Detection for toggle mode
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case listening
        case processing
        case waitingForCompletion  // NEW: Smart completion detection state
        case error
    }
    
    enum DictationMode {
        case toggle        // Continuous listening with smart completion detection
        case pushToTalk    // Accumulate until stop
    }
    
    enum ProcessingMode {
        case fast          // Current: minimal processing for speed
        case smart         // Smart completion detection + full features
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
    private var processingMode: ProcessingMode = .smart
    
    // SMART COMPLETION DETECTION - Core Properties
    private var completionTimer: Timer?
    private var bufferedTranscription: String = ""
    private var lastBufferUpdate = Date()
    private var isWaitingForCompletion = false
    private var consecutivePartialResults = 0
    private var lastProcessedContent = ""  // NEW: Track actual processed content
    
    // SMART COMPLETION DETECTION - Configuration
    private let maxWaitTime: TimeInterval = 4.0        // Maximum wait before timeout
    private let confidenceThreshold: Float = 0.85      // High confidence threshold
    private let naturalPauseTime: TimeInterval = 1.5   // Natural pause detection
    private let medicalPauseTime: TimeInterval = 1.2   // Medical phrase completion time
    
    // Legacy Properties (for push-to-talk and fallback)
    private var currentBuffer = ""
    private var hasProcessedBuffer = false
    private var isCurrentlyProcessing = false
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
        // Smart Completion Detection reset
        bufferedTranscription = ""
        isWaitingForCompletion = false
        consecutivePartialResults = 0
        completionTimer?.invalidate()
        lastBufferUpdate = Date()
        
        // Legacy reset (for push-to-talk)
        currentBuffer = ""
        hasProcessedBuffer = false
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        
        // NEW: Reset fast mode tracking
        lastFastModeText = ""
        lastProcessedContent = ""
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
        
        // Calculate average confidence from segments
        let confidence: Float
        if !result.bestTranscription.segments.isEmpty {
            let totalConfidence = result.bestTranscription.segments.reduce(0.0) { $0 + $1.confidence }
            confidence = totalConfidence / Float(result.bestTranscription.segments.count)
        } else {
            confidence = 0.5 // Default moderate confidence
        }
        
        // Always update legacy buffer for push-to-talk compatibility
        currentBuffer = text
        
        if result.isFinal {
            handleFinalResult(text: text, confidence: confidence)
        } else {
            handlePartialResult(text: text, confidence: confidence)
        }
    }
    
    private func handleFinalResult(text: String, confidence: Float) {
        DispatchQueue.main.async {
            switch self.dictationMode {
            case .toggle:
                self.handleToggleFinalResult(text: text, confidence: confidence)
            case .pushToTalk:
                self.handlePushToTalkFinalResult(text: text)
            }
        }
    }
    
    private func handlePartialResult(text: String, confidence: Float) {
        switch dictationMode {
        case .toggle:
            if processingMode == .smart {
                handleSmartTogglePartialResult(text: text, confidence: confidence)
            } else {
                handleFastTogglePartialResult(text: text)
            }
        case .pushToTalk:
            handlePushToTalkPartialResult(text: text)
        }
    }
    
    // MARK: - SMART COMPLETION DETECTION - Toggle Mode Logic
    
    private func handleSmartTogglePartialResult(text: String, confidence: Float) {
        // Update buffer and tracking
        bufferedTranscription = text
        lastBufferUpdate = Date()
        consecutivePartialResults += 1
        
        // Log activity for debugging
        print("🧠 Smart buffering (\(consecutivePartialResults)): '\(text)' (confidence: \(String(format: "%.2f", confidence)))")
        
        // Check for completion signals
        if shouldProcessNow(text: text, confidence: confidence) {
            processBufferedText()
        } else {
            // Not ready yet - update state and continue buffering
            if !isWaitingForCompletion {
                setState(.waitingForCompletion)
                startCompletionTimer()
            }
        }
    }
    
    private func handleToggleFinalResult(text: String, confidence: Float) {
        // Final result in toggle mode - process immediately if we have content
        if !text.isEmpty && !hasProcessedBuffer {
            print("🔄 Toggle final result: '\(text)'")
            bufferedTranscription = text
            processBufferedText()
        }
    }
    
    private func handleToggleStop() {
        // Toggle mode stop: Process any buffered text before stopping
        if !bufferedTranscription.isEmpty && !hasProcessedBuffer {
            print("🔄 Toggle stop: Processing buffered text: '\(bufferedTranscription)'")
            processBufferedText()
        }
    }
    
    // MARK: - SMART COMPLETION DETECTION - Core Logic
    
    private func shouldProcessNow(text: String, confidence: Float) -> Bool {
        // Don't process if we already did
        if hasProcessedBuffer { return false }
        
        // Must have substantial content
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        
        // Check completion signals in priority order
        
        // 1. STRONG COMPLETION: Definitive punctuation
        if hasStrongPunctuation(text) {
            print("🧠 ✅ Strong punctuation completion detected")
            return true
        }
        
        // 2. MEDICAL COMPLETION: Professional phrase patterns
        if hasMedicalCompletion(text) {
            print("🧠 ✅ Medical phrase completion detected")
            return true
        }
        
        // 3. HIGH CONFIDENCE + NATURAL PAUSE: Quality speech with silence
        if confidence >= confidenceThreshold && hasNaturalPause() {
            print("🧠 ✅ High confidence + natural pause completion detected")
            return true
        }
        
        // 4. EMERGENCY TIMEOUT: Prevent infinite buffering
        let bufferAge = Date().timeIntervalSince(lastBufferUpdate)
        if bufferAge >= maxWaitTime {
            print("🧠 ⏰ Emergency timeout completion (waited \(String(format: "%.1f", bufferAge))s)")
            return true
        }
        
        // Not ready to process yet
        return false
    }
    
    private func hasStrongPunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
    }
    
    private func hasMedicalCompletion(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let medicalCompletions = [
            "years old", "was normal", "was abnormal", "follow up", 
            "discharged", "admitted", "prescribed", "advised", 
            "recommended", "unremarkable", "significant for",
            "consistent with", "suggestive of", "compatible with"
        ]
        
        return medicalCompletions.contains { lowercased.hasSuffix($0) }
    }
    
    private func hasNaturalPause() -> Bool {
        let timeSinceUpdate = Date().timeIntervalSince(lastBufferUpdate)
        return timeSinceUpdate >= naturalPauseTime
    }
    
    private func startCompletionTimer() {
        completionTimer?.invalidate()
        
        // Start timer for emergency timeout
        completionTimer = Timer.scheduledTimer(withTimeInterval: maxWaitTime, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if self.isWaitingForCompletion && !self.bufferedTranscription.isEmpty {
                    print("🧠 ⏰ Completion timer fired - processing buffered text")
                    self.processBufferedText()
                }
            }
        }
        
        isWaitingForCompletion = true
        print("🧠 ⏲️ Started completion timer (\(maxWaitTime)s)")
    }
    
    private func processBufferedText() {
        guard !isCurrentlyProcessing else {
            print("🚫 Skipping buffered processing - already processing")
            return
        }
        
        guard !bufferedTranscription.isEmpty else {
            print("🚫 No buffered text to process")
            return
        }
        
        // NEW: Check if we already processed this exact text to prevent duplicates
        let textToProcess = bufferedTranscription.trimmingCharacters(in: .whitespaces)
        if hasProcessedBuffer || textToProcess == lastProcessedContent {
            print("🚫 Already processed buffered text or duplicate content - skipping")
            return
        }
        
        isCurrentlyProcessing = true
        hasProcessedBuffer = true
        isWaitingForCompletion = false
        completionTimer?.invalidate()
        
        print("🧠 ✨ Processing complete buffered text: '\(textToProcess)'")
        
        // NEW: Track this content as processed
        lastProcessedContent = textToProcess
        
        setState(.processing)
        
        // Send complete text to delegate for smart processing
        delegate?.dictationEngine(self, didProcessText: textToProcess)
        
        // Clear buffer and reset processing flag
        bufferedTranscription = ""
        consecutivePartialResults = 0
        isCurrentlyProcessing = false
        
        // Quick reset for next completion cycle - but keep hasProcessedBuffer = true
        // to prevent double processing until we get truly new content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.isRecording {
                self.setState(.listening)
            }
            // NOTE: hasProcessedBuffer stays true until next dictation session
        }
    }
    
    // MARK: - FAST MODE - Toggle Mode Logic (Legacy)
    
    private var lastFastModeText = ""  // NEW: Track last processed text in fast mode
    
    private func handleFastTogglePartialResult(text: String) {
        // Fast mode: Use simplified immediate processing for speed
        if !hasProcessedBuffer && !text.isEmpty {
            currentBuffer = text
            
            DispatchQueue.main.async {
                self.setState(.processing)
            }
            
            // Simple timeout for fast processing
            let timeout = text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") ? 0.3 : 0.6
            
            Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if !self.hasProcessedBuffer && self.isRecording && !self.currentBuffer.isEmpty {
                        // NEW: Check for duplicates in fast mode
                        if self.currentBuffer != self.lastFastModeText {
                            self.processSimpleText(self.currentBuffer)
                        } else {
                            print("⚡ Fast mode: Skipping duplicate text '\(self.currentBuffer)'")
                            self.hasProcessedBuffer = false  // Reset to allow next different text
                        }
                    }
                }
            }
        }
    }
    
    private func processSimpleText(_ text: String) {
        guard !isCurrentlyProcessing else { return }
        
        isCurrentlyProcessing = true
        hasProcessedBuffer = true
        
        let textToProcess = text.trimmingCharacters(in: .whitespaces)
        print("⚡ Fast processing: '\(textToProcess)'")
        
        // NEW: Track processed text to prevent duplicates
        lastFastModeText = text
        
        delegate?.dictationEngine(self, didProcessText: textToProcess)
        
        currentBuffer = ""
        isCurrentlyProcessing = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.hasProcessedBuffer = false
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    // MARK: - Push-to-Talk Mode Logic (Unchanged)
    
    private func handlePushToTalkFinalResult(text: String) {
        if isWaitingForFinalResult && !text.isEmpty {
            print("📱 Push-to-talk final result: '\(text)'")
            isWaitingForFinalResult = false
            finalizePushToTalkSession(with: text)
        }
    }
    
    private func finalizePushToTalkSession(with text: String) {
        if !text.isEmpty {
            processCompleteText(text)
        }
        
        cleanupRecognition()
        setState(.idle)
        delegate?.dictationEngineDidStop(self)
    }
    
    private func handlePushToTalkPartialResult(text: String) {
        currentBuffer = text
        print("📱 Push-to-talk accumulating: '\(text)'")
    }
    
    private func handlePushToTalkStop() {
        if !currentBuffer.isEmpty {
            print("📝 Push-to-talk stop: Checking for ongoing speech...")
            
            let wasRecentlySpeaking = checkRecentSpeechActivity()
            
            if wasRecentlySpeaking {
                print("📝 Push-to-talk: Recent speech detected - delaying stop for 800ms")
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
        let bufferLength = currentBuffer.count
        if bufferLength > 0 {
            print("📝 Buffer analysis: \(bufferLength) characters - assuming potential tail speech")
            return bufferLength > 10
        }
        return false
    }
    
    private func finalizeStopPushToTalk() {
        print("📝 Push-to-talk: Finalizing stop sequence")
        isWaitingForFinalResult = true
        
        recognitionRequest?.endAudio()
        
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
        
        delegate?.dictationEngine(self, didProcessText: textToProcess)
        
        isCurrentlyProcessing = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasProcessedBuffer = false
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    // MARK: - State Management
    
    private func setState(_ newState: DictationState) {
        state = newState
        print("🎤 DictationEngine (\(dictationMode)/\(processingMode)): State → \(newState)")
    }
    
    private func cleanupRecognition() {
        // Smart completion cleanup
        bufferedTranscription = ""
        isWaitingForCompletion = false
        consecutivePartialResults = 0
        completionTimer?.invalidate()
        lastProcessedContent = ""  // NEW: Clear processed content tracking
        
        // Legacy cleanup
        currentBuffer = ""
        hasProcessedBuffer = true
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        lastFastModeText = ""  // NEW: Clear fast mode tracking
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
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