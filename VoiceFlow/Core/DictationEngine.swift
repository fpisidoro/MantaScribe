import Foundation
import Speech
import AVFoundation

/// Professional dictation engine using AVAudioEngine for reliable speech recognition
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case ready
        case listening
        case processing
        case error
    }
    
    enum DictationMode {
        case toggle        // Continuous listening until manually stopped
        case pushToTalk    // Record while key held, stop when released
    }
    
    enum ProcessingMode {
        case fast
        case smart
    }
    
    enum DictationError: Error {
        case speechRecognizerUnavailable
        case audioEngineFailure(Error)
        case recognitionRequestCreationFailed
        case recognitionTaskFailed(Error)
    }
    
    // MARK: - Properties
    
    weak var delegate: DictationEngineDelegate?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var smartTextCoordinator: SmartTextCoordinator?
    
    // AVAudioEngine Components (REVERTED: Core Audio was too complex)
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // Mode Management
    private var dictationMode: DictationMode = .toggle
    private var processingMode: ProcessingMode = .smart
    
    // SIMPLIFIED STATE MANAGEMENT
    private var isActivelyRecording = false
    private var userRequestedStop = false
    private var isProcessingResults = false
    private var recognitionTaskFailed = false
    
    // Speech Processing
    private var currentText = ""
    private var lastProcessedText = ""
    private var hasReceivedAnyResults = false
    
    // Push-to-Talk Support
    private var isWaitingForPushToTalkResults = false
    private var pushToTalkTimeoutTimer: Timer?
    
    // State
    private(set) var state: DictationState = .idle {
        didSet {
            if oldValue != state {
                print("🎤 DictationEngine: State → \(state)")
            }
        }
    }
    
    // Configuration
    private let pushToTalkTimeout: TimeInterval = 3.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        setState(.ready)
        
        // 🎉 BREAKTHROUGH: This microphone warm-up SOLVED the first-press issue!
        // After months of complex attempts, simple warm-up was the answer.
        // Warm up microphone on app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.warmUpMicrophone()
        }
        
        print("🎤 DictationEngine: Initialized with AVAudioEngine for professional reliability")
    }
    
    deinit {
        cleanupAudioEngine()
    }
    
    // MARK: - AVAudioEngine Setup
    
    private func setupAudioEngine() throws {
        print("🔊 Setting up AVAudioEngine...")
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw DictationError.audioEngineFailure(NSError(domain: "AudioEngine", code: -1))
        }
        
        inputNode = audioEngine.inputNode
        let recordingFormat = inputNode?.outputFormat(forBus: 0)
        
        guard let format = recordingFormat else {
            throw DictationError.audioEngineFailure(NSError(domain: "AudioFormat", code: -1))
        }
        
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        print("✅ AVAudioEngine setup completed")
    }
    
    private func startAudioEngine() throws {
        guard let audioEngine = audioEngine else {
            throw DictationError.audioEngineFailure(NSError(domain: "AudioEngine", code: -1))
        }
        
        print("🔊 Starting AVAudioEngine...")
        try audioEngine.start()
        print("✅ AVAudioEngine started successfully!")
    }
    
    // MARK: - Public Interface
    
    func setDictationMode(_ mode: DictationMode) {
        guard !isActivelyRecording else {
            print("🎤 Cannot change mode while recording")
            return
        }
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
    
    /// Start dictation with AVAudioEngine
    func startDictation() {
        print("🎤 ═══ START DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        
        userRequestedStop = false
        
        guard !isActivelyRecording else {
            print("🎤 Already recording - ignoring duplicate start request")
            return
        }
        
        do {
            try performAVAudioEngineStart()
            print("🎤 ✅ AVAudioEngine dictation started successfully in \(dictationMode) mode")
            
        } catch {
            print("❌ Failed to start AVAudioEngine dictation: \(error)")
            handleError(DictationError.audioEngineFailure(error))
        }
    }
    
    /// Warm up microphone and speech recognition service on app launch
    private func warmUpMicrophone() {
        print("🎵 Warming up microphone and speech recognition service...")
        
        do {
            // Brief microphone activation to initialize system
            try setupRecognitionRequest()
            try setupAudioEngine()
            try startAudioEngine()
            
            // Start a very brief recognition task
            startRecognitionTask()
            
            print("🎵 Microphone warm-up initiated")
            
            // Stop after 0.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.completeWarmUp()
            }
            
        } catch {
            print("⚠️ Microphone warm-up failed: \(error)")
            // Not critical - just means first press might need retry
        }
    }
    
    private func completeWarmUp() {
        print("🎵 Completing microphone warm-up...")
        
        // Clean shutdown of warm-up session
        cleanupAudioEngine()
        cleanupRecognition()
        resetSession()
        
        print("✅ Microphone warm-up completed - first press should work!")
    }
    
    /// Stop dictation
    func stopDictation() {
        print("🎤 ═══ STOP DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        print("🎤 Mode: \(dictationMode), hasResults: \(hasReceivedAnyResults)")
        
        userRequestedStop = true
        
        guard isActivelyRecording else {
            print("🎤 Not recording - ignoring stop request")
            return
        }
        
        // Handle mode-specific stop logic
        switch dictationMode {
        case .toggle:
            handleToggleStop()
        case .pushToTalk:
            handlePushToTalkStop()
        }
    }
    
    // MARK: - State Queries
    
    var isDictating: Bool {
        return isActivelyRecording
    }
    
    var currentState: DictationState {
        return state
    }
    
    var isReady: Bool {
        return state == .ready && !isActivelyRecording
    }
    
    // MARK: - AVAudioEngine Implementation
    
    private func performAVAudioEngineStart() throws {
        setState(.listening)
        
        // Setup speech recognition
        try setupRecognitionRequest()
        
        // Setup and start AVAudioEngine
        try setupAudioEngine()
        try startAudioEngine()
        
        // Start speech recognition task
        startRecognitionTask()
        
        // Mark as actively recording
        isActivelyRecording = true
        hasReceivedAnyResults = false
        
        // Reset session state
        resetSession()
        
        // Notify delegate
        delegate?.dictationEngineDidStart(self)
        print("🎤 AVAudioEngine recording started successfully")
    }
    
    private func setupRecognitionRequest() throws {
        // Clean up any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create new request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw DictationError.recognitionRequestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Apply contextual strings for medical vocabulary (check both smart mode AND preference)
        if processingMode == .smart && PreferencesManager.shared.enableContextualStrings {
            let contextualStrings = VocabularyManager.shared.getContextualStrings()
            if !contextualStrings.isEmpty {
                recognitionRequest.contextualStrings = contextualStrings
                print("🎯 Applied \(contextualStrings.count) medical terms (contextual strings enabled)")
            }
        } else {
            print("🎯 Contextual strings bypassed (smart mode: \(processingMode == .smart), preference: \(PreferencesManager.shared.enableContextualStrings))")
        }
        
        print("🎤 Speech recognition request configured with Core Audio input")
    }
    
    private func startRecognitionTask() {
        guard let speechRecognizer = speechRecognizer,
              let recognitionRequest = recognitionRequest else {
            print("❌ Cannot start recognition - missing components")
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionCallback(result: result, error: error)
        }
        
        print("🎤 Recognition task started with Core Audio input")
    }
    
    // MARK: - Recognition Callback Handling
    
    private func handleRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        DispatchQueue.main.async {
            self.processRecognitionCallback(result: result, error: error)
        }
    }
    
    private func processRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        if userRequestedStop {
            print("🎤 Ignoring callback - user requested stop")
            return
        }
        
        if let result = result {
            handleSpeechResult(result)
        }
        
        if let error = error {
            handleRecognitionError(error)
        }
    }
    
    private func handleSpeechResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        let isFinal = result.isFinal
        let hasMetadata = result.speechRecognitionMetadata != nil
        
        print("🎤 Speech result: '\(text)' (final: \(isFinal), metadata: \(hasMetadata))")
        
        hasReceivedAnyResults = true
        currentText = text
        
        // Process final results with metadata (highest quality)
        if hasMetadata {
            print("🎤 ✨ Final result with metadata - processing")
            processFinalResult(text)
        }
        // For push-to-talk, also process when stream ends (isFinal)
        else if isFinal && dictationMode == .pushToTalk {
            print("🎤 📱 Push-to-talk final result - processing")
            processFinalResult(text)
        }
        // For toggle mode, update current text but don't send yet
        else if dictationMode == .toggle {
            print("🎤 📝 Toggle mode partial result - buffering")
        }
    }
    
    private func processFinalResult(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedText.isEmpty && trimmedText != lastProcessedText else {
            print("🎤 Skipping empty/duplicate result")
            return
        }
        
        guard !isProcessingResults else {
            print("🎤 Already processing results - skipping")
            return
        }
        
        isProcessingResults = true
        lastProcessedText = trimmedText
        
        print("🎤 🚀 Processing final result: '\(trimmedText)'")
        
        setState(.processing)
        delegate?.dictationEngine(self, didProcessText: trimmedText)
        
        isProcessingResults = false
        
        if isActivelyRecording && !userRequestedStop {
            setState(.listening)
        }
    }
    
    private func handleRecognitionError(_ error: Error) {
        print("❌ Recognition error: \(error.localizedDescription)")
        
        // CRITICAL: Immediately stop Core Audio to prevent endless error loop
        isActivelyRecording = false
        recognitionTaskFailed = true
        
        if !userRequestedStop {
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("no speech") && !hasReceivedAnyResults {
                print("🎤 No speech detected - this is normal for silence")
                return
            }
            
            print("❌ Fatal recognition error - stopping dictation immediately")
            handleError(DictationError.recognitionTaskFailed(error))
            performCleanStop()
        }
    }
    
    // MARK: - Mode-Specific Stop Handling
    
    private func handleToggleStop() {
        print("🎤 Toggle stop: Processing any buffered text")
        
        if !currentText.isEmpty && currentText != lastProcessedText {
            let trimmedText = currentText.trimmingCharacters(in: .whitespaces)
            if !trimmedText.isEmpty {
                print("🎤 Toggle stop: Sending buffered text: '\(trimmedText)'")
                setState(.processing)
                delegate?.dictationEngine(self, didProcessText: trimmedText)
                lastProcessedText = trimmedText
            }
        }
        
        performCleanStop()
    }
    
    private func handlePushToTalkStop() {
        print("🎤 Push-to-talk stop: Ending audio and waiting for final results")
        
        recognitionRequest?.endAudio()
        
        if !hasReceivedAnyResults {
            print("🎤 Push-to-talk: No results yet - waiting \(pushToTalkTimeout)s for results")
            isWaitingForPushToTalkResults = true
            
            pushToTalkTimeoutTimer = Timer.scheduledTimer(withTimeInterval: pushToTalkTimeout, repeats: false) { [weak self] _ in
                self?.handlePushToTalkTimeout()
            }
        } else {
            print("🎤 Push-to-talk: Have results - processing immediately")
            if !currentText.isEmpty && currentText != lastProcessedText {
                processFinalResult(currentText)
            }
            performCleanStop()
        }
    }
    
    private func handlePushToTalkTimeout() {
        print("🎤 Push-to-talk timeout - processing any available text")
        pushToTalkTimeoutTimer = nil
        isWaitingForPushToTalkResults = false
        
        if !currentText.isEmpty && currentText != lastProcessedText {
            processFinalResult(currentText)
        }
        
        performCleanStop()
    }
    
    // MARK: - Error Handling & Cleanup
    
    private func handleError(_ error: DictationError) {
        setState(.error)
        delegate?.dictationEngine(self, didEncounterError: error)
    }
    
    private func performCleanStop() {
        print("🎤 Performing clean stop with AVAudioEngine cleanup")
        
        // Cancel timers
        pushToTalkTimeoutTimer?.invalidate()
        pushToTalkTimeoutTimer = nil
        
        // Clean up AVAudioEngine and recognition
        cleanupAudioEngine()
        cleanupRecognition()
        
        // Update state
        isActivelyRecording = false
        isWaitingForPushToTalkResults = false
        setState(.ready)
        
        // Notify delegate
        delegate?.dictationEngineDidStop(self)
        print("🎤 ✅ AVAudioEngine clean stop completed")
    }
    
    private func cleanupAudioEngine() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        print("🔊 AVAudioEngine cleanup completed")
    }
    
    private func cleanupRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        print("🎤 Recognition components cleaned up")
    }
    
    private func resetSession() {
        currentText = ""
        lastProcessedText = ""
        hasReceivedAnyResults = false
        isProcessingResults = false
        isWaitingForPushToTalkResults = false
        recognitionTaskFailed = false
        print("🎤 Session reset complete")
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        print("🎤 Speech recognizer initialized")
    }
    
    private func setState(_ newState: DictationState) {
        state = newState
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension DictationEngine: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isActivelyRecording {
                print("⚠️ Speech recognizer became unavailable")
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
