import Foundation
import Speech
import AVFoundation
import AudioToolbox
import CoreAudio

/// Bulletproof dictation engine with macOS Audio Unit configuration for first-use reliability
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
        case audioUnitConfigurationFailed(Error)
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
        
        // Early initialization to prevent cold starts
        DispatchQueue.global(qos: .utility).async {
            self.preInitializeAudioSystem()
        }
        
        print("🎤 DictationEngine: Initialized with macOS Audio Unit configuration")
    }
    
    // MARK: - macOS Audio Unit Configuration
    
    private func configureMacOSAudioSystem() throws {
        print("🔊 Configuring macOS Audio Unit system...")
        
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "DictationEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio unit available"]))
        }
        
        // STEP 1: Enable input on the Audio Unit
        var enableInput: UInt32 = 1
        let enableInputResult = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Input bus
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        if enableInputResult != noErr {
            print("❌ Failed to enable audio unit input: \(enableInputResult)")
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "AudioUnit", code: Int(enableInputResult), userInfo: nil))
        }
        
        // STEP 2: Configure sample rate at Audio Unit level
        var sampleRate: Float64 = 44100.0
        let sampleRateResult = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Input,
            1,
            &sampleRate,
            UInt32(MemoryLayout<Float64>.size)
        )
        
        if sampleRateResult != noErr {
            print("⚠️ Warning: Could not set audio unit sample rate: \(sampleRateResult)")
            // Not fatal - continue with default
        }
        
        // STEP 3: Configure audio format for optimal recording
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("🔊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // STEP 4: Set up buffer size for optimal performance
        var bufferFrameSize: UInt32 = 1024
        let bufferSizeResult = AudioUnitSetProperty(
            audioUnit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &bufferFrameSize,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        if bufferSizeResult != noErr {
            print("⚠️ Warning: Could not set buffer frame size: \(bufferSizeResult)")
            // Not fatal - continue with default
        }
        
        // STEP 5: Initialize the Audio Unit
        let initResult = AudioUnitInitialize(audioUnit)
        if initResult != noErr {
            print("❌ Failed to initialize audio unit: \(initResult)")
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "AudioUnit", code: Int(initResult), userInfo: nil))
        }
        
        print("✅ macOS Audio Unit configuration completed successfully")
    }
    
    private func configureMacOSAudioDeviceAccess() throws {
        print("🔊 Configuring macOS audio device access...")
        
        // STEP 1: Get default input device
        var deviceID: AudioDeviceID = 0
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let getDeviceResult = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceIDAddress,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        )
        
        if getDeviceResult != noErr {
            print("❌ Failed to get default input device: \(getDeviceResult)")
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "AudioDevice", code: Int(getDeviceResult), userInfo: nil))
        }
        
        print("🔊 Default input device ID: \(deviceID)")
        
        // STEP 2: Verify device sample rate
        var sampleRate: Float64 = 0
        var sampleRateSize = UInt32(MemoryLayout<Float64>.size)
        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let getSampleRateResult = AudioObjectGetPropertyData(
            deviceID,
            &sampleRateAddress,
            0,
            nil,
            &sampleRateSize,
            &sampleRate
        )
        
        if getSampleRateResult == noErr {
            print("🔊 Device sample rate: \(sampleRate)Hz")
        } else {
            print("⚠️ Could not get device sample rate: \(getSampleRateResult)")
        }
        
        print("✅ macOS audio device access configured")
    }
    
    private func verifyMicrophonePermissions() throws {
        print("🔊 Verifying microphone permissions...")
        
        // Check microphone authorization status
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch authStatus {
        case .authorized:
            print("✅ Microphone permission: Authorized")
        case .denied:
            print("❌ Microphone permission: Denied")
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "Permissions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"]))
        case .restricted:
            print("❌ Microphone permission: Restricted")
            throw DictationError.audioUnitConfigurationFailed(NSError(domain: "Permissions", code: -2, userInfo: [NSLocalizedDescriptionKey: "Microphone access restricted"]))
        case .notDetermined:
            print("⚠️ Microphone permission: Not determined - requesting...")
            // For macOS, we can't synchronously request permission here
            // The permission will be requested when audio engine starts
        @unknown default:
            print("⚠️ Microphone permission: Unknown status")
        }
        
        // Additional verification: Check if we can access audio input devices
        let inputDevices = AVAudioSession.sharedInstance().availableInputs
        if inputDevices?.isEmpty ?? true {
            print("⚠️ No audio input devices available")
        } else {
            print("✅ Audio input devices available: \(inputDevices?.count ?? 0)")
        }
    }
    
    private func preInitializeAudioSystem() {
        print("🔥 Pre-initializing macOS audio system to prevent cold starts...")
        
        do {
            // STEP 1: Verify permissions first
            try verifyMicrophonePermissions()
            
            // STEP 2: Configure audio device access
            try configureMacOSAudioDeviceAccess()
            
            // STEP 3: Create temporary engine for full initialization
            let tempEngine = AVAudioEngine()
            
            // Force initialization of critical nodes in proper order
            _ = tempEngine.outputNode
            _ = tempEngine.mainMixerNode
            let tempInputNode = tempEngine.inputNode
            
            // STEP 4: Configure temporary Audio Unit
            if let tempAudioUnit = tempInputNode.audioUnit {
                var enableInput: UInt32 = 1
                AudioUnitSetProperty(
                    tempAudioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    1,
                    &enableInput,
                    UInt32(MemoryLayout<UInt32>.size)
                )
                
                AudioUnitInitialize(tempAudioUnit)
            }
            
            // STEP 5: Brief engine test with Audio Unit configured
            tempEngine.prepare()
            try tempEngine.start()
            
            // Brief operation to ensure system is active
            Thread.sleep(forTimeInterval: 0.2)
            
            // Clean shutdown
            tempEngine.stop()
            
            print("🔥 ✅ macOS audio system pre-initialization completed successfully")
            
        } catch {
            print("🔥 ⚠️ macOS audio system pre-initialization failed: \(error.localizedDescription)")
            // Not critical - main engine will handle initialization
        }
    }
    
    private func queueDictationAndWarmup() {
        guard !isSystemWarming else {
            print("🔄 Already warming system - request already queued")
            return
        }
        
        print("🔄 Queuing dictation request and warming macOS audio system...")
        hasPendingDictationRequest = true
        isSystemWarming = true
        
        // Start background warmup
        DispatchQueue.global(qos: .userInitiated).async {
            self.performMacOSSystemWarmup()
        }
        
        // Safety timeout in case warmup hangs
        warmupTimer = Timer.scheduledTimer(withTimeInterval: systemWarmupTimeout, repeats: false) { [weak self] _ in
            self?.handleWarmupTimeout()
        }
    }
    
    private func performMacOSSystemWarmup() {
        do {
            print("🔥 Performing macOS-specific system warmup...")
            
            // STEP 1: Configure audio device access
            try configureMacOSAudioDeviceAccess()
            
            // STEP 2: Test audio engine with full Audio Unit configuration
            let testEngine = AVAudioEngine()
            let inputNode = testEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // STEP 3: Configure Audio Unit on test engine
            if let audioUnit = inputNode.audioUnit {
                var enableInput: UInt32 = 1
                let result = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    1,
                    &enableInput,
                    UInt32(MemoryLayout<UInt32>.size)
                )
                
                if result != noErr {
                    print("⚠️ Warmup: Audio Unit configuration warning: \(result)")
                }
                
                AudioUnitInitialize(audioUnit)
            }
            
            // STEP 4: Install tap and test
            inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { _, _ in }
            testEngine.prepare()
            try testEngine.start()
            
            // Extended delay to ensure system is fully stable
            Thread.sleep(forTimeInterval: 0.3)
            
            // STEP 5: Test speech recognition initialization
            let testRequest = SFSpeechAudioBufferRecognitionRequest()
            testRequest.shouldReportPartialResults = false
            
            // Cleanup
            testEngine.stop()
            inputNode.removeTap(onBus: 0)
            
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
        print("✅ macOS system warmup completed successfully")
        isSystemWarming = false
        warmupTimer?.invalidate()
        warmupTimer = nil
        
        // Execute queued request if any
        if hasPendingDictationRequest {
            hasPendingDictationRequest = false
            print("🚀 Executing queued dictation request with macOS Audio Unit configuration")
            
            // Reset state for fresh start
            resetSession()
            
            // Start the recognition process
            do {
                try performStart()
                print("🎤 ✅ Dictation started successfully in \(dictationMode) mode")
            } catch {
                print("❌ Failed to start dictation after macOS warmup: \(error)")
                handleError(DictationError.audioEngineFailure(error))
            }
        }
    }
    
    private func handleWarmupFailure(_ error: Error) {
        print("❌ macOS system warmup failed: \(error.localizedDescription)")
        isSystemWarming = false
        warmupTimer?.invalidate()
        warmupTimer = nil
        
        // Try to execute the queued request anyway - might work now
        if hasPendingDictationRequest {
            hasPendingDictationRequest = false
            print("🤷‍♂️ Attempting queued dictation despite macOS warmup failure")
            
            // Reset state for fresh start
            resetSession()
            
            // Start the recognition process
            do {
                try performStart()
                print("🎤 ✅ Dictation started successfully in \(dictationMode) mode")
            } catch {
                print("❌ Failed to start dictation after failed macOS warmup: \(error)")
                handleError(DictationError.audioEngineFailure(error))
            }
        }
    }
    
    private func handleWarmupTimeout() {
        print("⏰ macOS system warmup timed out - proceeding anyway")
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
    
    /// Start dictation - Always use queue for reliability
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
        
        // ALWAYS queue and warm up for reliability
        print("🔄 Using macOS Audio Unit queue system for reliable startup")
        queueDictationAndWarmup()
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
        
        // Setup and start audio engine with macOS Audio Unit configuration
        try setupMacOSAudioEngine()
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
        print("🎤 Recording started successfully with macOS Audio Unit configuration")
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
        
        // Use server-based recognition for maximum reliability
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
    
    private func setupMacOSAudioEngine() throws {
        print("🔊 Setting up macOS Audio Engine with Audio Unit configuration...")
        
        // Stop any existing audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // CRITICAL: Force initialization of the audio chain before configuration
        _ = audioEngine.outputNode     // Force output node initialization
        _ = audioEngine.mainMixerNode  // Force mixer initialization
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Configure macOS Audio Unit BEFORE installing tap
        try configureMacOSAudioSystem()
        
        // Install audio tap AFTER Audio Unit configuration
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Call prepare() after Audio Unit configuration
        audioEngine.prepare()
        print("🔊 macOS Audio Engine configured with Audio Unit optimization")
    }
    
    private func startAudioEngine() throws {
        do {
            try audioEngine.start()
            print("🎤 macOS Audio Engine started with Audio Unit configuration")
        } catch {
            // Check if this is the common cold-start error
            let nsError = error as NSError
            if nsError.code == -10877 {
                print("⚠️ Audio engine cold start detected (-10877) - attempting macOS-specific recovery")
                try handleMacOSColdStartRecovery()
            } else {
                print("❌ Audio engine failed with: \(error.localizedDescription)")
                throw DictationError.audioEngineFailure(error)
            }
        }
    }
    
    private func handleMacOSColdStartRecovery() throws {
        print("🔄 Performing macOS-specific cold start recovery sequence...")
        
        // Full reset sequence
        audioEngine.stop()
        audioEngine.reset()  // Clear all connections
        
        // Small delay for system cleanup
        Thread.sleep(forTimeInterval: 0.1)
        
        // Reinitialize with macOS Audio Unit configuration
        try setupMacOSAudioEngine()
        
        // Second attempt
        do {
            try audioEngine.start()
            print("🔄 ✅ macOS cold start recovery successful")
        } catch {
            print("🔄 ❌ macOS cold start recovery failed")
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
        
        print("🎤 Recognition task started (macOS Audio Unit pre-configured)")
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
        print("🎤 Performing clean stop with macOS Audio Unit cleanup")
        
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
        
        print("🎤 Recognition components cleaned up (macOS Audio Unit deinitialized)")
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
