import Cocoa
import Foundation

/// Manages Right Option key detection with clean mode communication to DictationEngine
/// Determines and communicates toggle vs push-to-talk mode for optimized processing
class HotkeyManager {
    
    // MARK: - Types
    
    enum HotkeyAction {
        case startDictation(mode: DictationMode)
        case stopDictation
    }
    
    typealias DictationMode = DictationEngine.DictationMode
    
    // MARK: - Protocol
    
    weak var delegate: HotkeyManagerDelegate?
    
    // MARK: - Properties
    
    private var rightOptionPressed = false
    private var keyPressStartTime: Date?
    private var isRecording = false
    private var currentMode: DictationMode = .toggle
    
    // Constants
    private let rightOptionRawFlag: UInt = 524608
    private let holdThresholdSeconds: TimeInterval = 0.5
    private let maxHoldTimeSeconds: TimeInterval = 10.0
    private let eventProcessingDelay: TimeInterval = 0.05
    
    // MARK: - Initialization
    
    init() {
        setupEventMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Update the recording state so hotkey manager can make intelligent decisions
    func updateRecordingState(_ recording: Bool) {
        isRecording = recording
    }
    
    /// Get the current dictation mode for external components
    var dictationMode: DictationMode {
        return currentMode
    }
    
    // MARK: - Private Methods
    
    private func setupEventMonitoring() {
        setupGlobalEventMonitoring()
        setupLocalEventMonitoring()
    }
    
    private func setupGlobalEventMonitoring() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: .global)
        }
    }
    
    private func setupLocalEventMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event, source: .local)
            return event // Don't consume local events
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent, source: EventSource) {
        let rawFlags = event.modifierFlags.rawValue
        
        if rawFlags == rightOptionRawFlag {
            handleRightOptionPressed(source: source)
        } else if rightOptionPressed && rawFlags != rightOptionRawFlag {
            handleRightOptionReleased(source: source)
        }
    }
    
    private func handleRightOptionPressed(source: EventSource) {
        guard !rightOptionPressed else { return }
        
        rightOptionPressed = true
        keyPressStartTime = Date()
        
        let sourceDescription = source == .global ? "FROM BACKGROUND" : "LOCALLY"
        print("🎤 RIGHT OPTION PRESSED \(sourceDescription)")
        
        // Always start in toggle mode initially
        // Mode determination happens on release
        currentMode = .toggle
        
        // Add small delay for background apps to ensure event is fully processed
        DispatchQueue.main.asyncAfter(deadline: .now() + eventProcessingDelay) {
            self.delegate?.hotkeyManager(self, didDetectAction: .startDictation(mode: .toggle))
        }
    }
    
    private func handleRightOptionReleased(source: EventSource) {
        guard rightOptionPressed else { return }
        
        rightOptionPressed = false
        
        guard let startTime = keyPressStartTime else {
            keyPressStartTime = nil
            return
        }
        
        let holdTime = Date().timeIntervalSince(startTime)
        let sourceDescription = source == .global ? "from background" : "locally"
        
        print("🔍 Right Option released \(sourceDescription) - held for \(String(format: "%.2f", holdTime)) seconds")
        
        // Determine what action to take based on hold time and recording state
        let action = determineReleaseAction(holdTime: holdTime)
        
        switch action {
        case .pushAndHoldStop:
            currentMode = .pushToTalk
            print("🎤 Push-to-talk mode detected - stopping dictation")
            DispatchQueue.main.asyncAfter(deadline: .now() + eventProcessingDelay) {
                if self.isRecording {
                    self.delegate?.hotkeyManager(self, didDetectAction: .stopDictation)
                }
            }
            
        case .toggleModeIgnore:
            currentMode = .toggle
            print("🎤 Toggle mode - ignoring release (held for \(String(format: "%.2f", holdTime))s)")
            
        case .invalidHold:
            print("🎤 Invalid hold time (\(String(format: "%.2f", holdTime))s) - ignoring")
        }
        
        keyPressStartTime = nil
    }
    
    private func determineReleaseAction(holdTime: TimeInterval) -> ReleaseAction {
        // Clean logic for mode determination:
        // - Quick tap (< 0.5s): Toggle mode, ignore release
        // - Hold (0.5s - 10s) while recording: Push-to-talk mode, stop dictation
        // - Hold too long (> 10s): Invalid, ignore
        
        if holdTime >= holdThresholdSeconds && holdTime < maxHoldTimeSeconds && isRecording {
            return .pushAndHoldStop
        } else if holdTime >= maxHoldTimeSeconds {
            return .invalidHold
        } else {
            return .toggleModeIgnore
        }
    }
}

// MARK: - Supporting Types

extension HotkeyManager {
    
    private enum EventSource {
        case global
        case local
    }
    
    private enum ReleaseAction {
        case pushAndHoldStop    // Push-to-talk: stop dictation
        case toggleModeIgnore   // Toggle mode: ignore release
        case invalidHold        // Too long: ignore
    }
}

// MARK: - Delegate Protocol

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: HotkeyManager, didDetectAction action: HotkeyManager.HotkeyAction)
}
