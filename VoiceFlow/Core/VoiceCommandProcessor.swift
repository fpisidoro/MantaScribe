import Foundation
import Cocoa

/// Processes voice commands and distinguishes them from regular dictation text
/// Provides extensible architecture for adding new voice commands
class VoiceCommandProcessor {
    
    // MARK: - Types
    
    enum CommandResult {
        case commandExecuted(String)    // Command found and executed
        case textToSend(String)         // Not a command, send as regular text
        case commandNotRecognized       // Command syntax detected but unknown command
    }
    
    enum VoiceCommand {
        case scratchThat(count: Int)    // Undo last dictation(s)
        case scratchAll                 // Undo all recent dictations
        
        // Future commands can be added here:
        // case nextField
        // case previousField
        // case insertTemplate(String)
        // case switchToApp(String)
    }
    
    // MARK: - Properties
    
    weak var delegate: VoiceCommandProcessorDelegate?
    
    // App targeting for commands (injected dependency)
    weak var appTargetManager: AppTargetManager?
    
    // Command patterns (case-insensitive matching)
    private let commandPatterns: [String: VoiceCommand] = [
        "scratch that": .scratchThat(count: 1),
        "scratch that scratch that": .scratchThat(count: 2),
        "scratch that scratch that scratch that": .scratchThat(count: 3),
        "undo that": .scratchThat(count: 1),
        "undo dictation": .scratchThat(count: 1),
        "delete that": .scratchThat(count: 1),
        "scratch all": .scratchAll,
        "undo all": .scratchAll
    ]
    
    // MARK: - Public Interface
    
    /// Set the app target manager for proper app switching during commands
    func setAppTargetManager(_ manager: AppTargetManager) {
        appTargetManager = manager
    }
    
    /// Process incoming text and determine if it's a command or regular text
    func processText(_ text: String) -> CommandResult {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedText.isEmpty else {
            return .textToSend("")
        }
        
        print("🎤 VoiceCommandProcessor: Processing '\(trimmedText)'")
        
        // Check for voice commands (case-insensitive)
        if let command = detectCommand(in: trimmedText) {
            let result = executeCommand(command)
            print("🎤 VoiceCommandProcessor: Executed command - \(result)")
            return .commandExecuted(result)
        }
        
        // Not a command, return as regular text
        print("🎤 VoiceCommandProcessor: No command detected - returning as text")
        return .textToSend(trimmedText)
    }
    
    /// Check if text matches any known command patterns
    func isCommand(_ text: String) -> Bool {
        return detectCommand(in: text) != nil
    }
    
    /// Get list of available commands for help/debugging
    func getAvailableCommands() -> [String] {
        return Array(commandPatterns.keys).sorted()
    }
    
    // MARK: - Private Methods - Command Detection
    
    private func detectCommand(in text: String) -> VoiceCommand? {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Direct pattern matching
        if let command = commandPatterns[normalizedText] {
            return command
        }
        
        // Pattern variations and fuzzy matching
        return detectCommandVariations(normalizedText)
    }
    
    private func detectCommandVariations(_ text: String) -> VoiceCommand? {
        // Handle variations in "scratch that" repetitions
        if text.starts(with: "scratch that") {
            let scratchCount = countScratchThatOccurrences(text)
            if scratchCount > 0 {
                return .scratchThat(count: min(scratchCount, 5)) // Cap at 5 undos
            }
        }
        
        // Handle "undo" variations
        if text.starts(with: "undo that") || text == "undo" {
            return .scratchThat(count: 1)
        }
        
        // Handle "delete" variations
        if text.starts(with: "delete that") || text == "delete" {
            return .scratchThat(count: 1)
        }
        
        return nil
    }
    
    private func countScratchThatOccurrences(_ text: String) -> Int {
        let components = text.components(separatedBy: "scratch that")
        return components.count - 1
    }
    
    // MARK: - Private Methods - Command Execution
    
    private func executeCommand(_ command: VoiceCommand) -> String {
        switch command {
        case .scratchThat(let count):
            return executeScratchThat(count: count)
            
        case .scratchAll:
            return executeScratchAll()
        }
    }
    
    private func executeScratchThat(count: Int) -> String {
        print("🎤 Executing scratch that (count: \(count))")
        
        // Send undo commands to the target app (with proper app switching)
        sendUndoToTargetApp(count: count)
        
        // Notify delegate about the undo operation
        delegate?.voiceCommandProcessor(self, didExecuteUndo: count)
        
        let countText = count == 1 ? "last dictation" : "last \(count) dictations"
        return "Undid \(countText)"
    }
    
    private func executeScratchAll() -> String {
        print("🎤 Executing scratch all")
        
        // For "scratch all", we'll do multiple undos (configurable)
        let maxUndos = 10 // Reasonable limit
        
        sendUndoToTargetApp(count: maxUndos)
        
        delegate?.voiceCommandProcessor(self, didExecuteUndo: maxUndos)
        
        return "Undid all recent dictations"
    }
    
    // MARK: - Private Methods - System Integration
    
    private func sendUndoToTargetApp(count: Int) {
        guard let appTargetManager = appTargetManager else {
            print("❌ No AppTargetManager - sending undo to current app")
            // Fallback: send to currently active app
            for _ in 1...count {
                sendUndoCommand()
                if count > 1 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
            return
        }
        
        print("🎯 Sending \(count) undo command(s) to target app")
        
        // Remember the original app for focus restoration
        let originalApp = NSWorkspace.shared.frontmostApplication
        
        // Get the target app and activate it
        let targetApp = appTargetManager.selectedTargetApp
        
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetApp.bundleId).first {
            // Activate target app
            app.activate(options: [.activateIgnoringOtherApps])
            
            // Small delay to ensure app becomes active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Send undo commands
                for i in 1...count {
                    self.sendUndoCommand()
                    if i < count {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                
                // Switch back to original app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let originalApp = originalApp {
                        originalApp.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            }
        } else {
            print("❌ Target app not running - cannot send undo")
        }
    }
    
    private func sendUndoCommand() {
        // Send Cmd+Z to the currently active application
        let cmdZ = CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: true)
        let cmdZUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: false)
        
        cmdZ?.flags = .maskCommand
        cmdZUp?.flags = .maskCommand
        
        cmdZ?.post(tap: .cghidEventTap)
        cmdZUp?.post(tap: .cghidEventTap)
        
        print("🎤 VoiceCommandProcessor: Sent Cmd+Z")
    }
    
    // MARK: - Future Extension Points
    
    // These methods provide hooks for future command categories
    
    private func executeNavigationCommand(_ command: String) -> String {
        // Future: Handle "next field", "previous field", etc.
        return "Navigation command: \(command)"
    }
    
    private func executeTemplateCommand(_ template: String) -> String {
        // Future: Handle template insertions
        return "Inserted template: \(template)"
    }
    
    private func executeAppControlCommand(_ command: String) -> String {
        // Future: Handle app switching, mode changes, etc.
        return "App control: \(command)"
    }
    
    // MARK: - Debugging and Diagnostics
    
    /// Log current command processor state for debugging
    func logStatus() {
        print("🎤 VoiceCommandProcessor Status:")
        print("   Available commands: \(commandPatterns.count)")
        print("   Commands: \(getAvailableCommands().joined(separator: ", "))")
    }
    
    /// Test command recognition without execution
    func testCommand(_ text: String) -> String {
        if let command = detectCommand(in: text) {
            return "Recognized command: \(command)"
        } else {
            return "No command recognized in: '\(text)'"
        }
    }
}

// MARK: - Delegate Protocol

protocol VoiceCommandProcessorDelegate: AnyObject {
    /// Called when an undo command is executed
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didExecuteUndo count: Int)
    
    /// Called when a navigation command is executed (future)
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didExecuteNavigation command: String)
    
    /// Called when an unknown command is attempted (future)
    func voiceCommandProcessor(_ processor: VoiceCommandProcessor, didEncounterUnknownCommand text: String)
}
