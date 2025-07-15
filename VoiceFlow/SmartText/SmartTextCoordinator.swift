/*
 * MantaScribe - SmartTextCoordinator.swift - Performance Testing Framework
 *
 * PERFORMANCE TESTING FRAMEWORK:
 * - Toggle individual smart features on/off to measure performance impact
 * - Detailed timing logs for each feature component
 * - Step-by-step debugging from Fast Mode to Full Smart Mode
 *
 * USAGE:
 * - Change feature flags (enableLegacyVocabulary, etc.) to test individual components
 * - Watch console logs for detailed performance metrics
 * - Identify which features cause performance bottlenecks
 */

import Foundation
import Cocoa

// MARK: - SmartText Coordinator (Performance Testing Framework)

/// Coordinates all SmartText components with granular feature control for performance testing
/// Toggle individual features on/off to measure performance impact of each component
class SmartTextCoordinator {
    
    // MARK: - Performance Testing Flags
    // Toggle these manually in code to test individual feature performance impact
    
    /// Step 1: Basic vocabulary corrections (string processing only)
    /// Expected impact: Minimal (just dictionary lookups)
    var enableLegacyVocabulary = false
    
    /// Step 2: Enhanced speech recognition (handled by Apple's engine)
    /// Expected impact: None (processed during speech recognition)
    var enableContextualStrings = true
    
    /// Step 3: Intelligent spacing decisions (requires cursor detection)
    /// Expected impact: Medium (app switching + cursor analysis)
    var enableSmartSpacing = false
    
    /// Step 4: Context-aware capitalization (requires cursor detection)
    /// Expected impact: High (app switching + text selection + cursor manipulation)
    var enableSmartCapitalization = false
    
    // MARK: - Dependencies (for future smart features)
    
    private var spacingEngine: SmartSpacingEngine?
    private var capitalizationEngine: SmartCapitalizationEngine?
    
    // MARK: - Initialization
    
    init() {
        // Initialize smart feature engines when needed
        if enableSmartSpacing {
            spacingEngine = SmartSpacingEngine()
        }
        
        if enableSmartCapitalization {
            capitalizationEngine = SmartCapitalizationEngine()
        }
        
        printCurrentConfiguration()
    }
    
    // MARK: - Main Processing Pipeline
    
    /// Process text with enabled smart features and send to target app
    func processAndSend(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager,
        completion: @escaping (AppTargetManager.AppSwitchResult) -> Void
    ) {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🧠 SmartText processing started: '\(text)'")
        
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
        }
        
        // Step 2: Smart spacing (cursor detection + spacing logic)
        var spacingDecision: (needsLeadingSpace: Bool, needsTrailingSpace: Bool) = (true, false)
        if enableSmartSpacing {
            let spacingStartTime = CFAbsoluteTimeGetCurrent()
            spacingDecision = analyzeSpacingContext(text: processedText, targetApp: targetApp, appTargetManager: appTargetManager)
            let spacingTime = (CFAbsoluteTimeGetCurrent() - spacingStartTime) * 1000
            appliedFeatures.append("Smart Spacing (\(String(format: "%.1f", spacingTime))ms)")
        }
        
        // Step 3: Smart capitalization (cursor detection + capitalization logic)
        var shouldCapitalize = false
        if enableSmartCapitalization {
            let capsStartTime = CFAbsoluteTimeGetCurrent()
            shouldCapitalize = analyzeCapitalizationContext(text: processedText, targetApp: targetApp, appTargetManager: appTargetManager)
            let capsTime = (CFAbsoluteTimeGetCurrent() - capsStartTime) * 1000
            appliedFeatures.append("Smart Capitalization (\(String(format: "%.1f", capsTime))ms)")
        }
        
        // Apply capitalization if needed
        if shouldCapitalize && !processedText.isEmpty {
            let firstChar = processedText.prefix(1).uppercased()
            let restOfText = processedText.dropFirst()
            processedText = firstChar + restOfText
            print("🧠 ✅ Applied smart capitalization: '\(text)' → '\(processedText)'")
        }
        
        // Send processed text with smart formatting
        appTargetManager.sendText(
            processedText,
            shouldCapitalize: false, // Already handled above
            needsLeadingSpace: spacingDecision.needsLeadingSpace,
            needsTrailingSpace: spacingDecision.needsTrailingSpace,
            completion: completion
        )
        
        // Performance logging
        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let featuresApplied = appliedFeatures.isEmpty ? "None" : appliedFeatures.joined(separator: ", ")
        print("🧠 ⏱️ SmartText completed in \(String(format: "%.1f", totalTime))ms | Features: \(featuresApplied)")
    }
    
    // MARK: - Smart Feature Analysis (Placeholders)
    
    /// Analyze cursor context to determine optimal spacing
    private func analyzeSpacingContext(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager
    ) -> (needsLeadingSpace: Bool, needsTrailingSpace: Bool) {
        
        // TODO: Re-implement cursor detection logic from original SpacingEngine
        // This is where the performance impact will be measured
        
        // For now, return smart defaults based on text analysis
        let isPunctuation = [".", ",", "?", "!", ":", ";"].contains(text.trimmingCharacters(in: .whitespaces))
        
        if isPunctuation {
            return (needsLeadingSpace: false, needsTrailingSpace: true)
        } else {
            return (needsLeadingSpace: true, needsTrailingSpace: false)
        }
    }
    
    /// Analyze cursor context to determine if capitalization is needed
    private func analyzeCapitalizationContext(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager
    ) -> Bool {
        
        // TODO: Re-implement cursor detection logic from original CapitalizationEngine
        // This is where the highest performance impact will be measured
        
        // For now, return smart defaults based on text analysis
        // Check if text looks like it should be capitalized
        if text.isEmpty { return false }
        
        // Simple heuristic: capitalize if text looks like start of sentence
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.first?.isLowercase == true
    }
    
    // MARK: - Configuration Management
    
    /// Print current feature configuration for debugging
    private func printCurrentConfiguration() {
        print("""
        
        🧠 SmartTextCoordinator - Performance Testing Configuration
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📚 Legacy Vocabulary: \(enableLegacyVocabulary ? "✅ ENABLED" : "❌ DISABLED")
        🎯 Contextual Strings: \(enableContextualStrings ? "✅ ENABLED" : "❌ DISABLED")  
        📝 Smart Spacing: \(enableSmartSpacing ? "✅ ENABLED" : "❌ DISABLED")
        🔤 Smart Capitalization: \(enableSmartCapitalization ? "✅ ENABLED" : "❌ DISABLED")
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        """)
    }
    
    /// Update configuration and reinitialize engines as needed
    func updateConfiguration() {
        printCurrentConfiguration()
        
        // Reinitialize engines based on new configuration
        if enableSmartSpacing && spacingEngine == nil {
            spacingEngine = SmartSpacingEngine()
            print("🧠 Initialized SmartSpacingEngine")
        }
        
        if enableSmartCapitalization && capitalizationEngine == nil {
            capitalizationEngine = SmartCapitalizationEngine()
            print("🧠 Initialized SmartCapitalizationEngine")
        }
    }
}

// MARK: - Smart Feature Engine Placeholders

/// Placeholder for future smart spacing engine re-implementation
class SmartSpacingEngine {
    init() {
        print("📝 SmartSpacingEngine initialized (placeholder)")
    }
}

/// Placeholder for future smart capitalization engine re-implementation
class SmartCapitalizationEngine {
    init() {
        print("🔤 SmartCapitalizationEngine initialized (placeholder)")
    }
}
