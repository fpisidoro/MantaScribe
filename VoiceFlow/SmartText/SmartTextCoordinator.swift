/*
 * MantaScribe - SmartTextCoordinator.swift - Real Smart Features Integration
 *
 * SMART COMPLETION INTEGRATION:
 * - Integrated real CursorDetector, CapitalizationEngine, and SpacingEngine
 * - Medical vocabulary remains enabled via contextualStrings
 * - Performance testing framework maintained for future optimization
 *
 * USAGE WITH COMPLETION DETECTION:
 * - Now processes Apple's final corrected transcription
 * - Applies intelligent capitalization and spacing to accurate text
 * - No more processing of incomplete/incorrect partial results
 */

import Foundation
import Cocoa

// MARK: - SmartText Coordinator (Real Engines Integration)

/// Coordinates all SmartText components with Apple's completion-detected text
/// Now uses real CursorDetector, CapitalizationEngine, and SpacingEngine for production-grade intelligence
class SmartTextCoordinator {
    
    // MARK: - Smart Features Configuration (Now from Preferences)
    
    /// Step 1: Basic vocabulary corrections (string processing only)
    /// Expected impact: Minimal (just dictionary lookups)
    private var enableLegacyVocabulary: Bool {
        return PreferencesManager.shared.enableLegacyVocabulary
    }
    
    /// Step 2: Enhanced speech recognition (handled by Apple's engine)
    /// Expected impact: None (processed during speech recognition)
    private var enableContextualStrings: Bool {
        return PreferencesManager.shared.enableContextualStrings
    }
    
    /// Step 3: Intelligent spacing decisions (requires cursor detection)
    /// Expected impact: Medium (app switching + cursor analysis)
    private var enableSmartSpacing: Bool {
        return PreferencesManager.shared.enableSmartSpacing
    }
    
    /// Step 4: Context-aware capitalization (requires cursor detection)
    /// Expected impact: High (app switching + text selection + cursor manipulation)
    private var enableSmartCapitalization: Bool {
        return PreferencesManager.shared.enableSmartCapitalization
    }
    
    // MARK: - Real Smart Feature Engines
    
    private let cursorDetector: CursorDetector
    private let spacingEngine: SpacingEngine
    private let capitalizationEngine: CapitalizationEngine
    
    // MARK: - Initialization
    
    init() {
        // Initialize real smart feature engines for completion-detected text
        self.cursorDetector = CursorDetector()
        self.spacingEngine = SpacingEngine()
        self.capitalizationEngine = CapitalizationEngine()
        
        // Log initial configuration
        printCurrentConfiguration()
        
        // Listen for preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: PreferencesManager.preferenceDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Preference Change Handling
    
    @objc private func preferencesDidChange(_ notification: Notification) {
        // Check if any of our smart text preferences changed
        guard let userInfo = notification.userInfo,
              let key = userInfo["key"] as? PreferencesManager.PreferenceKey else {
            return
        }
        
        switch key {
        case .enableLegacyVocabulary, .enableContextualStrings, .enableSmartSpacing, .enableSmartCapitalization:
            print("🧠 🔧 SmartText preferences changed - updating configuration")
            printCurrentConfiguration()
        default:
            break
        }
    }
    
    // MARK: - Main Processing Pipeline (For Apple's Corrected Text)
    
    /// Process completion-detected text with full smart features enabled
    /// This now receives Apple's final corrected transcription instead of partial results
    func processAndSend(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager,
        completion: @escaping (AppTargetManager.AppSwitchResult) -> Void
    ) {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🧠 SmartText processing Apple's corrected text: '\(text)'")
        
        var processedText = text
        var appliedFeatures: [String] = []
        
        // Step 1: Legacy vocabulary corrections (string processing)
        if enableLegacyVocabulary {
            let vocabStartTime = CFAbsoluteTimeGetCurrent()
            processedText = VocabularyManager.shared.processText(processedText)
            let vocabTime = (CFAbsoluteTimeGetCurrent() - vocabStartTime) * 1000
            appliedFeatures.append("Legacy Vocabulary (\(String(format: "%.1f", vocabTime))ms)")
            
            if processedText != text {
                print("🧠 ✅ Legacy vocabulary applied: '\(text)' → '\(processedText)'")
            }
        } else {
            print("🧠 ⚠️ Legacy vocabulary bypassed (disabled in preferences)")
        }
        
        // Step 2: Real cursor detection (for both spacing and capitalization)
        var cursorDetectionResult: CursorDetector.DetectionResult?
        var detectionTime: Double = 0
        
        if enableSmartSpacing || enableSmartCapitalization {
            let detectionStartTime = CFAbsoluteTimeGetCurrent()
            
            // Switch to target app briefly for cursor detection
            let originalApp = NSWorkspace.shared.frontmostApplication
            
            // Activate target app for cursor detection
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetApp.bundleId).first {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }
            
            // Perform real cursor detection
            cursorDetectionResult = cursorDetector.detectCursorContext()
            detectionTime = (CFAbsoluteTimeGetCurrent() - detectionStartTime) * 1000
            appliedFeatures.append("Cursor Detection (\(String(format: "%.1f", detectionTime))ms)")
            
            // Restore original app (will happen anyway during text sending, but good practice)
            if let original = originalApp {
                original.activate(options: [])
            }
        } else {
            print("🧠 ⚠️ Cursor detection bypassed (both spacing and capitalization disabled)")
        }
        
        // Step 3: Smart spacing using real SpacingEngine
        var spacingDecision = SpacingEngine.SpacingDecision(needsLeadingSpace: true, needsTrailingSpace: false, reason: "Default spacing")
        
        if enableSmartSpacing, let detectionResult = cursorDetectionResult {
            let spacingStartTime = CFAbsoluteTimeGetCurrent()
            
            // Use real SpacingEngine with detected cursor context
            let isPunctuation = spacingEngine.isPunctuation(processedText)
            spacingDecision = spacingEngine.determineSpacing(
                for: processedText,
                detectedChars: detectionResult.detectedChars,
                isPunctuation: isPunctuation
            )
            
            let spacingTime = (CFAbsoluteTimeGetCurrent() - spacingStartTime) * 1000
            appliedFeatures.append("Smart Spacing (\(String(format: "%.1f", spacingTime))ms)")
            
            print("🧠 📝 Smart spacing decision: leading=\(spacingDecision.needsLeadingSpace), trailing=\(spacingDecision.needsTrailingSpace) (\(spacingDecision.reason))")
        } else if !enableSmartSpacing {
            print("🧠 ⚠️ Smart spacing bypassed (disabled in preferences)")
        }
        
        // Step 4: Smart capitalization using real CapitalizationEngine
        var capitalizationResult: CapitalizationEngine.CapitalizationResult?
        
        if enableSmartCapitalization, let detectionResult = cursorDetectionResult {
            let capsStartTime = CFAbsoluteTimeGetCurrent()
            
            // Determine if we should capitalize based on cursor context
            let shouldCapitalize = detectionResult.context.shouldCapitalize
            print("🧠 🔤 Capitalization analysis: context=\(detectionResult.context), shouldCapitalize=\(shouldCapitalize)")
            
            // Apply real CapitalizationEngine
            capitalizationResult = capitalizationEngine.applyCapitalization(
                to: processedText,
                shouldCapitalizeStart: shouldCapitalize
            )
            
            print("🧠 🔤 CapitalizationEngine result: \(capitalizationResult?.reason ?? "nil result")")
            
            if let result = capitalizationResult, result.wasModified {
                processedText = result.text
                print("🧠 ✅ Smart capitalization applied: '\(text)' → '\(processedText)' (\(result.reason))")
            } else {
                print("🧠 ⚠️ No capitalization applied - result: \(capitalizationResult?.description ?? "nil")")
            }
            
            let capsTime = (CFAbsoluteTimeGetCurrent() - capsStartTime) * 1000
            appliedFeatures.append("Smart Capitalization (\(String(format: "%.1f", capsTime))ms)")
        } else if !enableSmartCapitalization {
            print("🧠 ⚠️ Smart capitalization bypassed (disabled in preferences)")
        } else {
            print("🧠 ⚠️ Smart capitalization skipped: enabled=\(enableSmartCapitalization), detectionResult=\(cursorDetectionResult != nil)")
        }
        
        // Send processed text with smart formatting
        appTargetManager.sendText(
            processedText,
            shouldCapitalize: false, // Already handled by CapitalizationEngine
            needsLeadingSpace: spacingDecision.needsLeadingSpace,
            needsTrailingSpace: spacingDecision.needsTrailingSpace,
            completion: completion
        )
        
        // Performance logging
        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let featuresApplied = appliedFeatures.isEmpty ? "None" : appliedFeatures.joined(separator: ", ")
        print("🧠 ⏱️ SmartText completed in \(String(format: "%.1f", totalTime))ms | Features: \(featuresApplied)")
        
        // Log detailed results for debugging
        if enableSmartCapitalization || enableSmartSpacing {
            logDetailedResults(
                originalText: text,
                finalText: processedText,
                cursorContext: cursorDetectionResult?.context,
                detectedChars: cursorDetectionResult?.detectedChars,
                spacingDecision: spacingDecision,
                capitalizationResult: capitalizationResult
            )
        }
    }
    
    // MARK: - Configuration Management
    
    /// Print current feature configuration for debugging
    private func printCurrentConfiguration() {
        print("""
        
        🧠 SmartTextCoordinator - Real Smart Engines Integration (Preferences-Controlled)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📚 Legacy Vocabulary: \(enableLegacyVocabulary ? "✅ ENABLED" : "❌ DISABLED")
        🎯 Contextual Strings: \(enableContextualStrings ? "✅ ENABLED" : "❌ DISABLED")  
        📝 Smart Spacing: \(enableSmartSpacing ? "✅ ENABLED (Real SpacingEngine)" : "❌ DISABLED")
        🔤 Smart Capitalization: \(enableSmartCapitalization ? "✅ ENABLED (Real CapitalizationEngine)" : "❌ DISABLED")
        🔍 Cursor Detection: \(enableSmartSpacing || enableSmartCapitalization ? "✅ ENABLED (Real CursorDetector)" : "❌ DISABLED")
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        🧠 Now using REAL smart engines controlled by user preferences!
        
        """)
    }
    
    /// Update configuration and reinitialize engines as needed
    func updateConfiguration() {
        printCurrentConfiguration()
        // Real engines are always initialized, just controlled by preference flags
        print("🧠 Real engines ready - controlled by preference flags")
    }
    
    // MARK: - Public Access to Feature States (for external components)
    
    /// Get current legacy vocabulary setting (for other components that need this info)
    func isLegacyVocabularyEnabled() -> Bool {
        return enableLegacyVocabulary
    }
    
    /// Get current contextual strings setting (for DictationEngine)
    func isContextualStringsEnabled() -> Bool {
        return enableContextualStrings
    }
    
    /// Get current smart spacing setting
    func isSmartSpacingEnabled() -> Bool {
        return enableSmartSpacing
    }
    
    /// Get current smart capitalization setting
    func isSmartCapitalizationEnabled() -> Bool {
        return enableSmartCapitalization
    }
    
    // MARK: - Detailed Logging for Debugging
    
    private func logDetailedResults(
        originalText: String,
        finalText: String,
        cursorContext: CursorDetector.CursorContext?,
        detectedChars: String?,
        spacingDecision: SpacingEngine.SpacingDecision,
        capitalizationResult: CapitalizationEngine.CapitalizationResult?
    ) {
        print("""
        
        🧠 SmartText Detailed Results:
        ┌─ Input: '\(originalText)'
        ├─ Output: '\(finalText)'
        ├─ Cursor Context: \(cursorContext?.description ?? "Unknown")
        ├─ Detected Chars: '\(detectedChars?.debugDescription ?? "None")'
        ├─ Spacing: \(spacingDecision.reason)
        └─ Capitalization: \(capitalizationResult?.reason ?? "Not applied")
        
        """)
    }
}

// MARK: - CursorContext Extension for Better Logging

extension CursorDetector.CursorContext: CustomStringConvertible {
    var description: String {
        switch self {
        case .startOfDocument:
            return "Start of Document"
        case .afterSentencePunctuation:
            return "After Sentence Punctuation"
        case .afterClausePunctuation:
            return "After Clause Punctuation"
        case .afterWhitespace:
            return "After Whitespace"
        case .afterDoubleNewline:
            return "After Double Newline"
        case .afterNormalText:
            return "After Normal Text"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - CapitalizationResult Extension for Better Logging

extension CapitalizationEngine.CapitalizationResult: CustomStringConvertible {
    var description: String {
        return "CapitalizationResult(text: '\(text)', wasModified: \(wasModified), reason: '\(reason)')"
    }
}
