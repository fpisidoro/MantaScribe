import Cocoa
import Foundation

/// Manages Right Option key detection and dual-mode hotkey functionality
/// Supports both toggle mode (quick tap) and push-and-hold mode
class HotkeyManager {
    
    // MARK: - Types
    
    enum HotkeyAction {
        case startDictation
        case stopDictation
    }
    
    // MARK: - Protocol
    
    weak var delegate: HotkeyManagerDelegate?
    
    // MARK: - Properties
    
    private var rightOptionPressed = false
    private var keyPressStartTime: Date?
    private var isRecording = false // Track recording state for intelligent decision making
    
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
        print("🎤 RIGHT OPTION PRESSED \(sourceDescription) - toggling dictation")
        
        // Add small delay for background apps to ensure event is fully processed
        DispatchQueue.main.asyncAfter(deadline: .now() + eventProcessingDelay) {
            self.delegate?.hotkeyManager(self, didDetectToggle: .startDictation)
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
        
        print("🔍 DEBUG: Right Option released \(sourceDescription) - held for \(String(format: "%.2f", holdTime)) seconds")
        
        // Determine action based on hold time and current recording state
        let action = determineReleaseAction(holdTime: holdTime)
        
        switch action {
        case .pressAndHold:
            print("🎤 Detected press-and-hold pattern - stopping dictation")
            DispatchQueue.main.asyncAfter(deadline: .now() + eventProcessingDelay) {
                if self.isRecording {
                    self.delegate?.hotkeyManager(self, didDetectToggle: .stopDictation)
                }
            }
            
        case .quickTap:
            print("🎤 Quick tap detected (held for \(String(format: "%.2f", holdTime))s) - toggle mode, ignoring release")
            
        case .tooLong:
            print("🎤 Hold time too long (\(String(format: "%.2f", holdTime))s) - ignoring")
        }
        
        keyPressStartTime = nil
    }
    
    private func determineReleaseAction(holdTime: TimeInterval) -> ReleaseAction {
        // Only treat as press-and-hold if:
        // 1. Key was held for at least the threshold time
        // 2. Hold time is reasonable (not accidental long hold)
        // 3. We're currently recording (otherwise it doesn't make sense to stop)
        
        if holdTime >= holdThresholdSeconds && holdTime < maxHoldTimeSeconds && isRecording {
            return .pressAndHold
        } else if holdTime >= maxHoldTimeSeconds {
            return .tooLong
        } else {
            return .quickTap
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
        case pressAndHold    // Stop dictation
        case quickTap        // Ignore (toggle mode)
        case tooLong         // Ignore (probably accidental)
    }
}

// MARK: - Delegate Protocol

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: HotkeyManager, didDetectToggle action: HotkeyManager.HotkeyAction)
}