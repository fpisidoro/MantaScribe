import Foundation
import Speech

/// Handles text processing operations for MantaScribe
/// Contains pure functions for text manipulation, analysis, and validation
class TextProcessor {
    
    // MARK: - Punctuation Processing
    
    /// Convert voice punctuation commands to actual punctuation marks
    /// Handles both standalone commands ("period") and phrase-ending commands ("sentence period")
    func processPunctuationCommands(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        let words = trimmed.split(separator: " ")
        
        // Handle standalone punctuation commands (single word)
        if words.count == 1 {
            switch lowercased {
            case "period", "full stop":
                return "."
            case "comma":
                return ","
            case "question mark":
                return "?"
            case "exclamation point", "exclamation mark":
                return "!"
            case "colon":
                return ":"
            case "semicolon":
                return ";"
            default:
                return text
            }
        }
        
        // Handle phrase-ending punctuation commands (multi-word)
        return processPhaseEndingPunctuation(trimmed, lowercased: lowercased)
    }
    
    /// Process punctuation commands that appear at the end of phrases
    private func processPhaseEndingPunctuation(_ text: String, lowercased: String) -> String {
        if lowercased.hasSuffix(" period") {
            let baseText = String(text.dropLast(7)) // Remove " period"
            return baseText + "."
        }
        
        if lowercased.hasSuffix(" comma") {
            let baseText = String(text.dropLast(6)) // Remove " comma"
            return baseText + ","
        }
        
        if lowercased.hasSuffix(" question mark") {
            let baseText = String(text.dropLast(14)) // Remove " question mark"
            return baseText + "?"
        }
        
        if lowercased.hasSuffix(" exclamation point") {
            let baseText = String(text.dropLast(18)) // Remove " exclamation point"
            return baseText + "!"
        }
        
        if lowercased.hasSuffix(" exclamation mark") {
            let baseText = String(text.dropLast(16)) // Remove " exclamation mark"
            return baseText + "!"
        }
        
        if lowercased.hasSuffix(" colon") {
            let baseText = String(text.dropLast(6)) // Remove " colon"
            return baseText + ":"
        }
        
        if lowercased.hasSuffix(" semicolon") {
            let baseText = String(text.dropLast(10)) // Remove " semicolon"
            return baseText + ";"
        }
        
        return text
    }
    
    // MARK: - Speech Recognition Analysis
    
    /// Calculate average confidence score from speech recognition transcription
    func calculateConfidence(from transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0.0 }
        
        let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(segments.count)
    }
    
    /// Analyze transcription quality for processing decisions
    func analyzeTranscriptionQuality(_ transcription: SFTranscription) -> TranscriptionQuality {
        let confidence = calculateConfidence(from: transcription)
        let text = transcription.formattedString
        
        if confidence > 0.9 && hasStrongPunctuationEnding(text) {
            return .veryHigh
        } else if confidence > 0.8 {
            return .high
        } else if hasStrongPunctuationEnding(text) {
            return .mediumWithPunctuation
        } else if isProbablyComplete(text) {
            return .mediumComplete
        } else {
            return .standard
        }
    }
    
    // MARK: - Text Similarity Detection
    
    /// Check if two texts are substantially similar to prevent duplicate processing
    func isSubstantiallySimilar(_ text1: String, to text2: String) -> Bool {
        if text1.isEmpty || text2.isEmpty {
            return false
        }
        
        let normalized1 = normalizeTextForComparison(text1)
        let normalized2 = normalizeTextForComparison(text2)
        
        // Exact match after normalization
        if normalized1 == normalized2 {
            return true
        }
        
        // Check substring containment for longer texts
        return isSubstringMatch(normalized1, normalized2)
    }
    
    /// Normalize text for comparison purposes
    private func normalizeTextForComparison(_ text: String) -> String {
        return text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    
    /// Check if one text is a substantial substring of another
    private func isSubstringMatch(_ text1: String, _ text2: String) -> Bool {
        let longer = text1.count > text2.count ? text1 : text2
        let shorter = text1.count > text2.count ? text2 : text1
        
        // Only consider it a match if the shorter text is substantial
        if shorter.count > 5 && longer.contains(shorter) {
            print("🔄 Similar text detected: '\(shorter)' in '\(longer)'")
            return true
        }
        
        return false
    }
    
    // MARK: - Text Completion Analysis
    
    /// Determine if text appears to be a complete thought or phrase
    func isProbablyComplete(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Medical/professional phrase patterns that often indicate completion
        let completionPatterns = [
            "years old", "was normal", "was abnormal", "follow up",
            "discharged", "admitted", "prescribed", "advised",
            "recommended", "working", "not working", "completed",
            "finished", "done", "negative", "positive", "unremarkable"
        ]
        
        // Check if text ends with any completion patterns
        for pattern in completionPatterns {
            if lowercased.hasSuffix(pattern) {
                return true
            }
        }
        
        // Check for common sentence structures that indicate completeness
        if lowercased.contains(" and ") && text.count > 20 {
            return true // Longer sentences with "and" are often complete thoughts
        }
        
        if lowercased.contains(" with ") && text.count > 15 {
            return true // Medical descriptions with "with" are often complete
        }
        
        return false
    }
    
    /// Check if text has strong punctuation ending
    private func hasStrongPunctuationEnding(_ text: String) -> Bool {
        return text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
    }
    
    // MARK: - Text Validation
    
    /// Validate text before processing
    func validateTextForProcessing(_ text: String) -> TextValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty {
            return .empty
        }
        
        if trimmed.count < 2 {
            return .tooShort
        }
        
        if trimmed.count > 1000 {
            return .tooLong
        }
        
        // Check for suspicious patterns that might indicate recognition errors
        if hasSuspiciousPatterns(trimmed) {
            return .suspicious
        }
        
        return .valid
    }
    
    /// Check for patterns that might indicate speech recognition errors
    private func hasSuspiciousPatterns(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Patterns that often indicate recognition errors
        let suspiciousPatterns = [
            "uh uh uh", "um um um", "ah ah ah",
            "the the the", "and and and", "a a a",
            "123456789", "abcdefgh"
        ]
        
        for pattern in suspiciousPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        // Check for excessive repetition of single characters
        let characterCounts = Dictionary(lowercased.compactMap { char in
            char.isLetter ? (char, 1) : nil
        }, uniquingKeysWith: +)
        
        for (_, count) in characterCounts {
            if count > text.count / 2 {
                return true // More than half the text is the same character
            }
        }
        
        return false
    }
    
    // MARK: - Processing Timeouts
    
    /// Determine optimal processing timeout based on text quality and content
    func determineProcessingTimeout(quality: TranscriptionQuality, text: String) -> TimeInterval {
        switch quality {
        case .veryHigh:
            return 0.3 // Very confident punctuation = fast flush
        case .high:
            return 0.8 // High confidence = medium speed
        case .mediumWithPunctuation:
            return 1.0 // Punctuation ending
        case .mediumComplete:
            return 1.2 // Seems complete based on content
        case .standard:
            return 1.5 // Default for uncertain text
        }
    }
}

// MARK: - Supporting Types

extension TextProcessor {
    
    enum TranscriptionQuality {
        case veryHigh           // >90% confidence + punctuation
        case high               // >80% confidence
        case mediumWithPunctuation  // Has punctuation ending
        case mediumComplete     // Appears complete based on content
        case standard           // Default quality
    }
    
    enum TextValidationResult {
        case valid
        case empty
        case tooShort
        case tooLong
        case suspicious
    }
}