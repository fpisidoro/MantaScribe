import Foundation

/// Handles loading and parsing of contextual strings from JSON files
/// Supports multiple file formats and provides robust error handling
class ContextualStringsLoader {
    
    // MARK: - Types
    
    enum LoadingError: Error, LocalizedError {
        case fileNotFound
        case invalidJSONFormat
        case noVocabulariesFound
        case parsingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Vocabulary file not found in app bundle"
            case .invalidJSONFormat:
                return "Invalid JSON format in vocabulary file"
            case .noVocabulariesFound:
                return "No vocabularies found in JSON structure"
            case .parsingFailed(let details):
                return "Parsing failed: \(details)"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Load contextual strings from app bundle
    /// Returns dictionary of category -> [terms] for contextual strings
    func loadContextualStrings() -> Result<[String: [String]], LoadingError> {
        // Try multiple possible vocabulary files in order of preference
        let possibleFiles = [
            "optimized_medical_vocabulary",
            "medical_contextual_strings",
            "contextual_strings",
            "vocabularies"
        ]
        
        for fileName in possibleFiles {
            if let result = tryLoadFile(fileName) {
                print("✅ Loaded contextual strings from: \(fileName).json")
                return result
            }
        }
        
        print("❌ No contextual strings file found - tried: \(possibleFiles.joined(separator: ", "))")
        return .failure(.fileNotFound)
    }
    
    // MARK: - Private Methods
    
    private func tryLoadFile(_ fileName: String) -> Result<[String: [String]], LoadingError>? {
        // Try loading from path first
        if let path = Bundle.main.path(forResource: fileName, ofType: "json") {
            if let result = loadFromPath(path) {
                return result
            }
        }
        
        // Try loading from URL
        if let url = Bundle.main.url(forResource: fileName, withExtension: "json") {
            if let result = loadFromURL(url) {
                return result
            }
        }
        
        return nil
    }
    
    private func loadFromPath(_ path: String) -> Result<[String: [String]], LoadingError>? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return parseVocabularyData(data)
        } catch {
            print("❌ Error loading from path \(path): \(error)")
            return nil
        }
    }
    
    private func loadFromURL(_ url: URL) -> Result<[String: [String]], LoadingError>? {
        do {
            let data = try Data(contentsOf: url)
            return parseVocabularyData(data)
        } catch {
            print("❌ Error loading from URL \(url): \(error)")
            return nil
        }
    }
    
    private func parseVocabularyData(_ data: Data) -> Result<[String: [String]], LoadingError> {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.invalidJSONFormat)
            }
            
            // Try new contextual_strings format first
            if let contextualData = json["contextual_strings"] as? [String: [String]] {
                let totalTerms = contextualData.values.map { $0.count }.reduce(0, +)
                print("✅ Loaded \(contextualData.keys.count) contextual categories with \(totalTerms) total terms")
                return .success(contextualData)
            }
            
            // Try legacy vocabularies format and convert
            if let legacyData = json["vocabularies"] as? [String: [String: String]] {
                print("⚠️ Found legacy vocabulary format - converting to contextual strings")
                let converted = convertLegacyToContextual(legacyData)
                return .success(converted)
            }
            
            return .failure(.noVocabulariesFound)
            
        } catch {
            return .failure(.parsingFailed(error.localizedDescription))
        }
    }
    
    private func convertLegacyToContextual(_ legacyVocab: [String: [String: String]]) -> [String: [String]] {
        var contextualData: [String: [String]] = [:]
        
        for (category, terms) in legacyVocab {
            // Combine spoken and correct forms into contextual strings
            let spokenTerms = Array(terms.keys)
            let correctTerms = Array(terms.values)
            let contextualTerms = Array(Set(spokenTerms + correctTerms))
            contextualData[category] = contextualTerms
        }
        
        let totalTerms = contextualData.values.map { $0.count }.reduce(0, +)
        print("✅ Converted \(legacyVocab.keys.count) legacy categories to \(totalTerms) contextual strings")
        
        return contextualData
    }
}
