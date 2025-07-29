import Foundation
import Speech
import AVFoundation

/// Safe dictation engine with smart cold start handling (no proactive warm-up)
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case ready         // Available for dictation
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
    
    // METADATA-BASED PROCESSING
    private var currentPartialText = ""           // For UI feedback only
    private var lastProcessedText = ""            // Track processed final results
    private var isCurrentlyProcessing = false     // Prevent concurrent processing
    
    // Push-to-Talk Support
    private var isWaitingForFinalResult = false   // Push-to-talk completion tracking
    private var pushToTalkBackgroundQueue: DispatchQueue? // Background processing for push-to-talk
    
    // SAFE COLD START MANAGEMENT
    private var hasEverStartedSuccessfully = false // Track if we've ever had a successful start
    private var userRequestedStop = false          // User explicitly requested stop
    private var coldStartAttempts = 0              // Count of cold start attempts
    private let maxColdStartAttempts = 2           // Maximum retry attempts
    
    // State
    private(set) var state: DictationState = .idle {
        didSet {
            print("🎤 DictationEngine: State → \(state)")
        }
    }
    private(set) var isRecording = false
    
    // Configuration
    private let enableOnDeviceRecognition = true
    private let bufferSize: AVAudioFrameCount = 1024
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        setState(.ready) // Available for use immediately
        print("🎤 DictationEngine: Initialized and ready (no proactive warm-up)")
    }
    
    // MARK: - Mode Management
    
    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
        print("🎤 DictationEngine: Mode set to \(mode)")
    }
    
    func updatePerformanceMode(_ smartModeEnabled: Bool) {
        processingMode = smartModeEnabled ? .smart : .fast
        print("🎤 DictationEngine: Processing mode set to \(processingMode)")
    }
    
    func setSmartTextCoordinator(_ coordinator: SmartTextCoordinator) {
        self.smartTextCoordinator = coordinator
    }
    
    // MARK: - Public Interface
    
    /// Start dictation with safe cold start handling
    func startDictation() {
        // Clear any previous stop request
        userRequestedStop = false
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            let error = DictationError.speechRecognizerUnavailable
            delegate?.dictationEngine(self, didEncounterError: error)
            return
        }
        
        guard !isRecording else {
            print("🎤 Already recording - ignoring start request")
            return
        }
        
        print("🎙️ DictationEngine: Starting \(dictationMode) dictation")
        performStartDictation()
    }
    
    private func performStartDictation() {
        setState(.listening)
        resetSession()
        
        do {
            try setupRecognitionRequest()
            try setupAudioEngine()
            try startAudioEngine()
            startRecognitionTask()
            
            isRecording = true
            coldStartAttempts = 0 // Reset on successful start
            hasEverStartedSuccessfully = true
            delegate?.dictationEngineDidStart(self)
            print("✅ Dictation started successfully")
            
        } catch {
            print("❌ Failed to start dictation: \(error)")
            handleStartFailure(error)
        }
    }
    
    private func handleStartFailure(_ error: Error) {
        cleanupRecognition()
        setState(.error)
        
        // For cold start issues, try again with a brief delay (but only a few times)
        if !hasEverStartedSuccessfully && coldStartAttempts < maxColdStartAttempts {
            coldStartAttempts += 1
            print("🌡️ Cold start attempt \(coldStartAttempts)/\(maxColdStartAttempts) failed - retrying in 1s...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !self.userRequestedStop && !self.isRecording {
                    print("🔄 Cold start retry \(self.coldStartAttempts)")
                    self.setState(.ready)
                    self.performStartDictation()
                }
            }
        } else {
            // Give up and report error
            let dictationError: DictationError
            if let audioError = error as? DictationError {
                dictationError = audioError
            } else {
                dictationError = DictationError.recognitionTaskFailed(error)
            }
            delegate?.dictationEngine(self, didEncounterError: dictationError)
        }
    }
    
    /// Stop dictation with reliable stop behavior
    func stopDictation() {
        print("⏹️ DictationEngine: User requested stop")
        
        // Mark that user explicitly requested stop
        userRequestedStop = true
        coldStartAttempts = 0 // Reset retry counter
        
        guard isRecording else {
            print("🎤 Not recording - ignoring stop request")
            return
        }
        
        print("⏹️ DictationEngine: Stopping \(dictationMode) dictation")
        
        // Mode-specific stop behavior
        switch dictationMode {
        case .toggle:
            handleToggleStop()
            cleanupRecognition()
            setState(.ready)
            isRecording = false
            delegate?.dictationEngineDidStop(self)
            
        case .pushToTalk:
            handlePushToTalkStop()
            // Note: cleanup will be called from finalizePushToTalkStop()
        }
    }
    
    // MARK: - State Queries
    
    var isDictating: Bool {
        return isRecording
    }
    
    var currentState: DictationState {
        return state
    }
    
    var isReady: Bool {
        return state == .ready || state == .idle
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        print("🎤 DictationEngine: Speech recognizer initialized")
    }
    
    private func resetSession() {
        currentPartialText = ""
        lastProcessedText = ""
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        print("🎤 DictationEngine: Session reset")
    }
    
    private func setupRecognitionRequest() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        guard let speechRecognizer = speechRecognizer else {
            throw DictationError.speechRecognizerUnavailable
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw DictationError.recognitionRequestCreationFailed
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
    
    private func setupAudioEngine() throws {
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
    
    private func startAudioEngine() throws {
        do {
            try audioEngine.start()
            print("🎤 DictationEngine: Audio engine started")
        } catch {
            print("❌ DictationEngine: Audio engine failed: \(error)")
            throw DictationError.audioEngineFailure(error)
        }
    }
    
    private func startRecognitionTask() {
        guard let speechRecognizer = speechRecognizer,
              let recognitionRequest = recognitionRequest else {
            print("❌ Cannot start recognition task - missing components")
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            // Check if user requested stop before processing results
            if self.userRequestedStop {
                print("🎤 Ignoring recognition result - user requested stop")
                return
            }
            
            if let result = result {
                self.handleRecognitionResult(result)
            }
            
            if let error = error {
                print("❌ DictationEngine: Recognition error: \(error.localizedDescription)")
                
                // Only report error if user didn't request stop
                if !self.userRequestedStop {
                    DispatchQueue.main.async {
                        let dictationError = DictationError.recognitionTaskFailed(error)
                        self.delegate?.dictationEngine(self, didEncounterError: dictationError)
                        self.stopDictation()
                    }
                }
            }
        }
        
        print("🎤 DictationEngine: Recognition task started")
    }
    
    // MARK: - Recognition Result Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        // Skip processing if user requested stop
        guard !userRequestedStop else {
            print("🎤 Skipping result processing - user requested stop")
            return
        }
        
        let text = result.bestTranscription.formattedString
        let hasMetadata = result.speechRecognitionMetadata != nil
        
        print("🎤 Apple result: text='\(text)', isFinal=\(result.isFinal), hasMetadata=\(hasMetadata)")
        
        if hasMetadata {
            handleTrueFinalResult(text: text, result: result)
        } else {
            handlePartialResult(text: text)
        }
        
        if result.isFinal {
            handleStreamEnd()
        }
    }
    
    private func handleTrueFinalResult(text: String, result: SFSpeechRecognitionResult) {
        guard !isCurrentlyProcessing && !userRequestedStop else {
            print("🎤 Skipping final result - already processing or user stopped")
            return
        }
        
        let textToProcess = text.trimmingCharacters(in: .whitespaces)
        
        guard !textToProcess.isEmpty && textToProcess != lastProcessedText else {
            print("🎤 Skipping empty or duplicate final result")
            return
        }
        
        isCurrentlyProcessing = true
        lastProcessedText = textToProcess
        
        // Cancel push-to-talk background processing since we got the final result
        if dictationMode == .pushToTalk && isWaitingForFinalResult {
            print("🎤 Push-to-talk: Got metadata result, cancelling background processing")
            isWaitingForFinalResult = false
        }
        
        print("🎤 ✨ Processing FINAL result: '\(textToProcess)'")
        
        DispatchQueue.main.async {
            self.setState(.processing)
            self.delegate?.dictationEngine(self, didProcessText: textToProcess)
            self.isCurrentlyProcessing = false
            
            if self.isRecording && !self.userRequestedStop {
                self.setState(.listening)
            }
        }
    }
    
    private func handlePartialResult(text: String) {
        currentPartialText = text
        
        if !text.isEmpty {
            print("🎤 🔄 Partial result: '\(text)'")
        }
    }
    
    private func handleStreamEnd() {
        print("🎤 🟥 Recognition stream ended")
        
        switch dictationMode {
        case .toggle:
            // Continue listening until user stops
            break
        case .pushToTalk:
            // Already handled in handlePushToTalkStop()
            break
        }
    }
    
    // MARK: - Mode-Specific Stop Handling
    
    private func handleToggleStop() {
        print("🎤 Toggle mode: Processing any remaining text")
        
        // Process any unprocessed partial text as fallback
        if !currentPartialText.isEmpty && currentPartialText != lastProcessedText {
            let textToProcess = currentPartialText.trimmingCharacters(in: .whitespaces)
            if !textToProcess.isEmpty {
                print("🎤 Toggle mode: Processing partial text: '\(textToProcess)'")
                lastProcessedText = textToProcess
                
                DispatchQueue.main.async {
                    self.setState(.processing)
                    self.delegate?.dictationEngine(self, didProcessText: textToProcess)
                }
            }
        }
    }
    
    private func handlePushToTalkStop() {
        print("🎤 Push-to-talk: Starting background processing")
        
        pushToTalkBackgroundQueue = DispatchQueue(label: "pushToTalkProcessing", qos: .userInitiated)
        recognitionRequest?.endAudio()
        isWaitingForFinalResult = true
        
        pushToTalkBackgroundQueue?.async { [weak self] in
            guard let self = self else { return }
            
            var waitCount = 0
            let maxWaitCycles = 30 // 3 seconds total
            
            while self.isWaitingForFinalResult && waitCount < maxWaitCycles && !self.userRequestedStop {
                Thread.sleep(forTimeInterval: 0.1)
                waitCount += 1
            }
            
            if self.isWaitingForFinalResult && !self.userRequestedStop {
                print("🎤 Push-to-talk: Timeout - processing partial text")
                DispatchQueue.main.async {
                    if !self.currentPartialText.isEmpty {
                        let textToProcess = self.currentPartialText.trimmingCharacters(in: .whitespaces)
                        if !textToProcess.isEmpty && textToProcess != self.lastProcessedText {
                            print("🎤 Push-to-talk: Processing partial: '\(textToProcess)'")
                            self.lastProcessedText = textToProcess
                            self.delegate?.dictationEngine(self, didProcessText: textToProcess)
                        }
                    }
                    self.isWaitingForFinalResult = false
                }
            }
        }
        
        DispatchQueue.main.async {
            self.finalizePushToTalkStop()
        }
    }
    
    private func finalizePushToTalkStop() {
        isWaitingForFinalResult = false
        cleanupRecognition()
        setState(.ready)
        isRecording = false
        delegate?.dictationEngineDidStop(self)
        print("🎤 Push-to-talk: Stop completed")
    }
    
    // MARK: - State Management
    
    private func setState(_ newState: DictationState) {
        state = newState
    }
    
    // MARK: - Cleanup
    
    private func cleanupRecognition() {
        currentPartialText = ""
        lastProcessedText = ""
        isCurrentlyProcessing = false
        isWaitingForFinalResult = false
        pushToTalkBackgroundQueue = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        print("🎤 DictationEngine: Recognition cleaned up")
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension DictationEngine: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isRecording {
                print("⚠️ DictationEngine: Speech recognizer unavailable")
                self.stopDictation()
            }
        }
    }
}

// MARK: - Delegate Protocol

protocol DictationEngineDelegate: AnyObject {
    func dictationEngine(_ engine: DictationEngine, didProcessText text: String)
    func dictationEngineDidStart(_ engine: DictationEngine)
    func dictationEngineDidStop(_ engine: DictationEngine)
    func dictationEngine(_ engine: DictationEngine, didEncounterError error: Error)
}
