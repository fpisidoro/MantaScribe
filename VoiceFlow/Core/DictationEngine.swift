import Foundation
import Speech
import AVFoundation

/// Bulletproof dictation engine with audio warm-up system for first-use reliability
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case ready
        case warming         // NEW: Audio engine warm-up state
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
        case audioEngineWarmupFailed(Error)  // NEW
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
    
    // NEW: Speech Service Connection Management
    private var speechServiceConnected = false
    private var systemSleepObserver: NSObjectProtocol?
    private var systemWakeObserver: NSObjectProtocol?
    private var connectionValidationTimer: Timer?
    
    // NEW: Speech Recognition Pre-warming System
    private var isSpeechRecognitionWarmedUp = false
    private var speechRecognitionWarmupAttempts = 0
    private var maxSpeechRecognitionWarmupAttempts = 2
    private var speechRecognitionWarmupTimer: Timer?
    private var pendingSpeechRecognitionRequest = false
    
    // NEW: Speech Recognition Task Management
    private var recognitionTaskRetryCount = 0
    private var maxRecognitionTaskRetries = 2
    private var recognitionTaskRetryTimer: Timer?
    
    // MARK: - NEW: Audio Engine Warm-up System
    private var isAudioEngineWarmedUp = false
    private var warmupAttempts = 0
    private var maxWarmupAttempts = 3
    private var isPerformingWarmup = false
    private var pendingStartRequest = false        // Track if user requested start during warmup
    private var autoRetryTimer: Timer?
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
    private let warmupDelay: TimeInterval = 1.0        // NEW: Delay before warmup retry
    private let autoRetryDelay: TimeInterval = 0.5     // NEW: Delay before auto-retry
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSpeechRecognizer()
        setupSystemEventMonitoring()
        setState(.ready)
        
        // Start both audio engine and speech recognition warm-up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performAudioEngineWarmup()
            self.performSpeechRecognitionWarmup()
        }
        
        print("🎤 DictationEngine: Initialized - bulletproof reliability mode")
    }
    
    deinit {
        removeSystemEventMonitoring()
    }
    
    // MARK: - NEW: System Event Monitoring
    
    private func setupSystemEventMonitoring() {
        // Monitor system sleep events
        systemSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        
        // Monitor system wake events  
        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }
        
        print("📉 System sleep/wake monitoring initialized")
    }
    
    private func removeSystemEventMonitoring() {
        if let observer = systemSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            systemSleepObserver = nil
        }
        
        if let observer = systemWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            systemWakeObserver = nil
        }
        
        connectionValidationTimer?.invalidate()
        connectionValidationTimer = nil
    }
    
    private func handleSystemWillSleep() {
        print("📉 😴 System going to sleep - marking speech service as disconnected")
        speechServiceConnected = false
        
        // Stop any active dictation cleanly
        if isActivelyRecording {
            print("📉 Stopping active dictation before sleep")
            stopDictation()
        }
    }
    
    private func handleSystemDidWake() {
        print("📉 😊 System woke up - validating speech service connection")
        speechServiceConnected = false  // Assume disconnected until validated
        
        // Validate connection after a brief delay to let system stabilize
        connectionValidationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.validateSpeechServiceConnection()
        }
    }
    
    private func validateSpeechServiceConnection() {
        print("📉 Validating speech service connection...")
        
        // Reset warm-up flags to force re-initialization
        isSpeechRecognitionWarmedUp = false
        speechRecognitionWarmupAttempts = 0
        
        // Perform speech recognition warm-up to validate/restore connection
        performSpeechRecognitionWarmup()
    }
    
    // MARK: - NEW: Audio Engine Warm-up System
    
    private func performAudioEngineWarmup() {
        guard !isAudioEngineWarmedUp && !isPerformingWarmup else { return }
        
        warmupAttempts += 1
        isPerformingWarmup = true
        setState(.warming)
        
        print("🔥 Audio Engine Warm-up: Attempt \(warmupAttempts)/\(maxWarmupAttempts)")
        
        // Perform warm-up in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            self.executeWarmupSequence()
        }
    }
    
    private func executeWarmupSequence() {
        do {
            // Test audio engine initialization and startup
            try self.testAudioEngineInitialization()
            
            // Success - mark as warmed up
            DispatchQueue.main.async {
                self.handleWarmupSuccess()
            }
            
        } catch {
            print("⚠️ Warm-up attempt \(warmupAttempts) failed: \(error.localizedDescription)")
            
            DispatchQueue.main.async {
                self.handleWarmupFailure(error)
            }
        }
    }
    
    private func testAudioEngineInitialization() throws {
        // Create a temporary audio engine for testing
        let testEngine = AVAudioEngine()
        let inputNode = testEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install a test tap (will be removed immediately)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { _, _ in
            // Do nothing - just testing initialization
        }
        
        testEngine.prepare()
        
        // Try to start the engine
        try testEngine.start()
        
        // Brief moment to ensure it's stable
        Thread.sleep(forTimeInterval: 0.1)
        
        // Clean up
        testEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        print("🔥 Audio engine test successful")
    }
    
    private func handleWarmupSuccess() {
        isAudioEngineWarmedUp = true
        isPerformingWarmup = false
        setState(.ready)
        
        print("🔥 ✅ Audio Engine Warm-up: SUCCESS after \(warmupAttempts) attempts")
        
        // If user tried to start during warmup, start now
        if pendingStartRequest {
            pendingStartRequest = false
            print("🔥 Executing pending start request")
            startDictation()
        }
    }
    
    // MARK: - NEW: Speech Recognition Warm-up System
    
    private func performSpeechRecognitionWarmup() {
        guard !isSpeechRecognitionWarmedUp && speechRecognitionWarmupAttempts < maxSpeechRecognitionWarmupAttempts else { return }
        
        speechRecognitionWarmupAttempts += 1
        
        print("🧾 Speech Recognition Warm-up: Attempt \(speechRecognitionWarmupAttempts)/\(maxSpeechRecognitionWarmupAttempts)")
        
        // Perform speech recognition warm-up in background
        DispatchQueue.global(qos: .utility).async {
            self.executeSpeechRecognitionWarmup()
        }
    }
    
    private func executeSpeechRecognitionWarmup() {
        do {
            // Create a test recognition request to warm up the speech recognition system
            let warmupRequest = SFSpeechAudioBufferRecognitionRequest()
            warmupRequest.shouldReportPartialResults = false
            
            // Test speech recognizer availability and create a minimal task
            guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                throw DictationError.speechRecognizerUnavailable
            }
            
            // Create a brief test recognition task to initialize the system
            let warmupTask = speechRecognizer.recognitionTask(with: warmupRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.handleSpeechRecognitionWarmupResult(result: result, error: error)
                }
            }
            
            // End the test task quickly - we just want to initialize the system
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                warmupRequest.endAudio()
                warmupTask.cancel()
            }
            
            print("🧾 Speech recognition warm-up task created")
            
        } catch {
            DispatchQueue.main.async {
                self.handleSpeechRecognitionWarmupFailure(error)
            }
        }
    }
    
    private func handleSpeechRecognitionWarmupResult(result: SFSpeechRecognitionResult?, error: Error?) {
        // Don't care about the actual result - we just want to warm up the system
        if error == nil {
            handleSpeechRecognitionWarmupSuccess()
        } else {
            handleSpeechRecognitionWarmupFailure(error!)
        }
    }
    
    private func handleSpeechRecognitionWarmupSuccess() {
        isSpeechRecognitionWarmedUp = true
        speechServiceConnected = true
        print("🧾 ✅ Speech Recognition Warm-up: SUCCESS after \(speechRecognitionWarmupAttempts) attempts")
        print("🧾 🔗 Speech service connection validated")
        
        // If user tried to start during warmup, start now
        if pendingSpeechRecognitionRequest {
            pendingSpeechRecognitionRequest = false
            print("🧾 Executing pending speech recognition request")
            startDictation()
        }
    }
    
    private func handleSpeechRecognitionWarmupFailure(_ error: Error) {
        if speechRecognitionWarmupAttempts < maxSpeechRecognitionWarmupAttempts {
            print("🧾 Speech recognition warm-up failed, retrying in 1s...")
            
            speechRecognitionWarmupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                self.performSpeechRecognitionWarmup()
            }
        } else {
            print("🧾 ❌ Speech Recognition Warm-up: FAILED after \(maxSpeechRecognitionWarmupAttempts) attempts")
            isSpeechRecognitionWarmedUp = true  // Allow normal operation anyway
        }
    }
    
    private func handleWarmupFailure(_ error: Error) {
        isPerformingWarmup = false
        
        if warmupAttempts < maxWarmupAttempts {
            print("🔥 Warm-up failed, retrying in \(warmupDelay)s...")
            
            warmupTimer = Timer.scheduledTimer(withTimeInterval: warmupDelay, repeats: false) { _ in
                self.performAudioEngineWarmup()
            }
        } else {
            print("🔥 ❌ Audio Engine Warm-up: FAILED after \(maxWarmupAttempts) attempts")
            setState(.ready)  // Continue anyway, will rely on auto-retry
        }
    }
    
    private func shouldAttemptAutoRetry(for error: Error) -> Bool {
        // Auto-retry for audio engine failures during first few attempts
        let errorDescription = error.localizedDescription.lowercased()
        let isAudioError = errorDescription.contains("audio") || 
                          errorDescription.contains("10877") ||
                          errorDescription.contains("engine")
        
        return isAudioError && !isAudioEngineWarmedUp
    }
    
    private func scheduleAutoRetry() {
        print("🔄 Scheduling auto-retry in \(autoRetryDelay)s...")
        
        autoRetryTimer = Timer.scheduledTimer(withTimeInterval: autoRetryDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("🔄 Executing auto-retry...")
            self.autoRetryTimer = nil
            
            // Try once more, but mark as warmed up to prevent infinite retries
            self.isAudioEngineWarmedUp = true
            self.startDictation()
        }
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
    
    /// Start dictation - BULLETPROOF VERSION with Speech Recognition Pre-warming
    func startDictation() {
        print("🎤 ═══ START DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        print("🎤 Audio warm-up: \(isAudioEngineWarmedUp), Speech warm-up: \(isSpeechRecognitionWarmedUp)")
        
        // Clear stop flag - user wants to start
        userRequestedStop = false
        
        // If audio engine is warming up, queue the request
        if isPerformingWarmup {
            print("🔥 Audio engine warming up - queuing start request")
            pendingStartRequest = true
            return
        }
        
        // If speech recognition is warming up, queue the request
        if !isSpeechRecognitionWarmedUp || !speechServiceConnected {
            if !speechServiceConnected {
                print("📉 Speech service not connected - triggering reconnection")
                validateSpeechServiceConnection()
            }
            print("🧾 Speech recognition warming up - queuing start request")
            pendingSpeechRecognitionRequest = true
            return
        }
        
        // Validate prerequisites
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            handleError(DictationError.speechRecognizerUnavailable)
            return
        }
        
        guard !isActivelyRecording else {
            print("🎤 Already recording - ignoring duplicate start request")
            return
        }
        
        // Reset state for fresh start
        resetSession()
        
        // Start the recognition process
        do {
            try performStart()
            print("🎤 ✅ Dictation started successfully in \(dictationMode) mode")
        } catch {
            print("❌ Failed to start dictation: \(error)")
            
            // Check if we should auto-retry
            if shouldAttemptAutoRetry(for: error) {
                handleStartFailureWithRetry(error)
            } else {
                handleStartFailure(error)
            }
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
        return state == .ready && !isActivelyRecording && !isPerformingWarmup
    }
    
    var isSystemReady: Bool {
        return isAudioEngineWarmedUp && isSpeechRecognitionWarmedUp && speechServiceConnected && isReady
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
        recognitionTaskRetryCount = 0
        print("🎤 Session reset complete")
    }
    
    private func cancelPendingOperations() {
        // Cancel timers
        pushToTalkTimeoutTimer?.invalidate()
        pushToTalkTimeoutTimer = nil
        autoRetryTimer?.invalidate()
        autoRetryTimer = nil
        warmupTimer?.invalidate()
        warmupTimer = nil
        recognitionTaskRetryTimer?.invalidate()
        recognitionTaskRetryTimer = nil
        speechRecognitionWarmupTimer?.invalidate()
        speechRecognitionWarmupTimer = nil
        connectionValidationTimer?.invalidate()
        connectionValidationTimer = nil
        
        // Clear pending requests
        pendingStartRequest = false
        pendingSpeechRecognitionRequest = false
        recognitionTaskRetryCount = 0
    }
    
    private func performStart() throws {
        setState(.listening)
        
        // Setup recognition request
        try setupRecognitionRequest()
        
        // Setup and start audio engine
        try setupAudioEngine()
        try startAudioEngine()
        
        // Brief delay for audio engine stabilization
        let initializationDelay = isAudioEngineWarmedUp ? 0.1 : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + initializationDelay) {
            self.startRecognitionTask()
        }
        
        // Mark as actively recording
        isActivelyRecording = true
        hasReceivedAnyResults = false
        
        // Mark system as warmed up on successful start
        if !isAudioEngineWarmedUp {
            isAudioEngineWarmedUp = true
            print("🔥 Audio engine marked as warmed up after successful start")
        }
        
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
    
    private func handleStartFailure(_ error: Error) {
        setState(.error)
        
        let dictationError: DictationError
        if let existing = error as? DictationError {
            dictationError = existing
        } else {
            dictationError = DictationError.recognitionTaskFailed(error)
        }
        
        delegate?.dictationEngine(self, didEncounterError: dictationError)
    }
    
    private func handleStartFailureWithRetry(_ error: Error) {
        print("🔄 Start failed, but will auto-retry: \(error.localizedDescription)")
        
        // Don't immediately show error to user - try auto-retry first
        setState(.ready)
        scheduleAutoRetry()
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