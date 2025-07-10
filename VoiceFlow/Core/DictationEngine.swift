import Foundation
import Speech
import AVFoundation

/// Manages speech recognition, audio engine, and buffering for MantaScribe
/// Provides a clean interface for dictation functionality with intelligent buffering and timing
class DictationEngine: NSObject {
    
    // MARK: - Types
    
    enum DictationState {
        case idle
        case listening
        case processing
        case error
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
    
    // Buffer management
    private var bufferTimer: Timer?
    private var currentBuffer = ""
    private var hasProcessedBuffer = false
    private var isCurrentlyProcessing = false
    
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
    
    // MARK: - Public Interface
    
    /// Start dictation with enhanced medical recognition
    func startDictation() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            let error = DictationError.speechRecognizerUnavailable
            delegate?.dictationEngine(self, didEncounterError: error)
            return
        }
        
        print("🎙️ DictationEngine: Starting enhanced medical dictation...")
        
        setState(.listening)
        resetBuffer()
        setupRecognitionRequest()
        setupAudioEngine()
        startAudioEngine()
        startRecognitionTask()
        
        isRecording = true
        delegate?.dictationEngineDidStart(self)
    }
    
    /// Stop dictation and process any remaining buffer
    func stopDictation() {
        print("⏹️ DictationEngine: Stopping dictation")
        
        // Process any remaining buffer before stopping
        if shouldProcessRemainingBuffer() {
            print("📝 DictationEngine: Processing final buffer: '\(currentBuffer)'")
            flushBuffer()
        } else {
            print("✅ DictationEngine: No buffer to process or already handled")
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
        
        // Apply contextual strings for enhanced medical recognition
        applyContextualStrings(to: recognitionRequest)
    }
    
    private func applyContextualStrings(to request: SFSpeechAudioBufferRecognitionRequest) {
        let contextualStrings = VocabularyManager.shared.getContextualStrings()
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
            print("🎯 DictationEngine: Applied \(contextualStrings.count) contextual strings for enhanced medical recognition")
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
    
    // MARK: - Private Methods - Recognition Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString
        let confidence = calculateConfidence(from: result.bestTranscription)
        
        if result.isFinal {
            handleFinalResult(text: text, confidence: confidence)
        } else {
            handlePartialResult(text: text, confidence: confidence)
        }
    }
    
    private func handleFinalResult(text: String, confidence: Float) {
        DispatchQueue.main.async {
            self.bufferTimer?.invalidate()
            
            if !self.hasProcessedBuffer && !text.isEmpty {
                if self.isTextSimilarToRecent(text) {
                    print("🔄 DictationEngine: Final result skipped - too similar to recent text: '\(text)'")
                } else {
                    self.currentBuffer = text
                    print("🎯 DictationEngine: Final result - processing buffer: '\(text)'")
                    
                    self.bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            if !self.hasProcessedBuffer && !self.currentBuffer.isEmpty {
                                self.flushBuffer()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handlePartialResult(text: String, confidence: Float) {
        if !hasProcessedBuffer && !text.isEmpty {
            currentBuffer = text
            
            DispatchQueue.main.async {
                self.setState(.processing)
            }
            
            bufferTimer?.invalidate()
            
            let timeout = calculateBufferTimeout(text: text, confidence: confidence)
            
            bufferTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if !self.hasProcessedBuffer && self.isRecording && !self.currentBuffer.isEmpty {
                        self.flushBuffer()
                    }
                }
            }
        }
    }
    
    private func calculateBufferTimeout(text: String, confidence: Float) -> TimeInterval {
        let hasSentenceEnding = text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
        
        if confidence > 0.9 && hasSentenceEnding {
            return 0.3
        } else if confidence > 0.8 {
            return 0.8
        } else if hasSentenceEnding {
            return 1.0
        } else {
            return 1.5
        }
    }
    
    private func flushBuffer() {
        guard !currentBuffer.isEmpty && !hasProcessedBuffer && !isCurrentlyProcessing else {
            print("🚫 DictationEngine: Skipping flush - already processed or processing")
            return
        }
        
        isCurrentlyProcessing = true
        
        let textToProcess = currentBuffer.trimmingCharacters(in: .whitespaces)
        print("📝 DictationEngine: Processing buffer: '\(textToProcess)'")
        
        hasProcessedBuffer = true
        currentBuffer = ""
        bufferTimer?.invalidate()
        
        // Delegate the text processing to the app
        delegate?.dictationEngine(self, didProcessText: textToProcess)
        
        isCurrentlyProcessing = false
        
        // Reset buffer processing flag after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasProcessedBuffer = false
            if self.isRecording {
                self.setState(.listening)
            }
        }
    }
    
    // MARK: - Private Methods - Utilities
    
    private func calculateConfidence(from transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(segments.count)
    }
    
    private func isTextSimilarToRecent(_ text: String) -> Bool {
        // This would integrate with TextProcessor for similarity detection
        // For now, simplified implementation
        return false
    }
    
    private func shouldProcessRemainingBuffer() -> Bool {
        return !currentBuffer.isEmpty && !hasProcessedBuffer && !isCurrentlyProcessing
    }
    
    private func setState(_ newState: DictationState) {
        state = newState
        print("🎤 DictationEngine: State changed to \(newState)")
    }
    
    private func cleanupRecognition() {
        currentBuffer = ""
        hasProcessedBuffer = true
        isCurrentlyProcessing = false
        
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