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
        // Future smart mode integration point
        let contextualStrings = VocabularyManager.shared.getContextualStrings()
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
            print("🎯 DictationEngine: Applied \(contextualStrings.count) contextual strings")
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
            
            // Send incremental text to delegate
            delegate?.dictationEngine(self, didProcessText: textToSend)
        } else {
            print("🔄 No new text to send (duplicate or subset)")
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
    
    private func extractIncrementalText(_ newText: String) -> String {
        // Handle incremental text extraction
        if lastProcessedText.isEmpty {
            // First text, send everything
            return newText
        }
        
        if newText.hasPrefix(lastProcessedText) {
            // New text extends previous text, send only the new part
            let newPart = String(newText.dropFirst(lastProcessedText.count))
            return newPart
        } else {
            // Completely different text (shouldn't happen in toggle mode, but handle gracefully)
            print("⚠️ Toggle mode: Non-incremental text detected")
            return newText
        }
    }
    
    // MARK: - Push-to-Talk Mode Logic (Final Results Only)
    
    private func handlePushToTalkFinalResult(text: String) {
        if isWaitingForFinalResult && !text.isEmpty {
            print("📱 Push-to-talk final result (Apple finalized): '\(text)'")
            isWaitingForFinalResult = false
            
            // Process Apple's complete final result
            processCompleteText(text)
        } else if !isWaitingForFinalResult {
            // Still accumulating during active push-to-talk
            print("📱 Push-to-talk final result accumulated: '\(text)'")
        }
    }
    
    private func handlePushToTalkPartialResult(text: String) {
        // Push-to-talk: Just accumulate, no processing until key release
        currentBuffer = text
        print("📱 Push-to-talk accumulating: '\(text)'")
    }
    
    private func handlePushToTalkStop() {
        // Push-to-talk: Wait for Apple's final result to capture tail end
        if !currentBuffer.isEmpty {
            print("📝 Push-to-talk stop: Waiting for Apple's final result to capture complete speech...")
            isWaitingForFinalResult = true
            
            // Set a safety timeout in case final result doesn't come
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isWaitingForFinalResult && !self.currentBuffer.isEmpty {
                    print("📝 Push-to-talk: Safety timeout - processing current buffer")
                    self.isWaitingForFinalResult = false
                    self.processCompleteText(self.currentBuffer)
                }
            }
        } else {
            print("📝 Push-to-talk stop: No buffer to process")
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
    
    // MARK: - Legacy Processing (Removed)
    
    // Removed processBuffer() - replaced with mode-specific processing:
    // - Toggle Mode: processIncrementalText() for incremental updates
    // - Push-to-Talk Mode: processCompleteText() for final results
    
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
