import Cocoa
import Foundation

/// Manages target application selection, switching, and text insertion for MantaScribe
/// Handles app detection, focus management, and text sending with smart formatting
class AppTargetManager {
    
    // MARK: - Types
    
    enum TargetApp: String, CaseIterable {
        case textEdit = "TextEdit"
        case pages = "Pages"
        case notes = "Notes"
        case word = "Microsoft Word"
        
        var displayName: String { return self.rawValue }
        var bundleId: String {
            switch self {
            case .textEdit: return "com.apple.TextEdit"
            case .pages: return "com.apple.iWork.Pages"
            case .notes: return "com.apple.Notes"
            case .word: return "com.microsoft.Word"
            }
        }
    }
    
    enum AppSwitchResult {
        case success
        case appNotFound
        case launchFailed(Error)
        case focusRestoreFailed
    }
    
    // MARK: - Properties
    
    private(set) var selectedTargetApp: TargetApp = .textEdit
    
    // Timing constants
    private let runningAppDelay: TimeInterval = 0.2
    private let launchAppDelay: TimeInterval = 1.0
    private let focusRestoreDelay: TimeInterval = 0.1
    private let statusUpdateDelay: TimeInterval = 0.05
    
    // MARK: - Public Interface
    
    /// Set the currently selected target app
    func setTargetApp(_ app: TargetApp) {
        selectedTargetApp = app
        print("🎯 Target changed to: \(app.displayName)")
    }
    
    /// Send text to the currently selected target app with smart formatting
    func sendText(_ text: String, 
                  shouldCapitalize: Bool,
                  needsLeadingSpace: Bool,
                  needsTrailingSpace: Bool,
                  completion: @escaping (AppSwitchResult) -> Void) {
        
        let isPunctuation = [".", ",", "?", "!", ":", ";"].contains(text)
        
        print("🎯 Sending: '\(text)' to \(selectedTargetApp.displayName)")
        print("📝 Formatting: capitalize=\(shouldCapitalize), leadSpace=\(needsLeadingSpace), trailSpace=\(needsTrailingSpace)")
        
        // Remember the original app for focus restoration
        let originalApp = NSWorkspace.shared.frontmostApplication
        print("📱 Original app: \(originalApp?.localizedName ?? "Unknown")")
        
        // Apply smart formatting
        let finalText = applySmartFormatting(to: text, 
                                           shouldCapitalize: shouldCapitalize,
                                           isPunctuation: isPunctuation)
        
        let textWithSpacing = applySmartSpacing(to: finalText,
                                              needsLeadingSpace: needsLeadingSpace,
                                              needsTrailingSpace: needsTrailingSpace)
        
        print("📝 Final formatted text: '\(textWithSpacing)'")
        
        // Check if target app is running
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: selectedTargetApp.bundleId).first {
            handleRunningApp(app, text: textWithSpacing, originalApp: originalApp, completion: completion)
        } else {
            handleAppLaunch(text: textWithSpacing, originalApp: originalApp, completion: completion)
        }
    }
    
    /// Check if the target app is currently running
    func isTargetAppRunning() -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: selectedTargetApp.bundleId).first != nil
    }
    
    /// Get all available target apps
    func getAvailableApps() -> [TargetApp] {
        return TargetApp.allCases
    }
    
    // MARK: - Private Methods - App Management
    
    private func handleRunningApp(_ app: NSRunningApplication,
                                text: String,
                                originalApp: NSRunningApplication?,
                                completion: @escaping (AppSwitchResult) -> Void) {
        
        print("✅ Found running app: \(app.localizedName ?? selectedTargetApp.bundleId)")
        
        // Activate the target app
        app.activate(options: [.activateIgnoringOtherApps])
        print("✅ App activation called")
        
        // Wait for app to become active, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + runningAppDelay) {
            self.performTextInsertion(text: text, originalApp: originalApp, completion: completion)
        }
    }
    
    private func handleAppLaunch(text: String,
                               originalApp: NSRunningApplication?,
                               completion: @escaping (AppSwitchResult) -> Void) {
        
        print("🚀 Launching app: \(selectedTargetApp.displayName)")
        
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: selectedTargetApp.bundleId) else {
            print("❌ Could not find app with bundle ID: \(selectedTargetApp.bundleId)")
            completion(.appNotFound)
            return
        }
        
        do {
            try NSWorkspace.shared.launchApplication(at: appURL, options: [.default], configuration: [:])
            print("✅ App launch initiated")
            
            // Wait longer for app launch
            DispatchQueue.main.asyncAfter(deadline: .now() + launchAppDelay) {
                self.performTextInsertion(text: text, originalApp: originalApp, completion: completion)
            }
        } catch {
            print("❌ Failed to launch \(selectedTargetApp.displayName): \(error)")
            completion(.launchFailed(error))
        }
    }
    
    private func performTextInsertion(text: String,
                                    originalApp: NSRunningApplication?,
                                    completion: @escaping (AppSwitchResult) -> Void) {
        
        print("🟢 Performing text insertion")
        
        // Put text in clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Paste immediately
        simulatePaste()
        
        // Switch back to original app after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + focusRestoreDelay) {
            self.restoreFocus(to: originalApp, completion: completion)
        }
    }
    
    private func restoreFocus(to originalApp: NSRunningApplication?,
                            completion: @escaping (AppSwitchResult) -> Void) {
        
        if let originalApp = originalApp {
            print("🔄 Switching back to: \(originalApp.localizedName ?? "Unknown")")
            originalApp.activate(options: [.activateIgnoringOtherApps])
            
            // Update status after switching back
            DispatchQueue.main.asyncAfter(deadline: .now() + statusUpdateDelay) {
                completion(.success)
            }
        } else {
            print("⚠️ No original app to switch back to")
            DispatchQueue.main.asyncAfter(deadline: .now() + statusUpdateDelay) {
                completion(.success)
            }
        }
    }
    
    // MARK: - Private Methods - Text Formatting
    
    private func applySmartFormatting(to text: String, shouldCapitalize: Bool, isPunctuation: Bool) -> String {
        // Don't modify punctuation
        if isPunctuation {
            return text
        }
        
        if shouldCapitalize {
            return capitalizeFirstWord(text)
        } else {
            return makeFirstWordLowercase(text)
        }
    }
    
    private func applySmartSpacing(to text: String, needsLeadingSpace: Bool, needsTrailingSpace: Bool) -> String {
        var result = text
        
        if needsLeadingSpace {
            result = " " + result
        }
        
        if needsTrailingSpace {
            result = result + " "
        }
        
        return result
    }
    
    private func capitalizeFirstWord(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let firstChar = String(text.prefix(1)).uppercased()
        return firstChar + String(text.dropFirst())
    }
    
    private func makeFirstWordLowercase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        let words = text.split(separator: " ", maxSplits: 1)
        guard let firstWord = words.first else { return text }
        
        let firstWordString = String(firstWord)
        let lowercaseFirst = firstWordString.lowercased()
        
        if words.count > 1 {
            let remainder = String(words[1])
            return lowercaseFirst + " " + remainder
        } else {
            return lowercaseFirst
        }
    }
    
    // MARK: - Private Methods - System Integration
    
    private func simulatePaste() {
        print("📋 Executing paste command")
        
        let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        
        cmdVDown?.flags = .maskCommand
        cmdVUp?.flags = .maskCommand
        
        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
    }
}