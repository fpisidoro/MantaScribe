import Foundation

/// Manages all user preferences for MantaScribe
/// Provides a centralized way to handle settings with UserDefaults backing
class PreferencesManager {
    
    // MARK: - Singleton
    
    static let shared = PreferencesManager()
    private init() {}
    
    // MARK: - Preference Keys
    
    private enum Keys {
        // General preferences
        static let launchAtLogin = "launchAtLogin"
        static let showStatusInMenuBar = "showStatusInMenuBar"
        static let enableAudioFeedback = "enableAudioFeedback"
        
        // Dictation preferences
        static let globalHotkey = "globalHotkey"
        static let bufferTimeout = "bufferTimeout"
        static let defaultTargetApp = "defaultTargetApp"
        static let autoCapitalization = "autoCapitalization"
        
        // Performance preferences
        static let performanceMode = "performanceMode" // "smart" or "fast"
        static let speechRecognitionLanguage = "speechRecognitionLanguage"
        
        // Medical vocabulary preferences
        static let enableMedicalVocabulary = "enableMedicalVocabulary"
        static let enabledMedicalCategories = "enabledMedicalCategories"
        
        // Window preferences
        static let preferencesWindowFrame = "preferencesWindowFrame"
    }
    
    // MARK: - General Preferences
    
    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.launchAtLogin) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.launchAtLogin)
            notifyPreferenceChanged(.launchAtLogin)
        }
    }
    
    var showStatusInMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: Keys.showStatusInMenuBar) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showStatusInMenuBar)
            notifyPreferenceChanged(.showStatusInMenuBar)
        }
    }
    
    var enableAudioFeedback: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enableAudioFeedback) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.enableAudioFeedback)
            notifyPreferenceChanged(.enableAudioFeedback)
        }
    }
    
    // MARK: - Dictation Preferences
    
    var globalHotkey: String {
        get { UserDefaults.standard.string(forKey: Keys.globalHotkey) ?? "Right Option" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.globalHotkey)
            notifyPreferenceChanged(.globalHotkey)
        }
    }
    
    var bufferTimeout: Double {
        get {
            let value = UserDefaults.standard.double(forKey: Keys.bufferTimeout)
            return value > 0 ? value : 2.0 // Default 2 seconds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.bufferTimeout)
            notifyPreferenceChanged(.bufferTimeout)
        }
    }
    
    var defaultTargetApp: String {
        get { UserDefaults.standard.string(forKey: Keys.defaultTargetApp) ?? "TextEdit" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.defaultTargetApp)
            notifyPreferenceChanged(.defaultTargetApp)
        }
    }
    
    var autoCapitalization: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoCapitalization) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoCapitalization)
            notifyPreferenceChanged(.autoCapitalization)
        }
    }
    
    // MARK: - Performance Preferences
    
    enum PerformanceMode: String, CaseIterable {
        case smart = "smart"
        case fast = "fast"
        
        var displayName: String {
            switch self {
            case .smart: return "Smart Mode (Full Features)"
            case .fast: return "Fast Mode (Performance Optimized)"
            }
        }
    }
    
    var performanceMode: PerformanceMode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: Keys.performanceMode) ?? PerformanceMode.smart.rawValue
            return PerformanceMode(rawValue: rawValue) ?? .smart
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.performanceMode)
            notifyPreferenceChanged(.performanceMode)
        }
    }
    
    var speechRecognitionLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.speechRecognitionLanguage) ?? "en-US" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.speechRecognitionLanguage)
            notifyPreferenceChanged(.speechRecognitionLanguage)
        }
    }
    
    // MARK: - Medical Vocabulary Preferences
    
    var enableMedicalVocabulary: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enableMedicalVocabulary) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.enableMedicalVocabulary)
            notifyPreferenceChanged(.enableMedicalVocabulary)
        }
    }
    
    var enabledMedicalCategories: Set<String> {
        get {
            let array = UserDefaults.standard.array(forKey: Keys.enabledMedicalCategories) as? [String] ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Keys.enabledMedicalCategories)
            notifyPreferenceChanged(.enabledMedicalCategories)
        }
    }
    
    // MARK: - Window Preferences
    
    var preferencesWindowFrame: NSRect? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.preferencesWindowFrame) else { return nil }
            return NSRect(from: data)
        }
        set {
            if let frame = newValue {
                UserDefaults.standard.set(frame.data, forKey: Keys.preferencesWindowFrame)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferencesWindowFrame)
            }
        }
    }
    
    // MARK: - Preference Change Notifications
    
    enum PreferenceKey {
        case launchAtLogin
        case showStatusInMenuBar
        case enableAudioFeedback
        case globalHotkey
        case bufferTimeout
        case defaultTargetApp
        case autoCapitalization
        case performanceMode
        case speechRecognitionLanguage
        case enableMedicalVocabulary
        case enabledMedicalCategories
    }
    
    static let preferenceDidChangeNotification = Notification.Name("PreferenceDidChange")
    
    private func notifyPreferenceChanged(_ key: PreferenceKey) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: PreferencesManager.preferenceDidChangeNotification,
                object: self,
                userInfo: ["key": key]
            )
        }
    }
    
    // MARK: - Utility Methods
    
    /// Reset all preferences to defaults
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        // Notify all preferences changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.preferenceDidChangeNotification, object: self)
        }
    }
    
    /// Export preferences to a dictionary for backup
    func exportPreferences() -> [String: Any] {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        return defaults.filter { key, _ in
            key.hasPrefix("launchAtLogin") ||
            key.hasPrefix("showStatusInMenuBar") ||
            key.hasPrefix("enableAudioFeedback") ||
            key.hasPrefix("globalHotkey") ||
            key.hasPrefix("bufferTimeout") ||
            key.hasPrefix("defaultTargetApp") ||
            key.hasPrefix("autoCapitalization") ||
            key.hasPrefix("performanceMode") ||
            key.hasPrefix("speechRecognitionLanguage") ||
            key.hasPrefix("enableMedicalVocabulary") ||
            key.hasPrefix("enabledMedicalCategories")
        }
    }
    
    /// Import preferences from a dictionary
    func importPreferences(_ preferences: [String: Any]) {
        for (key, value) in preferences {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.synchronize()
        
        // Notify all preferences changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.preferenceDidChangeNotification, object: self)
        }
    }
}

// MARK: - NSRect Data Conversion

private extension NSRect {
    init?(from data: Data) {
        guard data.count == MemoryLayout<NSRect>.size else { return nil }
        self = data.withUnsafeBytes { $0.load(as: NSRect.self) }
    }
    
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}
