import Foundation

/// Main vocabulary management system for MantaScribe
/// Handles both contextual strings (for enhanced speech recognition) and fallback corrections
class VocabularyManager {
    static let shared = VocabularyManager()
    
    // MARK: - Properties
    
    // Legacy vocabulary system (for fallback corrections)
    private var vocabularies: [String: [String: String]] = [:]
    private var enabledCategories: [String] = ["medical"]
    
    // Contextual strings system (for Apple Speech Recognition enhancement)
    private var contextualStrings: [String] = []
    private var contextualStringsByCategory: [String: [String]] = [:]
    private var enabledContextualCategories: Set<String> = []
    
    // Processing state
    private var processedReplacements: [String: String] = [:]
    
    // MARK: - Dependencies
    
    private let contextualLoader: ContextualStringsLoader
    private let textCorrections: TextCorrections
    
    // MARK: - Initialization
    
    private init() {
        self.contextualLoader = ContextualStringsLoader()
        self.textCorrections = TextCorrections()
        
        loadVocabularies()
        setupDefaultCategories()
    }
    
    // MARK: - Public Interface
    
    /// Process text with vocabulary corrections (fallback system)
    func processText(_ text: String) -> String {
        processedReplacements.removeAll()
        return textCorrections.applyCorrections(to: text, 
                                              using: vocabularies, 
                                              enabledCategories: enabledCategories,
                                              processedReplacements: &processedReplacements)
    }
    
    /// Get contextual strings for Apple Speech Recognition
    func getContextualStrings() -> [String] {
        return contextualStrings
    }
    
    /// Set enabled legacy vocabulary categories
    func setEnabledCategories(_ categories: [String]) {
        enabledCategories = categories
        print("📚 Enabled legacy categories: \(categories.joined(separator: ", "))")
    }
    
    /// Set enabled contextual string categories
    func setEnabledContextualCategories(_ categories: [String]) {
        enabledContextualCategories = Set(categories)
        rebuildContextualStrings()
        print("📚 Enabled contextual categories: \(categories.joined(separator: ", "))")
        print("📚 Total contextual strings: \(contextualStrings.count)")
    }
    
    // MARK: - Getters
    
    func getAvailableCategories() -> [String] {
        return Array(vocabularies.keys).sorted()
    }
    
    func getEnabledCategories() -> [String] {
        return enabledCategories
    }
    
    func getAvailableContextualCategories() -> [String] {
        return Array(contextualStringsByCategory.keys).sorted()
    }
    
    func getEnabledContextualCategories() -> [String] {
        return Array(enabledContextualCategories).sorted()
    }
    
    // MARK: - Private Methods
    
    private func loadVocabularies() {
        // Load contextual strings from bundle
        let contextualResult = contextualLoader.loadContextualStrings()
        switch contextualResult {
        case .success(let data):
            self.contextualStringsByCategory = data
            print("✅ Loaded contextual vocabularies: \(data.keys.joined(separator: ", "))")
        case .failure(let error):
            print("⚠️ Contextual strings loading failed: \(error.localizedDescription)")
        }
        
        // Load legacy vocabularies for fallback corrections
        loadLegacyVocabularies()
    }
    
    private func loadLegacyVocabularies() {
        // Keep basic fallback vocabulary for corrections that contextual strings miss
        vocabularies = [
            "medical": [
                "cat scan": "CT scan",
                "ct": "CT",
                "mri": "MRI", 
                "ecg": "ECG",
                "ekg": "EKG", 
                "xray": "X-ray",
                "x ray": "X-ray",
                "covid": "COVID",
                "tylenol": "Tylenol",
                "advil": "Advil",
                "bp": "blood pressure",
                "hr": "heart rate"
            ]
        ]
        print("📚 Loaded legacy vocabulary: \(vocabularies.keys.joined(separator: ", "))")
    }
    
    private func setupDefaultCategories() {
        // Auto-enable medical categories for contextual strings
        let medicalCategories = contextualStringsByCategory.keys.filter { key in
            key.contains("medication") || key.contains("condition") || 
            key.contains("procedure") || key.contains("nuclear") ||
            key.contains("pet_ct") || key.contains("radiology")
        }
        enabledContextualCategories = Set(medicalCategories)
        
        rebuildContextualStrings()
    }
    
    private func rebuildContextualStrings() {
        contextualStrings.removeAll()
        
        for category in enabledContextualCategories {
            if let categoryTerms = contextualStringsByCategory[category] {
                contextualStrings.append(contentsOf: categoryTerms)
            }
        }
        
        // Remove duplicates and limit to Apple's recommended maximum
        contextualStrings = Array(Set(contextualStrings))
        
        // Apple recommends max 2000-2500 terms for optimal performance
        if contextualStrings.count > 2000 {
            print("⚠️ Contextual strings count (\(contextualStrings.count)) exceeds recommended limit")
            contextualStrings = Array(contextualStrings.prefix(2000))
            print("📚 Trimmed to 2000 contextual strings for optimal performance")
        }
        
        print("📚 Built contextual strings array: \(contextualStrings.count) terms")
    }
}