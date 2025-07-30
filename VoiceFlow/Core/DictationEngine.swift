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
    
    // AVAudioEngine Components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // Mode Management
    private var dictationMode: DictationMode = .toggle
    private var processingMode: ProcessingMode = .smart
    
    // State Management
    private var isActivelyRecording = false
    private var userRequestedStop = false
    private var isProcessingResults = false
    private var recognitionTaskFailed = false
    private var isSystemInitialized = false
    
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
            throw DictationError.audioEngineFailure(NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AudioEngine"]))
        }
        
        inputNode = audioEngine.inputNode
        let recordingFormat = inputNode?.outputFormat(forBus: 0)
        
        guard let format = recordingFormat else {
            throw DictationError.audioEngineFailure(NSError(domain: "AudioFormat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get recording format"]))
        }
        
        // Use optimized buffer size for better performance
        let bufferSize: AVAudioFrameCount = 512
        print("🔊 Using buffer size: \(bufferSize)")
        
        inputNode?.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Log audio format for debugging
        let sampleRate = format.sampleRate
        print("🔊 Audio format: \(format.channelCount) channels, \(sampleRate) Hz")
        
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
    
    // MARK: - Optimized Microphone Warm-Up Implementation
    
    /// Initialize microphone and speech recognition on app launch with optimized retry mechanism
    private func warmUpMicrophone() {
        print("🎵 Starting optimized microphone initialization...")
        
        // Check permissions first
        guard checkPermissions() else {
            print("🎵 Permissions not available - marking as initialized anyway")
            isSystemInitialized = true
            return
        }
        
        // Use retry mechanism for audio context errors
        performWarmUpWithRetry(maxAttempts: 3) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.isSystemInitialized = true
                    print("✅ Optimized microphone initialization completed successfully!")
                } else {
                    print("⚠️ Warm-up failed after retries, but first press will still work")
                    // Mark as initialized anyway - first press will handle any remaining issues
                    self?.isSystemInitialized = true
                }
                print("🎵 System ready: \(self?.isSystemInitialized ?? false)")
            }
        }
    }
    
    /// Check if required permissions are available
    private func checkPermissions() -> Bool {
        let microphoneStatus = AVAudioApplication.shared.recordPermission
        let speechAvailable = SFSpeechRecognizer.authorizationStatus() == .authorized
        
        print("🎵 Microphone permission: \(microphoneStatus.rawValue)")
        print("🎵 Speech recognition authorized: \(speechAvailable)")
        
        return microphoneStatus == .granted && speechAvailable
    }
    
    /// Perform warm-up with intelligent retry mechanism for Error -10877
    private func performWarmUpWithRetry(maxAttempts: Int, completion: @escaping (Bool) -> Void) {
        var attempt = 0
        var startTime = CFAbsoluteTimeGetCurrent()
        
        func tryWarmUp() {
            attempt += 1
            print("🎵 Warm-up attempt \(attempt)/\(maxAttempts)")
            
            do {
                // OPTIMIZATION 1: Ensure proper audio context initialization
                // Force mainMixerNode creation to establish audio graph
                let _ = audioEngine?.mainMixerNode
                
                // OPTIMIZATION 2: Use faster buffer size for quicker initialization
                try setupRecognitionRequest()
                try setupAudioEngine()  // Use same method as regular dictation
                try startAudioEngine()
                
                // OPTIMIZATION 3: Shorter validation period for successful cases
                print("🎵 Warm-up attempt \(attempt) succeeded - validation started")
                
                // Quick validation then cleanup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    print("🎵 Warm-up completed in \(String(format: "%.3f", elapsed))s")
                    self.completeOptimizedWarmUp()
                    completion(true)
                }
                
            } catch let error as NSError {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                print("🎵 Attempt \(attempt) failed after \(String(format: "%.3f", elapsed))s: \(error.code) - \(error.localizedDescription)")
                self.logWarmUpError(error, attempt: attempt)
                
                // OPTIMIZATION 4: Specific handling for Error -10877
                if error.code == -10877 {
                    print("🎵 Detected kAudioUnitErr_CannotDoInCurrentContext (-10877)")
                    
                    if attempt < maxAttempts {
                        // Clean up current attempt
                        self.cleanupAudioEngine()
                        self.cleanupRecognition()
                        
                        // Retry after next render cycle (community recommended delay)
                        print("🎵 Retrying after render cycle delay...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            tryWarmUp()
                        }
                        return
                    } else {
                        print("🎵 Max attempts reached for Error -10877")
                    }
                }
                // OPTIMIZATION 5: Handle other audio engine errors
                else if error.code == -10868 || error.code == -10851 {
                    print("🎵 Format/property error detected: \(error.code)")
                    
                    if attempt < maxAttempts {
                        self.cleanupAudioEngine()
                        self.cleanupRecognition()
                        
                        // Longer delay for format-related issues
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            tryWarmUp()
                        }
                        return
                    }
                }
                
                // Max attempts reached or non-recoverable error
                print("🎵 Warm-up failed: attempts exhausted or non-recoverable error")
                self.cleanupAudioEngine()
                self.cleanupRecognition()
                completion(false)
            }
        }
        
        // Start the retry process
        startTime = CFAbsoluteTimeGetCurrent()
        tryWarmUp()
    }
    
    /// Clean up warm-up session with performance tracking
    private func completeOptimizedWarmUp() {
        print("🎵 Completing optimized warm-up...")
        
        // Log final states for debugging
        let engineRunning = audioEngine?.isRunning ?? false
        print("🎵 Final states - Engine: \(engineRunning)")
        
        if let task = recognitionTask {
            print("🎵 Recognition task state: \(task.state)")
        }
        
        // OPTIMIZATION: Faster cleanup
        cleanupAudioEngine()
        cleanupRecognition()
        resetSession()
        
        print("🎵 ✅ Optimized warm-up cleanup completed")
    }
    
    /// Enhanced error logging for warm-up debugging
    private func logWarmUpError(_ error: Error, attempt: Int) {
        if let nsError = error as NSError? {
            let domain = nsError.domain
            let code = nsError.code
            let description = nsError.localizedDescription
            
            print("🎵 Error details:")
            print("🎵   Domain: \(domain)")
            print("🎵   Code: \(code)")
            print("🎵   Description: \(description)")
            print("🎵   Attempt: \(attempt)")
            
            // Specific diagnostics for known error codes
            switch code {
            case -10877:
                print("🎵   Analysis: Audio context conflict - will retry")
            case -10868:
                print("🎵   Analysis: Format not supported - may need format adjustment")
            case -10851:
                print("🎵   Analysis: Invalid property value - checking sample rates")
            case -10863:
                print("🎵   Analysis: Cannot do in current context (render thread issue)")
            default:
                print("🎵   Analysis: Unknown audio error")
            }
        }
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
    
    var isSystemReady: Bool {
        return isSystemInitialized && 
               SFSpeechRecognizer.authorizationStatus() == .authorized &&
               AVAudioApplication.shared.recordPermission == .granted
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
        
        // Apply contextual strings for medical vocabulary (only in smart mode)
        if processingMode == .smart {
            let contextualStrings = VocabularyManager.shared.getContextualStrings()
            if !contextualStrings.isEmpty {
                recognitionRequest.contextualStrings = contextualStrings
                print("🎯 Applied \(contextualStrings.count) medical terms")
            }
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
        // Note: isSystemInitialized is NOT reset - it's permanent once set
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
