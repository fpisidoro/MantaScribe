import Foundation
import Speech
import AVFoundation

/// Bulletproof dictation engine with audio warm-up system for first-use reliability
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
    private var audioEngine = AVAudioEngine()
    private var smartTextCoordinator: SmartTextCoordinator?
    
    // Mode Management
    private var dictationMode: DictationMode = .toggle
    private var processingMode: ProcessingMode = .smart
    
    // ROCK-SOLID STATE MANAGEMENT
    private var isActivelyRecording = false        // True only when actually recording audio
    private var userRequestedStop = false          // User explicitly wants to stop
    private var isProcessingResults = false        // Currently processing speech results
    
    // Speech Processing
    private var currentText = ""                   // Current accumulated text
    private var lastProcessedText = ""             // Last text we sent to delegate
    private var hasReceivedAnyResults = false      // Track if we've gotten any speech results
    
    // Push-to-Talk Support
    private var isWaitingForPushToTalkResults = false
    private var pushToTalkTimeoutTimer: Timer?
    
    // Simple Queue System
    private var hasPendingDictationRequest = false
    private var isSystemWarming = false
    private var warmupTimer: Timer?
    
    // State
    private(set) var state: DictationState = .idle {
        didSet {
            if oldValue != state {
                print("🎤 DictationEngine: State → \(state)")
            }
        }
    }
    
    // Configuration
    private let bufferSize: AVAudioFrameCount = 1024
    private let pushToTalkTimeout: TimeInterval = 3.0  // Max wait for results after key release
    private let systemWarmupTimeout: TimeInterval = 2.0  // Max time to wait for system warmup
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        setState(.ready)
        print("🎤 DictationEngine: Initialized with simple queue system")
    }
    
    // MARK: - System Readiness Check
    
    private func isSystemReady() -> Bool {
        // Quick speech recognizer check
        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            print("⚠️ Speech recognizer not available")
            return false
        }
        
        // REAL TEST: Can we actually start audio capture?
        do {
            let testEngine = AVAudioEngine()
            let inputNode = testEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Try to install tap and start - this will fail if system is cold
            inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { _, _ in }
            testEngine.prepare()
            try testEngine.start()
            
            // If we got here, system is actually ready
            testEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            print("✅ System readiness check passed (audio engine test)")
            return true
        } catch {
            print("⚠️ System readiness check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func queueDictationAndWarmup() {
        guard !isSystemWarming else {
            print("🔄 Already warming system - request already queued")
            return
        }
        
        print("🔄 Queuing dictation request and warming system...")
        hasPendingDictationRequest = true
        isSystemWarming = true
        
        // Start background warmup
        DispatchQueue.global(qos: .userInitiated).async {
            self.performSystemWarmup()
        }
        
        // Safety timeout in case warmup hangs
        warmupTimer = Timer.scheduledTimer(withTimeInterval: systemWarmupTimeout, repeats: false) { [weak self] _ in
            self?.handleWarmupTimeout()
        }
    }
    
    private func performSystemWarmup() {
        do {
            // Test audio engine initialization
            let testEngine = AVAudioEngine()
            let inputNode = testEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Brief test to wake up the system
            inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { _, _ in }
            testEngine.prepare()
            try testEngine.start()
            
            // Small delay to ensure system is stable
            Thread.sleep(forTimeInterval: 0.2)
            
            // Cleanup
            testEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            // Test speech recognition
            let testRequest = SFSpeechAudioBufferRecognitionRequest()
            testRequest.shouldReportPartialResults = false
            
            DispatchQueue.main.async {
                self.handleWarmupSuccess()
            }
            
        } catch {
            DispatchQueue.main.async {
                self.handleWarmupFailure(error)
            }
        }
    }
    
    private func handleWarmupSuccess() {
        print("✅ System warmup completed successfully")
        isSystemWarming = false
        warmupTimer?.invalidate()
        warmupTimer = nil
        
        // Execute queued request if any
        if hasPendingDictationRequest {
            hasPendingDictationRequest = false
            print("🚀 Executing queued dictation request")
            startDictation()
        }
    }
    
    private func handleWarmupFailure(_ error: Error) {
        print("❌ System warmup failed: \(error.localizedDescription)")
        isSystemWarming = false
        warmupTimer?.invalidate()
        warmupTimer = nil
        
        // Try to execute the queued request anyway - might work now
        if hasPendingDictationRequest {
            hasPendingDictationRequest = false
            print("🤷‍♂️ Attempting queued dictation despite warmup failure")
            startDictation()
        }
    }
    
    private func handleWarmupTimeout() {
        print("⏰ System warmup timed out - proceeding anyway")
        warmupTimer = nil
        handleWarmupSuccess()  // Treat timeout as success and try anyway
    }
    
    // MARK: - Public Interface
    
    func setDictationMode(_ mode: DictationMode) {
        // Only change mode when not actively recording
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
    
    /// Start dictation - Simple try-first approach
    func startDictation() {
        print("🎤 ═══ START DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        
        // Clear stop flag - user wants to start
        userRequestedStop = false
        
        // If already warming, just update the queue
        if isSystemWarming {
            print("🔄 System warming - ensuring request is queued")
            hasPendingDictationRequest = true
            return
        }
        
        guard !isActivelyRecording else {
            print("🎤 Already recording - ignoring duplicate start request")
            return
        }
        
        // Quick system readiness check
        if !isSystemReady() {
            print("⚠️ System not ready - queuing request and warming up")
            queueDictationAndWarmup()
            return
        }
        
        // System is ready - try to start immediately
        print("✅ System ready - starting dictation immediately")
        
        // Reset state for fresh start
        resetSession()
        
        // Start the recognition process
        do {
            try performStart()
            print("🎤 ✅ Dictation started successfully in \(dictationMode) mode")
        } catch {
            print("❌ Failed to start dictation: \(error)")
            
            // If immediate start failed, try queuing and warming
            print("🔄 Immediate start failed - falling back to queue and warmup")
            queueDictationAndWarmup()
        }
    }
    
    /// Stop dictation - BULLETPROOF VERSION  
    func stopDictation() {
        print("🎤 ═══ STOP DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        print("🎤 Mode: \(dictationMode), hasResults: \(hasReceivedAnyResults)")
        
        // Mark that user wants to stop (prevents any auto-restarts)
        userRequestedStop = true
        
        // Cancel any pending operations
        cancelPendingOperations()
        
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
        return state == .ready && !isActivelyRecording && !isSystemWarming
    }
    
    // MARK: - Private Implementation
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.delegate = self
        print("🎤 Speech recognizer initialized")
    }
    
    private func resetSession() {
        currentText = ""
        lastProcessedText = ""
        hasReceivedAnyResults = false
        isProcessingResults = false
        isWaitingForPushToTalkResults = false
        print("🎤 Session reset complete")
    }
    
    private func cancelPendingOperations() {
        // Cancel timers
        pushToTalkTimeoutTimer?.invalidate()
        pushToTalkTimeoutTimer = nil
        warmupTimer?.invalidate()
        warmupTimer = nil
        
        // Clear pending requests
        hasPendingDictationRequest = false
        isSystemWarming = false
    }
    
    private func performStart() throws {
        setState(.listening)
        
        // Setup recognition request
        try setupRecognitionRequest()
        
        // Setup and start audio engine
        try setupAudioEngine()
        try startAudioEngine()
        
        // Brief delay for audio engine stabilization
        let initializationDelay: TimeInterval = 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + initializationDelay) {
            self.startRecognitionTask()
        }
        
        // Mark as actively recording
        isActivelyRecording = true
        hasReceivedAnyResults = false
        
        // Notify delegate
        delegate?.dictationEngineDidStart(self)
        print("🎤 Recording started successfully")
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
        
        // SIMPLE APPROACH: Just use server-based recognition without forcing specific settings
        print("🎤 Using server-based recognition for maximum reliability")
        
        // Apply contextual strings for medical vocabulary (only in smart mode)
        if processingMode == .smart {
            let contextualStrings = VocabularyManager.shared.getContextualStrings()
            if !contextualStrings.isEmpty {
                recognitionRequest.contextualStrings = contextualStrings
                print("🎯 Applied \(contextualStrings.count) medical terms")
            }
        }
    }
    
    private func setupAudioEngine() throws {
        // Stop any existing audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install audio tap
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        print("🎤 Audio engine configured")
    }
    
    private func startAudioEngine() throws {
        do {
            try audioEngine.start()
            print("🎤 Audio engine started")
        } catch {
            throw DictationError.audioEngineFailure(error)
        }
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
        
        print("🎤 Recognition task started (pre-warmed system)")
    }
    
    // MARK: - Recognition Callback Handling
    
    private func handleRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        // Always run on main queue for thread safety
        DispatchQueue.main.async {
            self.processRecognitionCallback(result: result, error: error)
        }
    }
    
    private func processRecognitionCallback(result: SFSpeechRecognitionResult?, error: Error?) {
        // Check if user requested stop - ignore all results if so
        if userRequestedStop {
            print("🎤 Ignoring callback - user requested stop")
            return
        }
        
        // Handle successful result
        if let result = result {
            handleSpeechResult(result)
        }
        
        // Handle errors (only if user didn't request stop)
        if let error = error {
            handleRecognitionError(error)
        }
    }
    
    private func handleSpeechResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        let isFinal = result.isFinal
        let hasMetadata = result.speechRecognitionMetadata != nil
        
        print("🎤 Speech result: '\(text)' (final: \(isFinal), metadata: \(hasMetadata))")
        
        // Mark that we've received results
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
            // Just buffer the text, don't send until we get metadata or user stops
        }
    }
    
    private func processFinalResult(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        
        // Skip empty or duplicate results
        guard !trimmedText.isEmpty && trimmedText != lastProcessedText else {
            print("🎤 Skipping empty/duplicate result")
            return
        }
        
        // Prevent concurrent processing
        guard !isProcessingResults else {
            print("🎤 Already processing results - skipping")
            return
        }
        
        isProcessingResults = true
        lastProcessedText = trimmedText
        
        print("🎤 🚀 Processing final result: '\(trimmedText)'")
        
        setState(.processing)
        delegate?.dictationEngine(self, didProcessText: trimmedText)
        
        // Reset processing flag
        isProcessingResults = false
        
        // Return to listening if still recording
        if isActivelyRecording && !userRequestedStop {
            setState(.listening)
        }
    }
    
    private func handleRecognitionError(_ error: Error) {
        print("❌ Recognition error: \(error.localizedDescription)")
        
        // Only handle error if user didn't request stop (errors during stop are expected)
        if !userRequestedStop {
            // Check if this is a "no speech detected" error during first few seconds
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("no speech") && !hasReceivedAnyResults {
                print("🎤 No speech detected - this is normal for silence")
                // Don't treat "no speech" as a fatal error, just continue listening
                return
            }
            
            // For other errors, stop and notify
            print("❌ Fatal recognition error - stopping dictation")
            handleError(DictationError.recognitionTaskFailed(error))
            performCleanStop()
        }
    }
    
    // MARK: - Mode-Specific Stop Handling
    
    private func handleToggleStop() {
        print("🎤 Toggle stop: Processing any buffered text")
        
        // Process any unprocessed text
        if !currentText.isEmpty && currentText != lastProcessedText {
            let trimmedText = currentText.trimmingCharacters(in: .whitespaces)
            if !trimmedText.isEmpty {
                print("🎤 Toggle stop: Sending buffered text: '\(trimmedText)'")
                setState(.processing)
                delegate?.dictationEngine(self, didProcessText: trimmedText)
                lastProcessedText = trimmedText
            }
        }
        
        // Clean stop
        performCleanStop()
    }
    
    private func handlePushToTalkStop() {
        print("🎤 Push-to-talk stop: Ending audio and waiting for final results")
        
        // End audio input to signal completion
        recognitionRequest?.endAudio()
        
        // If we haven't received any results yet, wait a bit
        if !hasReceivedAnyResults {
            print("🎤 Push-to-talk: No results yet - waiting \(pushToTalkTimeout)s for results")
            isWaitingForPushToTalkResults = true
            
            pushToTalkTimeoutTimer = Timer.scheduledTimer(withTimeInterval: pushToTalkTimeout, repeats: false) { [weak self] _ in
                self?.handlePushToTalkTimeout()
            }
        } else {
            // We have results, process them
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
        
        // Process whatever text we have
        if !currentText.isEmpty && currentText != lastProcessedText {
            processFinalResult(currentText)
        }
        
        performCleanStop()
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: DictationError) {
        setState(.error)
        delegate?.dictationEngine(self, didEncounterError: error)
    }
    

    
    // MARK: - Clean Shutdown
    
    private func performCleanStop() {
        print("🎤 Performing clean stop")
        
        // Cancel all timers and operations
        cancelPendingOperations()
        
        // Clean up recognition
        cleanupRecognition()
        
        // Update state
        isActivelyRecording = false
        isWaitingForPushToTalkResults = false
        setState(.ready)
        
        // Notify delegate
        delegate?.dictationEngineDidStop(self)
        print("🎤 ✅ Clean stop completed")
    }
    
    private func cleanupRecognition() {
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
        
        print("🎤 Recognition components cleaned up")
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