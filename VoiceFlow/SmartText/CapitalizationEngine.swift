import Foundation

/// Handles smart capitalization decisions based on cursor context and text content
/// Preserves medical terminology and applies professional formatting rules
class CapitalizationEngine {
    
    // MARK: - Types
    
    struct CapitalizationResult {
        let text: String
        let wasModified: Bool
        let reason: String
    }
    
    // MARK: - Properties
    
    private let medicalTerms: Set<String> = [
        "ct", "mri", "ecg", "ekg", "covid", "bp", "hr", "rr", 
        "icu", "er", "cpr", "dnr", "iv", "po", "prn", "bid", 
        "tid", "qid", "ent", "copd", "chf", "cbc", "bmp", "cmp"
    ]
    
    private let commonMidSentenceWords: Set<String> = [
        "for", "but", "and", "or", "so", "yet", "nor",
        "with", "without", "about", "after", "before", "during",
        "in", "on", "at", "by", "from", "to", "of", "the",
        "a", "an", "this", "that", "these", "those",
        "he", "she", "it", "they", "we", "you", "his", "her",
        "then", "when", "where", "while", "since", "because"
    ]
    
    // MARK: - Public Interface
    
    /// Apply smart capitalization based on cursor context
    func applyCapitalization(to text: String, 
                           shouldCapitalizeStart: Bool) -> CapitalizationResult {
        
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { 
            return CapitalizationResult(text: text, wasModified: false, reason: "Empty text")
        }
        
        print("🔤 Applying capitalization: '\(trimmed)' (shouldCapitalize: \(shouldCapitalizeStart))")
        
        var result = trimmed
        var wasModified = false
        var reason = ""
        
        // Step 1: Handle first word based on cursor context
        if shouldCapitalizeStart {
            let capitalizedFirst = capitalizeFirstWord(result)
            if capitalizedFirst != result {
                result = capitalizedFirst
                wasModified = true
                reason = "Capitalized first word due to cursor context"
            } else {
                // Already capitalized - still consider this "modified" to indicate we processed it
                wasModified = true
                reason = "First word already capitalized correctly"
            }
        } else {
            let lowercaseFirst = makeFirstWordLowercase(result)
            if lowercaseFirst != result {
                result = lowercaseFirst
                wasModified = true
                reason = "Lowercased first word for mid-sentence"
            }
        }
        
        // Step 2: Handle capitalization after punctuation within the text
        let finalResult = capitalizeAfterInternalPunctuation(result)
        if finalResult != result {
            result = finalResult
            wasModified = true
            reason += (reason.isEmpty ? "" : " + ") + "Capitalized after internal punctuation"
        }
        
        print("🔤 Capitalization result: '\(result)' (modified: \(wasModified), reason: '\(reason)')")
        
        return CapitalizationResult(text: result, wasModified: wasModified, reason: reason)
    }
    
    /// Check if a word should preserve its capitalization (medical terms, proper nouns)
    func shouldPreserveCapitalization(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        
        // Preserve medical abbreviations
        if medicalTerms.contains(lowercased) {
            return true
        }
        
        // Preserve words that are already properly capitalized (likely proper nouns)
        if word.count > 1 && 
           word.first?.isUppercase == true && 
           word.dropFirst().contains(where: { $0.isLowercase }) {
            return true
        }
        
        return false
    }
    
    // MARK: - Private Methods - Word-Level Capitalization
    
    private func capitalizeFirstWord(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        let firstChar = String(text.prefix(1)).uppercased()
        let remainder = String(text.dropFirst())
        
        return firstChar + remainder
    }
    
    private func makeFirstWordLowercase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        let words = text.split(separator: " ", maxSplits: 1)
        guard let firstWord = words.first else { return text }
        
        let firstWordString = String(firstWord)
        
        // Preserve medical terms and proper nouns
        if shouldPreserveCapitalization(firstWordString) {
            return text
        }
        
        // Check if this is a common mid-sentence word that should be lowercase
        let lowercaseFirstWord = firstWordString.lowercased()
        if commonMidSentenceWords.contains(lowercaseFirstWord) {
            if words.count > 1 {
                let remainder = String(words[1])
                return lowercaseFirstWord + " " + remainder
            } else {
                return lowercaseFirstWord
            }
        }
        
        // For other words, just lowercase the first character
        let lowercaseFirst = String(firstWordString.prefix(1)).lowercased() + String(firstWordString.dropFirst())
        
        if words.count > 1 {
            let remainder = String(words[1])
            return lowercaseFirst + " " + remainder
        } else {
            return lowercaseFirst
        }
    }
    
    // MARK: - Private Methods - Sentence-Level Capitalization
    
    private func capitalizeAfterInternalPunctuation(_ text: String) -> String {
        // Only capitalize after sentence-ending punctuation, NOT semicolons or colons
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var result = ""
        var shouldCapitalizeNext = false
        var i = text.startIndex
        
        while i < text.endIndex {
            let char = text[i]
            
            if sentenceEnders.contains(char.unicodeScalars.first!) {
                shouldCapitalizeNext = true
                result.append(char)
                print("🔤 Found sentence ender '\(char)' - will capitalize next word")
            } else if char.isWhitespace {
                result.append(char)
                // Don't change shouldCapitalizeNext - keep waiting for the next letter
            } else if char.isLetter && shouldCapitalizeNext {
                // Find the complete word and capitalize it properly
                let wordStart = i
                var wordEnd = i
                
                // Find end of current word
                while wordEnd < text.endIndex && text[wordEnd].isLetter {
                    wordEnd = text.index(after: wordEnd)
                }
                
                let word = String(text[wordStart..<wordEnd])
                let capitalizedWord = capitalizeWordSafely(word)
                result.append(capitalizedWord)
                
                print("🔤 Capitalized word after punctuation: '\(word)' → '\(capitalizedWord)'")
                
                // Skip to end of word
                i = wordEnd
                shouldCapitalizeNext = false
                continue
            } else {
                result.append(char)
                if char.isLetter {
                    shouldCapitalizeNext = false
                }
            }
            
            i = text.index(after: i)
        }
        
        return result
    }
    
    private func capitalizeWordSafely(_ word: String) -> String {
        let lowercased = word.lowercased()
        
        // Preserve medical abbreviations - make them uppercase
        if medicalTerms.contains(lowercased) {
            return word.uppercased()
        }
        
        // Regular capitalization for other words
        return String(word.prefix(1)).uppercased() + String(word.dropFirst()).lowercased()
    }
    
    // MARK: - Public Utilities
    
    /// Quick check if text starts with a medical term
    func startsWithMedicalTerm(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard let firstWord = words.first else { return false }
        
        return medicalTerms.contains(String(firstWord).lowercased())
    }
    
    /// Get appropriate capitalization for a medical term
    func getCorrectMedicalCapitalization(_ term: String) -> String {
        let lowercased = term.lowercased()
        
        if medicalTerms.contains(lowercased) {
            return term.uppercased()
        }
        
        return term
    }
}