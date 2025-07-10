import Cocoa
import Foundation

/// Detects cursor context by analyzing characters before the cursor position
/// Uses clipboard-based method to safely determine text context without accessibility permissions
class CursorDetector {
    
    // MARK: - Types
    
    enum CursorContext {
        case startOfDocument        // Empty or beginning of text
        case afterSentencePunctuation  // After . ! ?
        case afterClausePunctuation    // After : ;
        case afterWhitespace          // After space, tab, newline
        case afterDoubleNewline       // After paragraph break
        case afterNormalText          // After regular characters
        case unknown                  // Detection failed
        
        var shouldCapitalize: Bool {
            switch self {
            case .startOfDocument, .afterSentencePunctuation, .afterDoubleNewline:
                return true
            case .afterClausePunctuation, .afterWhitespace, .afterNormalText, .unknown:
                return false
            }
        }
    }
    
    struct DetectionResult {
        let context: CursorContext
        let detectedChars: String
        let success: Bool
        
        static func failed() -> DetectionResult {
            return DetectionResult(context: .unknown, detectedChars: "", success: false)
        }
        
        static func success(context: CursorContext, chars: String) -> DetectionResult {
            return DetectionResult(context: context, detectedChars: chars, success: true)
        }
    }
    
    // MARK: - Properties
    
    private let detectionDelay: TimeInterval = 0.02
    private let maxDetectionLength = 2
    
    // MARK: - Public Interface
    
    /// Detect cursor context by analyzing characters before cursor position
    func detectCursorContext() -> DetectionResult {
        print("🔍 Starting cursor context detection...")
        
        let previous2Chars = extractPreviousCharacters()
        guard !previous2Chars.isEmpty else {
            print("📋 Empty detection - start of document")
            return .success(context: .startOfDocument, chars: "")
        }
        
        let context = analyzeCursorContext(previous2Chars)
        print("📋 Context detected: \(context) from chars: '\(previous2Chars.debugDescription)'")
        
        return .success(context: context, chars: previous2Chars)
    }
    
    // MARK: - Private Methods - Character Extraction
    
    private func extractPreviousCharacters() -> String {
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        
        // Perform character extraction
        let extractedChars = performCharacterExtraction()
        
        // Restore original clipboard
        pasteboard.clearContents()
        if let original = originalClipboard {
            pasteboard.setString(original, forType: .string)
        }
        
        // Safety: Ensure we only got expected amount of characters
        let safeChars = String(extractedChars.suffix(maxDetectionLength))
        print("📋 Extracted chars: '\(safeChars.debugDescription)' (length: \(safeChars.count))")
        
        return safeChars
    }
    
    private func performCharacterExtraction() -> String {
        // Move cursor left 2 positions
        moveCursorLeft(positions: 2)
        
        // Select exactly 2 characters to the right
        selectCharactersRight(count: 2)
        
        // Copy selection
        copySelection()
        
        // Get the copied text
        let pasteboard = NSPasteboard.general
        let extractedText = pasteboard.string(forType: .string) ?? ""
        
        // Restore cursor position (move right to original position)
        restoreCursorPosition()
        
        return extractedText
    }
    
    // MARK: - Private Methods - Cursor Manipulation
    
    private func moveCursorLeft(positions: Int) {
        let leftKey = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: true)
        let leftKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: false)
        
        for _ in 0..<positions {
            leftKey?.post(tap: .cghidEventTap)
            leftKeyUp?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: detectionDelay)
        }
    }
    
    private func selectCharactersRight(count: Int) {
        let rightKey = CGEvent(keyboardEventSource: nil, virtualKey: 0x7C, keyDown: true)
        let rightKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x7C, keyDown: false)
        
        for _ in 0..<count {
            rightKey?.flags = .maskShift
            rightKeyUp?.flags = .maskShift
            rightKey?.post(tap: .cghidEventTap)
            rightKeyUp?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: detectionDelay)
        }
    }
    
    private func copySelection() {
        let cmdC = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true)
        let cmdCUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false)
        cmdC?.flags = .maskCommand
        cmdCUp?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)
        cmdCUp?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: detectionDelay)
    }
    
    private func restoreCursorPosition() {
        let rightKey = CGEvent(keyboardEventSource: nil, virtualKey: 0x7C, keyDown: true)
        let rightKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x7C, keyDown: false)
        
        rightKey?.flags = []
        rightKeyUp?.flags = []
        rightKey?.post(tap: .cghidEventTap)
        rightKeyUp?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: detectionDelay)
    }
    
    // MARK: - Private Methods - Context Analysis
    
    private func analyzeCursorContext(_ chars: String) -> CursorContext {
        if chars.isEmpty {
            return .startOfDocument
        }
        
        // Check for sentence-ending punctuation
        if chars.contains(where: { "!?.".contains($0) }) {
            return .afterSentencePunctuation
        }
        
        // Check for clause punctuation (don't capitalize after these)
        if chars.contains(where: { ":;".contains($0) }) {
            return .afterClausePunctuation
        }
        
        // Check for paragraph breaks
        if hasDoubleNewlinePattern(chars) {
            return .afterDoubleNewline
        }
        
        // Check for single newline (treat as paragraph break for medical notes)
        if chars.hasSuffix("\n") {
            return .afterDoubleNewline  // Treat single newline as new paragraph in medical context
        }
        
        // Check for double spaces (often indicates new sentence)
        if chars == "  " {
            return .afterDoubleNewline
        }
        
        // Check for whitespace
        if chars.last?.isWhitespace == true || chars.last?.isNewline == true {
            return .afterWhitespace
        }
        
        // Default to normal text
        return .afterNormalText
    }
    
    private func hasDoubleNewlinePattern(_ chars: String) -> Bool {
        return chars.contains("\n\n") || 
               chars.contains("\n ") || 
               chars.contains(" \n")
    }
    
    // MARK: - Public Utilities
    
    /// Quick check if cursor is likely at start of document
    func isLikelyStartOfDocument() -> Bool {
        let result = detectCursorContext()
        return result.context == .startOfDocument
    }
    
    /// Quick check if cursor is after sentence-ending punctuation
    func isAfterSentenceEnd() -> Bool {
        let result = detectCursorContext()
        return result.context == .afterSentencePunctuation || result.context == .afterDoubleNewline
    }
}