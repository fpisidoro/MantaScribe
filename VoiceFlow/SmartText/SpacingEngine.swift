import Foundation

/// Handles intelligent spacing decisions for professional text output
/// Prevents double spaces, handles punctuation spacing, and manages insertion contexts
class SpacingEngine {
    
    // MARK: - Types
    
    struct SpacingDecision {
        let needsLeadingSpace: Bool
        let needsTrailingSpace: Bool
        let reason: String
    }
    
    enum InsertionContext {
        case normal                 // Regular text insertion
        case afterPunctuation     // After . , ; : etc
        case afterWhitespace      // After space or newline
        case midSentenceInsertion // Inserting in middle of sentence
        case bracketInsertion     // Inserting after opening bracket
        case unknown              // Cannot determine context
    }
    
    // MARK: - Properties
    
    private let punctuationMarks: Set<String> = [".", ",", "?", "!", ":", ";"]
    private let openingBrackets: Set<Character> = ["(", "[", "{"]
    private let closingBrackets: Set<Character> = [")", "]", "}"]
    
    // MARK: - Public Interface
    
    /// Determine spacing needs based on detected characters and text type
    func determineSpacing(for text: String, 
                         detectedChars: String, 
                         isPunctuation: Bool) -> SpacingDecision {
        
        print("📝 Analyzing spacing for: '\(text)' with context: '\(detectedChars.debugDescription)'")
        
        // Punctuation never needs spacing
        if isPunctuation {
            let decision = SpacingDecision(needsLeadingSpace: false, 
                                         needsTrailingSpace: false,
                                         reason: "Punctuation detected - no spacing needed")
            print("📝 Spacing decision: \(decision.reason)")
            return decision
        }
        
        // If we couldn't detect previous chars, default to adding space
        if detectedChars.isEmpty {
            let decision = SpacingDecision(needsLeadingSpace: true, 
                                         needsTrailingSpace: false,
                                         reason: "No context detected - adding leading space")
            print("📝 Spacing decision: \(decision.reason)")
            return decision
        }
        
        let context = analyzeInsertionContext(detectedChars)
        let decision = makeSpacingDecision(for: context, detectedChars: detectedChars)
        
        print("📝 Spacing decision: leading=\(decision.needsLeadingSpace), trailing=\(decision.needsTrailingSpace) (\(decision.reason))")
        return decision
    }
    
    // MARK: - Private Methods - Context Analysis
    
    private func analyzeInsertionContext(_ chars: String) -> InsertionContext {
        guard !chars.isEmpty else { return .unknown }
        
        // Check for specific patterns in the last 2 characters
        if chars.count >= 2 {
            let secondToLast = chars[chars.index(chars.endIndex, offsetBy: -2)]
            let lastChar = chars.last!
            
            // Pattern: [space + opening bracket] - special insertion context
            if secondToLast.isWhitespace && openingBrackets.contains(lastChar) {
                return .bracketInsertion
            }
            
            // Pattern: [letter + space] - likely mid-sentence insertion
            if secondToLast.isLetter && lastChar.isWhitespace {
                return .midSentenceInsertion
            }
        }
        
        let lastChar = chars.last!
        
        // Check last character type
        if punctuationMarks.contains(String(lastChar)) {
            return .afterPunctuation
        }
        
        if lastChar.isWhitespace || lastChar.isNewline {
            return .afterWhitespace
        }
        
        return .normal
    }
    
    private func makeSpacingDecision(for context: InsertionContext, 
                                   detectedChars: String) -> SpacingDecision {
        
        switch context {
        case .afterPunctuation:
            return SpacingDecision(needsLeadingSpace: true, 
                                 needsTrailingSpace: false,
                                 reason: "After punctuation - adding leading space")
            
        case .afterWhitespace:
            return SpacingDecision(needsLeadingSpace: false, 
                                 needsTrailingSpace: false,
                                 reason: "After whitespace - no additional spacing")
            
        case .midSentenceInsertion:
            return SpacingDecision(needsLeadingSpace: false, 
                                 needsTrailingSpace: true,
                                 reason: "Mid-sentence insertion - adding trailing space")
            
        case .bracketInsertion:
            return SpacingDecision(needsLeadingSpace: false, 
                                 needsTrailingSpace: true,
                                 reason: "Bracket insertion - adding trailing space")
            
        case .normal:
            let lastChar = detectedChars.last!
            if lastChar.isLetter || lastChar.isNumber {
                return SpacingDecision(needsLeadingSpace: true, 
                                     needsTrailingSpace: false,
                                     reason: "After normal text - adding leading space")
            } else {
                return SpacingDecision(needsLeadingSpace: false, 
                                     needsTrailingSpace: false,
                                     reason: "After special character - no spacing")
            }
            
        case .unknown:
            return SpacingDecision(needsLeadingSpace: true, 
                                 needsTrailingSpace: false,
                                 reason: "Unknown context - default leading space")
        }
    }
    
    // MARK: - Public Utilities
    
    /// Check if text appears to be punctuation
    func isPunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return punctuationMarks.contains(trimmed)
    }
    
    /// Clean up spacing in text (remove double spaces, fix punctuation spacing)
    func cleanSpacing(in text: String) -> String {
        var result = text
        
        // Remove double spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Fix spacing before punctuation
        for punct in punctuationMarks {
            result = result.replacingOccurrences(of: " \(punct)", with: punct)
        }
        
        // Fix spacing after opening brackets
        for bracket in openingBrackets {
            result = result.replacingOccurrences(of: "\(bracket) ", with: String(bracket))
        }
        
        // Fix spacing before closing brackets
        for bracket in closingBrackets {
            result = result.replacingOccurrences(of: " \(bracket)", with: String(bracket))
        }
        
        return result
    }
    
    /// Analyze spacing patterns in existing text for learning
    func analyzeTextSpacing(_ text: String) -> [String: Int] {
        var patterns: [String: Int] = [:]
        
        // Count spacing patterns around punctuation
        for punct in punctuationMarks {
            let beforePattern = " \(punct)"
            let afterPattern = "\(punct) "
            
            patterns["space_before_\(punct)"] = text.components(separatedBy: beforePattern).count - 1
            patterns["space_after_\(punct)"] = text.components(separatedBy: afterPattern).count - 1
        }
        
        // Count double spaces
        patterns["double_spaces"] = text.components(separatedBy: "  ").count - 1
        
        return patterns
    }
    
    /// Validate spacing in text and suggest improvements
    func validateSpacing(_ text: String) -> [String] {
        var issues: [String] = []
        
        // Check for double spaces
        if text.contains("  ") {
            issues.append("Contains double spaces")
        }
        
        // Check for spaces before punctuation
        for punct in punctuationMarks {
            if text.contains(" \(punct)") {
                issues.append("Space before \(punct)")
            }
        }
        
        // Check for missing spaces after punctuation (but not at end)
        for punct in punctuationMarks where punct != "." {
            let pattern = "\(punct)[a-zA-Z]"
            if text.range(of: pattern, options: .regularExpression) != nil {
                issues.append("Missing space after \(punct)")
            }
        }
        
        return issues
    }
}