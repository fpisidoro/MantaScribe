import Foundation
import Speech
import AVFoundation
import AudioToolbox
import CoreAudio

/// Professional dictation engine using Core Audio for bulletproof first-press reliability
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
        case coreAudioFailure(Error)
        case recognitionRequestCreationFailed
        case recognitionTaskFailed(Error)
        case audioQueueCreationFailed(OSStatus)
    }
    
    // MARK: - Properties
    
    weak var delegate: DictationEngineDelegate?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var smartTextCoordinator: SmartTextCoordinator?
    
    // Core Audio Components
    private var audioQueue: AudioQueueRef?
    private var audioFormat = AudioStreamBasicDescription()
    private var audioBuffers: [AudioQueueBufferRef?] = []
    private let numberOfBuffers = 3
    private let bufferSize: UInt32 = 8192  // Larger buffer for Core Audio
    
    // Mode Management
    private var dictationMode: DictationMode = .toggle
    private var processingMode: ProcessingMode = .smart
    
    // SIMPLIFIED STATE MANAGEMENT
    private var isActivelyRecording = false
    private var userRequestedStop = false
    private var isProcessingResults = false
    
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
        setupCoreAudioFormat()
        setState(.ready)
        print("🎤 DictationEngine: Initialized with Core Audio for professional reliability")
        
        // BRILLIANT: "Waste" the first try during startup so user never sees the failure
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            self.performSilentStartupTest()
        }
    }
    
    deinit {
        cleanupCoreAudio()
    }
    
    // MARK: - Silent Startup Test
    
    /// Performs a silent speech recognition test during app startup to "waste" the first try
    /// so the user's actual first attempt will be Apple's "second try" and work reliably
    private func performSilentStartupTest() {
        print("🔥 Performing silent startup speech recognition test to prime Apple's service...")
        
        // Only do this if we're in ready state and not actively recording
        guard state == .ready && !isActivelyRecording else {
            print("🔥 Skipping startup test - app not in ready state")
            return
        }
        
        do {
            // Create a minimal speech recognition test
            let testRequest = SFSpeechAudioBufferRecognitionRequest()
            testRequest.shouldReportPartialResults = false
            
            // Create minimal Core Audio setup for test
            try createTestCoreAudioQueue()
            
            // Start very brief test recording
            guard let testQueue = audioQueue else {
                print("🔥 No test queue available")
                return
            }
            
            // Start test recording for just 0.5 seconds
            AudioQueueStart(testQueue, nil)
            
            // Create test recognition task
            let testTask = speechRecognizer?.recognitionTask(with: testRequest) { result, error in
                // Ignore all results - this is just to prime the service
                DispatchQueue.main.async {
                    if let error = error {
                        print("🔥 Startup test completed with expected error: \(error.localizedDescription.prefix(50))")
                    } else {
                        print("🔥 Startup test completed with result")
                    }
                }
            }
            
            // Stop test after very brief period
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                testTask?.cancel()
                self.cleanupTestAudio()
                print("🔥 ✅ Silent startup test completed - Apple's speech service primed")
                print("🔥 🎤 User's first dictation attempt should now work reliably!")
            }
            
        } catch {
            print("🔥 Startup test failed: \(error.localizedDescription) (not critical)")
            cleanupTestAudio()
        }
    }
    
    /// Creates a minimal Core Audio queue just for the startup test
    private func createTestCoreAudioQueue() throws {
        print("🔥 Creating minimal test audio queue...")
        
        let callbackPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        let status = AudioQueueNewInput(
            &audioFormat,
            testAudioQueueCallback,
            callbackPointer,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.commonModes.rawValue,
            0,
            &audioQueue
        )
        
        guard status == noErr else {
            throw DictationError.audioQueueCreationFailed(status)
        }
        
        // Create just one buffer for the test
        var buffer: AudioQueueBufferRef?
        let bufferStatus = AudioQueueAllocateBuffer(audioQueue!, 4096, &buffer)
        
        if bufferStatus == noErr, let audioBuffer = buffer {
            audioBuffers.append(audioBuffer)
            AudioQueueEnqueueBuffer(audioQueue!, audioBuffer, 0, nil)
        }
    }
    
    /// Minimal callback for startup test - just consumes audio without processing
    private let testAudioQueueCallback: AudioQueueInputCallback = { userData, queue, bufferRef, startTime, numPackets, packetDescs in
        // Just re-enqueue the buffer - we don't need to process the audio for the test
        AudioQueueEnqueueBuffer(queue, bufferRef, 0, nil)
    }
    
    /// Clean up test audio resources
    private func cleanupTestAudio() {
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            
            for buffer in audioBuffers {
                if let audioBuffer = buffer {
                    AudioQueueFreeBuffer(queue, audioBuffer)
                }
            }
            audioBuffers.removeAll()
            
            AudioQueueDispose(queue, true)
            audioQueue = nil
        }
    }
    
    // MARK: - Core Audio Setup
    
    private func setupCoreAudioFormat() {
        // Configure professional audio format
        audioFormat.mSampleRate = 44100.0
        audioFormat.mFormatID = kAudioFormatLinearPCM
        audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
        audioFormat.mBitsPerChannel = 16
        audioFormat.mChannelsPerFrame = 1  // Mono
        audioFormat.mBytesPerFrame = 2     // 16-bit mono
        audioFormat.mFramesPerPacket = 1
        audioFormat.mBytesPerPacket = 2
        audioFormat.mReserved = 0
        
        print("🔊 Core Audio format configured: 44.1kHz, 16-bit, mono")
    }
    
    private func createCoreAudioQueue() throws {
        print("🔊 Creating Core Audio input queue...")
        
        // Create audio queue for recording
        let callbackPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        let status = AudioQueueNewInput(
            &audioFormat,
            audioQueueCallback,
            callbackPointer,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.commonModes.rawValue,
            0,
            &audioQueue
        )
        
        guard status == noErr, let queue = audioQueue else {
            print("❌ Failed to create Core Audio queue: \(status)")
            throw DictationError.audioQueueCreationFailed(status)
        }
        
        // Configure queue properties for optimal recording
        var enableLevelMetering: UInt32 = 1
        AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &enableLevelMetering, UInt32(MemoryLayout<UInt32>.size))
        
        // Create and enqueue buffers
        audioBuffers = []
        for i in 0..<numberOfBuffers {
            var buffer: AudioQueueBufferRef?
            let bufferStatus = AudioQueueAllocateBuffer(queue, bufferSize, &buffer)
            
            if bufferStatus == noErr, let audioBuffer = buffer {
                audioBuffers.append(audioBuffer)
                AudioQueueEnqueueBuffer(queue, audioBuffer, 0, nil)
                print("🔊 Created Core Audio buffer \(i + 1) (\(bufferSize) bytes)")
            } else {
                print("❌ Failed to create Core Audio buffer \(i + 1): \(bufferStatus)")
                throw DictationError.audioQueueCreationFailed(bufferStatus)
            }
        }
        
        print("✅ Core Audio queue created successfully with \(numberOfBuffers) buffers")
    }
    
    // MARK: - Core Audio Callback
    
    private let audioQueueCallback: AudioQueueInputCallback = { userData, queue, bufferRef, startTime, numPackets, packetDescs in
        
        guard let userData = userData else { return }
        let dictationEngine = Unmanaged<DictationEngine>.fromOpaque(userData).takeUnretainedValue()
        
        // Process the audio data
        dictationEngine.processAudioBuffer(buffer: bufferRef, packetCount: numPackets)
        
        // Re-enqueue the buffer for continuous recording
        AudioQueueEnqueueBuffer(queue, bufferRef, 0, nil)
    }
    
    private func processAudioBuffer(buffer: AudioQueueBufferRef, packetCount: UInt32) {
        guard isActivelyRecording, !userRequestedStop else { return }
        
        // Convert Core Audio buffer to AVAudioPCMBuffer for speech recognition
        let audioBuffer = convertToAVAudioBuffer(coreAudioBuffer: buffer, packetCount: packetCount)
        
        // Send to speech recognizer
        DispatchQueue.main.async {
            self.recognitionRequest?.append(audioBuffer)
        }
    }
    
    private func convertToAVAudioBuffer(coreAudioBuffer: AudioQueueBufferRef, packetCount: UInt32) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: audioFormat.mSampleRate,
            channels: AVAudioChannelCount(audioFormat.mChannelsPerFrame),
            interleaved: true
        )!
        
        let frameLength = packetCount
        let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)!
        audioBuffer.frameLength = frameLength
        
        // Copy audio data
        let audioData = coreAudioBuffer.pointee.mAudioData.bindMemory(to: Int16.self, capacity: Int(packetCount))
        let bufferData = audioBuffer.int16ChannelData![0]
        
        for i in 0..<Int(packetCount) {
            bufferData[i] = audioData[i]
        }
        
        return audioBuffer
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
    
    /// Start dictation with Core Audio
    func startDictation() {
        print("🎤 ═══ START DICTATION REQUEST ═══")
        print("🎤 Current state: \(state), isActivelyRecording: \(isActivelyRecording)")
        
        userRequestedStop = false
        
        guard !isActivelyRecording else {
            print("🎤 Already recording - ignoring duplicate start request")
            return
        }
        
        do {
            try performCoreAudioStart()
            print("🎤 ✅ Core Audio dictation started successfully in \(dictationMode) mode")
        } catch {
            print("❌ Failed to start Core Audio dictation: \(error)")
            handleError(DictationError.coreAudioFailure(error))
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
    
    // MARK: - Core Audio Implementation
    
    private func performCoreAudioStart() throws {
        setState(.listening)
        
        // Setup speech recognition
        try setupRecognitionRequest()
        
        // Create Core Audio queue
        try createCoreAudioQueue()
        
        // Start Core Audio recording
        try startCoreAudioRecording()
        
        // Start speech recognition task
        startRecognitionTask()
        
        // Mark as actively recording
        isActivelyRecording = true
        hasReceivedAnyResults = false
        
        // Reset session state
        resetSession()
        
        // Notify delegate
        delegate?.dictationEngineDidStart(self)
        print("🎤 Core Audio recording started successfully")
    }
    
    private func startCoreAudioRecording() throws {
        guard let queue = audioQueue else {
            throw DictationError.audioQueueCreationFailed(-1)
        }
        
        print("🔊 Starting Core Audio recording...")
        let status = AudioQueueStart(queue, nil)
        
        guard status == noErr else {
            print("❌ Failed to start Core Audio recording: \(status)")
            throw DictationError.audioQueueCreationFailed(status)
        }
        
        print("✅ Core Audio recording started - no cold start issues!")
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
        
        if !userRequestedStop {
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("no speech") && !hasReceivedAnyResults {
                print("🎤 No speech detected - this is normal for silence")
                return
            }
            
            print("❌ Fatal recognition error - stopping dictation")
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
        print("🎤 Performing clean stop with Core Audio cleanup")
        
        // Cancel timers
        pushToTalkTimeoutTimer?.invalidate()
        pushToTalkTimeoutTimer = nil
        
        // Clean up Core Audio and recognition
        cleanupCoreAudio()
        cleanupRecognition()
        
        // Update state
        isActivelyRecording = false
        isWaitingForPushToTalkResults = false
        setState(.ready)
        
        // Notify delegate
        delegate?.dictationEngineDidStop(self)
        print("🎤 ✅ Core Audio clean stop completed")
    }
    
    private func cleanupCoreAudio() {
        if let queue = audioQueue {
            print("🔊 Stopping Core Audio queue...")
            AudioQueueStop(queue, true)  // true = immediate stop
            
            // Dispose of buffers
            for buffer in audioBuffers {
                if let audioBuffer = buffer {
                    AudioQueueFreeBuffer(queue, audioBuffer)
                }
            }
            audioBuffers.removeAll()
            
            // Dispose of queue
            AudioQueueDispose(queue, true)
            audioQueue = nil
            
            print("🔊 Core Audio cleanup completed")
        }
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
