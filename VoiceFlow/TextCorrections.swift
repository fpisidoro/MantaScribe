import Foundation

/// Handles fallback text corrections for terms missed by contextual strings
/// This system serves as a safety net for medical terminology that contextual strings don't catch
class TextCorrections {
    
    // MARK: - Types
    
    private struct TermReplacement {
        let spoken: String
        let correct: String
        let length: Int
        
        init(spoken: String, correct: String) {
            self.spoken = spoken
            self.correct = correct
            self.length = spoken.count
        }
    }
    
    // MARK: - Properties
    
    private var termsByLength: [Int: [TermReplacement]] = [:]
    private var maxTermLength: Int = 0
    
    // MARK: - Public Methods
    
    /// Apply vocabulary corrections to text using legacy correction system
    /// This serves as fallback for terms missed by contextual strings
    func applyCorrections(to text: String, 
                         using vocabularies: [String: [String: String]], 
                         enabledCategories: [String],
                         processedReplacements: inout [String: String]) -> String {
        
        // Rebuild optimization structure if needed
        rebuildOptimizedStructure(vocabularies: vocabularies, enabledCategories: enabledCategories)
        
        guard !termsByLength.isEmpty else { 
            return text 
        }
        
        print("📚 Applying fallback corrections to: '\(text)'")
        var result = text
        
        // Process from longest to shortest terms to avoid partial replacements
        for length in (1...maxTermLength).reversed() {
            guard let termsOfLength = termsByLength[length] else { continue }
            
            for term in termsOfLength {
                // Skip if we already processed this exact replacement in this session
                let replacementKey = "\(term.spoken)->\(term.correct)"
                if processedReplacements[replacementKey] != nil {
                    continue
                }
                
                // Check if this spoken form exists and needs replacement
                if needsReplacement(in: result, term: term) {
                    let beforeReplacement = result
                    result = performReplacement(in: result, term: term)
                    
                    if beforeReplacement != result {
                        print("📚 ✅ Fallback correction: '\(term.spoken)' → '\(term.correct)'")
                        // Mark this replacement as completed for this session
                        processedReplacements[replacementKey] = term.correct
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func rebuildOptimizedStructure(vocabularies: [String: [String: String]], enabledCategories: [String]) {
        termsByLength.removeAll()
        maxTermLength = 0
        
        for category in enabledCategories {
            if let categoryDict = vocabularies[category] {
                for (spoken, correct) in categoryDict {
                    let term = TermReplacement(spoken: spoken, correct: correct)
                    maxTermLength = max(maxTermLength, term.length)
                    
                    if termsByLength[term.length] == nil {
                        termsByLength[term.length] = []
                    }
                    termsByLength[term.length]?.append(term)
                }
            }
        }
        
        let totalTerms = termsByLength.values.flatMap { $0 }.count
        print("📚 Legacy correction terms: \(totalTerms) terms, max length: \(maxTermLength)")
    }
    
    private func needsReplacement(in text: String, term: TermReplacement) -> Bool {
        let lowercaseText = text.lowercased()
        let lowercaseSpoken = term.spoken.lowercased()
        let lowercaseCorrect = term.correct.lowercased()
        
        // Don't replace if:
        // 1. Spoken form not in text
        if !lowercaseText.contains(lowercaseSpoken) {
            return false
        }
        
        // 2. Spoken and correct forms are equivalent
        if lowercaseSpoken == lowercaseCorrect {
            return false
        }
        
        // 3. Text already contains the correct form in the right place
        if lowercaseText.contains(lowercaseCorrect) {
            return false
        }
        
        return true
    }
    
    private func performReplacement(in text: String, term: TermReplacement) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term.spoken))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        
        let range = NSRange(location: 0, length: text.utf16.count)
        let replacementForm = isMedicalAbbreviation(term.correct) ? term.correct : term.correct.lowercased()
        
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacementForm)
    }
    
    /// Check if a term is a medical abbreviation that should preserve capitalization
    private func isMedicalAbbreviation(_ term: String) -> Bool {
        let medicalAbbreviations = [
            "CT", "CT scan", "MRI", "MRI scan", "ECG", "EKG", "X-ray",
            "COVID", "COVID-19", "BP", "HR", "RR", "ICU", "ER", "OR",
            "CBC", "BMP", "CMP", "COPD", "CHF", "CPR", "DNR", "NPO",
            "IV", "PO", "PRN", "BID", "TID", "QID", "ENT"
        ]
        
        return medicalAbbreviations.contains(term) || 
               medicalAbbreviations.contains(where: { $0.lowercased() == term.lowercased() })
    }
}