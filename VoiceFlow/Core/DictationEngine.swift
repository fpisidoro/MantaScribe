import Foundation
import Speech
import AVFoundation

/// Clean dictation engine with Metadata-Based Final Result Detection
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case listening
        case processing
        case error
    }
    
    enum DictationMode {
        case toggle        // Continuous listening with metadata-based finalization
        case pushToTalk    // Stop and wait for natural final result
    }
    
    enum ProcessingMode {
        case fast          // Minimal processing for speed
        case smart         // Full smart features on final results
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
    
    // METADATA-BASED PROCESSING - Simple Properties
    private var currentPartialText = ""           // For UI feedback only
    private var lastProcessedText = ""            // Track processed final results
    private var isCurrentlyProcessing = false     // Prevent concurrent processing
    
    // Push-to-Talk Support
    private var isWaitingForFinalResult = false   // Push-to-talk completion tracking
    private var pushToTalkBackgroundQueue: DispatchQueue? // Background processing for push-to-talk
    
    // Cold Start Management
    private var isSystemWarmedUp = false          // Track if first successful recognition happened
    private var startAttemptCount = 0             // Count start attempts for debugging
    
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
        resetSession()
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
            // Toggle mode: Stop immediately
            handleToggleStop()
            cleanupRecognition()
            setState(.idle)
            isRecording = false
            delegate?.dictationEngineDidStop(self)
            
        case .pushToTalk:
            // Push-to-talk: Wait for final result before cleanup
            handlePushToTalkStop()
            // Note: cleanup will be called from handleStreamEnd() or timeout
        }
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
    
    private func resetSession() {
        // Reset metadata-based processing state
        currentPartialText = ""
        lastProcessedText = ""
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        
        print("🎤 DictationEngine: Session reset for metadata-based processing")
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
                
                // Check for cold start issues and auto-retry
                if !self.isSystemWarmedUp && self.startAttemptCount <= 2 {
                    print("🌡️ DictationEngine: Cold start error detected - auto-retrying in 0.5s (attempt \(self.startAttemptCount)/2)")
                    
                    // Auto-retry after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("🔄 DictationEngine: Auto-retry starting...")
                        self.startDictation()
                    }
                    return
                }
                
                // If still failing after retries, give up and report error
                if !self.isSystemWarmedUp {
                    print("😱 DictationEngine: Cold start failed after retries - system may have issues")
                }
                
                DispatchQueue.main.async {
                    let dictationError = DictationError.recognitionTaskFailed(error)
                    self.delegate?.dictationEngine(self, didEncounterError: dictationError)
                    self.stopDictation()
                }
            }
        }
        
        print("🎤 DictationEngine: Recognition task started")
    }
    
    // MARK: - Metadata-Based Recognition Result Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        
        // Log Apple's result metadata for debugging
        let hasMetadata = result.speechRecognitionMetadata != nil
        print("🎤 Apple result: text='\(text)', isFinal=\(result.isFinal), hasMetadata=\(hasMetadata)")
        
        if hasMetadata {
            // TRUE final result with metadata - process immediately
            handleTrueFinalResult(text: text, result: result)
        } else {
            // Partial result - update for UI feedback only
            handlePartialResult(text: text)
        }
        
        // Handle stream end (when isFinal = true)
        if result.isFinal {
            handleStreamEnd()
        }
    }
    
    // MARK: - New Metadata-Based Result Processing
    
    private func handleTrueFinalResult(text: String, result: SFSpeechRecognitionResult) {
        guard !isCurrentlyProcessing else {
            print("😫 Skipping final result processing - already processing")
            return
        }
        
        let textToProcess = text.trimmingCharacters(in: .whitespaces)
        
        // Skip empty results
        guard !textToProcess.isEmpty else {
            print("😫 Skipping empty final result")
            return
        }
        
        // Skip duplicates
        guard textToProcess != lastProcessedText else {
            print("😫 Skipping duplicate final result: '\(textToProcess)'")
            return
        }
        
        isCurrentlyProcessing = true
        lastProcessedText = textToProcess
        
        // For push-to-talk, cancel background processing since we got the final result
        if dictationMode == .pushToTalk && isWaitingForFinalResult {
            print("🎤 Push-to-talk: Got metadata result, cancelling background processing")
            isWaitingForFinalResult = false
        }
        
        // Calculate confidence from segments (should be reliable now)
        let confidence: Float
        if !result.bestTranscription.segments.isEmpty {
            let totalConfidence = result.bestTranscription.segments.reduce(0.0) { $0 + $1.confidence }
            confidence = totalConfidence / Float(result.bestTranscription.segments.count)
        } else {
            confidence = 0.5
        }
        
        print("🎤 ✨ Processing FINAL result: '\(textToProcess)' (confidence: \(String(format: "%.2f", confidence)))")
        
        DispatchQueue.main.async {
            self.setState(.processing)
            
            // Send to delegate for processing
            self.delegate?.dictationEngine(self, didProcessText: textToProcess)
            
            // Reset processing flag
            self.isCurrentlyProcessing = false
            
            // Return to listening if still recording
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    private func handlePartialResult(text: String) {
        // Update partial text for potential UI feedback (future feature)
        currentPartialText = text
        
        // Mark system as warmed up on first successful partial result
        if !isSystemWarmedUp {
            isSystemWarmedUp = true
            startAttemptCount = 0  // Reset counter after successful warm-up
            print("🌡️ DictationEngine: System warmed up - first recognition successful")
        }
        
        // Log partial results for debugging (can be removed later)
        if !text.isEmpty {
            print("🎤 🔄 Partial result: '\(text)' (UI feedback only)")
        }
    }
    
    private func handleStreamEnd() {
        print("🎤 🟥 Recognition stream ended (isFinal=true)")
        
        // Handle mode-specific stream end logic
        switch dictationMode {
        case .toggle:
            // For toggle mode, stream end just means this recognition cycle is complete
            // We continue listening until user manually stops
            break
        case .pushToTalk:
            // For push-to-talk using immediate processing, stream end is just informational
            // The stop sequence was already handled in handlePushToTalkStop()
            print("🎤 Push-to-talk: Stream end (already processed with immediate method)")
        }
    }
    
    // MARK: - Mode-Specific Stop Handling
    
    private func handleToggleStop() {
        // For toggle mode, we just stop - but add fallback for metadata issues
        print("🎤 Toggle mode: Clean stop - checking for unprocessed text")
        
        // FALLBACK: If we have partial text but never got metadata result, process it
        if !currentPartialText.isEmpty && currentPartialText != lastProcessedText {
            let textToProcess = currentPartialText.trimmingCharacters(in: .whitespaces)
            if !textToProcess.isEmpty {
                print("🎤 Toggle mode: Processing partial text as fallback: '\(textToProcess)'")
                lastProcessedText = textToProcess
                
                DispatchQueue.main.async {
                    self.setState(.processing)
                    self.delegate?.dictationEngine(self, didProcessText: textToProcess)
                    
                    // Brief delay then reset to idle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !self.isRecording {
                            self.setState(.idle)
                        }
                    }
                }
            }
        }
    }
    
    private func handlePushToTalkStop() {
        // For push-to-talk, start background processing and return immediately
        print("🎤 Push-to-talk: Starting background processing, UI responsive immediately")
        
        // Create background queue for processing
        pushToTalkBackgroundQueue = DispatchQueue(label: "pushToTalkProcessing", qos: .userInitiated)
        
        // Signal end of audio input
        recognitionRequest?.endAudio()
        
        // Set flag to expect final result
        isWaitingForFinalResult = true
        
        // Start background processing that won't be cancelled
        pushToTalkBackgroundQueue?.async { [weak self] in
            guard let self = self else { return }
            
            // Wait for metadata result on background thread
            var waitCount = 0
            let maxWaitCycles = 30 // 3 seconds total (30 * 0.1s)
            
            while self.isWaitingForFinalResult && waitCount < maxWaitCycles {
                Thread.sleep(forTimeInterval: 0.1) // Check every 100ms
                waitCount += 1
            }
            
            // If we timed out without getting metadata result, process partial text
            if self.isWaitingForFinalResult {
                print("🎤 Push-to-talk: Background timeout - processing partial text")
                DispatchQueue.main.async {
                    if !self.currentPartialText.isEmpty {
                        let textToProcess = self.currentPartialText.trimmingCharacters(in: .whitespaces)
                        if !textToProcess.isEmpty && textToProcess != self.lastProcessedText {
                            print("🎤 Push-to-talk: Processing partial text: '\(textToProcess)'")
                            self.lastProcessedText = textToProcess
                            self.delegate?.dictationEngine(self, didProcessText: textToProcess)
                        }
                    }
                    self.isWaitingForFinalResult = false
                }
            }
        }
        
        // Complete UI stop sequence immediately (user sees immediate response)
        DispatchQueue.main.async {
            self.finalizePushToTalkStop()
        }
    }
    
    /// Complete the push-to-talk stop sequence with cleanup
    private func finalizePushToTalkStop() {
        isWaitingForFinalResult = false
        cleanupRecognition()
        setState(.idle)
        isRecording = false
        delegate?.dictationEngineDidStop(self)
        print("🎤 Push-to-talk: Stop sequence completed")
    }
    
    // MARK: - State Management
    
    private func setState(_ newState: DictationState) {
        state = newState
        print("🎤 DictationEngine (\(dictationMode)/\(processingMode)): State → \(newState)")
    }
    
    // MARK: - Cleanup
    
    private func cleanupRecognition() {
        // Simple cleanup for metadata-based processing
        currentPartialText = ""
        lastProcessedText = ""
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        
        // Clean up push-to-talk background queue
        pushToTalkBackgroundQueue = nil
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Stop recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        print("🎤 DictationEngine: Recognition cleaned up (metadata-based)")
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
