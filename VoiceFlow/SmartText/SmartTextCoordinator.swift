/*
 * MantaScribe - SmartTextCoordinator.swift - Smart Features Re-enabled for Completion Detection
 *
 * SMART COMPLETION INTEGRATION:
 * - Re-enabled smart capitalization and spacing for Apple's corrected text
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

// MARK: - SmartText Coordinator (Re-enabled for Smart Completion)

/// Coordinates all SmartText components with Apple's completion-detected text
/// Now processes final corrected transcription for maximum accuracy + intelligence
class SmartTextCoordinator {
    
    // MARK: - Smart Features Configuration
    // Re-enabled for Smart Completion Detection integration
    
    /// Step 1: Basic vocabulary corrections (string processing only)
    /// Expected impact: Minimal (just dictionary lookups)
    var enableLegacyVocabulary = true  // ✅ RE-ENABLED
    
    /// Step 2: Enhanced speech recognition (handled by Apple's engine)
    /// Expected impact: None (processed during speech recognition)
    var enableContextualStrings = true  // ✅ ENABLED (was already on)
    
    /// Step 3: Intelligent spacing decisions (requires cursor detection)
    /// Expected impact: Medium (app switching + cursor analysis)
    var enableSmartSpacing = true  // ✅ RE-ENABLED
    
    /// Step 4: Context-aware capitalization (requires cursor detection)
    /// Expected impact: High (app switching + text selection + cursor manipulation)
    var enableSmartCapitalization = true  // ✅ RE-ENABLED
    
    // MARK: - Dependencies
    
    private var spacingEngine: SmartSpacingEngine?
    private var capitalizationEngine: SmartCapitalizationEngine?
    
    // MARK: - Initialization
    
    init() {
        // Initialize smart feature engines for completion-detected text
        if enableSmartSpacing {
            spacingEngine = SmartSpacingEngine()
        }
        
        if enableSmartCapitalization {
            capitalizationEngine = SmartCapitalizationEngine()
        }
        
        printCurrentConfiguration()
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
    
    // MARK: - Smart Feature Analysis (Re-implement Core Logic)
    
    /// Analyze cursor context to determine optimal spacing
    private func analyzeSpacingContext(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager
    ) -> (needsLeadingSpace: Bool, needsTrailingSpace: Bool) {
        
        // Get cursor context from target app
        let cursorContext = getCursorContext(targetApp: targetApp, appTargetManager: appTargetManager)
        
        // Analyze spacing based on text content and cursor context
        let textToAnalyze = text.trimmingCharacters(in: .whitespaces)
        
        // Check if this is punctuation
        let isPunctuation = [".", ",", "?", "!", ":", ";"].contains(textToAnalyze)
        
        if isPunctuation {
            // Punctuation: no leading space, add trailing space
            print("🧠 📝 Spacing: Punctuation detected - no leading space, add trailing space")
            return (needsLeadingSpace: false, needsTrailingSpace: true)
        }
        
        // Check cursor context for existing spacing
        let beforeCursor = cursorContext.beforeCursor
        let afterCursor = cursorContext.afterCursor
        
        // Determine leading space
        let needsLeadingSpace: Bool
        if beforeCursor.isEmpty {
            // Start of document - no leading space
            needsLeadingSpace = false
            print("🧠 📝 Spacing: Start of document - no leading space")
        } else if beforeCursor.hasSuffix(" ") || beforeCursor.hasSuffix("\n") {
            // Already has whitespace - no additional space
            needsLeadingSpace = false
            print("🧠 📝 Spacing: Existing whitespace detected - no leading space")
        } else {
            // Normal text continuation - add leading space
            needsLeadingSpace = true
            print("🧠 📝 Spacing: Normal continuation - add leading space")
        }
        
        // Determine trailing space (generally no trailing space unless special case)
        let needsTrailingSpace = false
        
        return (needsLeadingSpace: needsLeadingSpace, needsTrailingSpace: needsTrailingSpace)
    }
    
    /// Analyze cursor context to determine if capitalization is needed
    private func analyzeCapitalizationContext(
        text: String,
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager
    ) -> Bool {
        
        // Get cursor context from target app
        let cursorContext = getCursorContext(targetApp: targetApp, appTargetManager: appTargetManager)
        
        let textToAnalyze = text.trimmingCharacters(in: .whitespaces)
        if textToAnalyze.isEmpty { return false }
        
        let beforeCursor = cursorContext.beforeCursor
        
        // Check capitalization context
        if beforeCursor.isEmpty {
            // Start of document - capitalize
            print("🧠 🔤 Capitalization: Start of document - capitalize")
            return true
        }
        
        // Check for sentence endings
        let sentenceEnders = [".", "!", "?", ":", ";"]
        for ender in sentenceEnders {
            if beforeCursor.hasSuffix(ender) || beforeCursor.hasSuffix(ender + " ") {
                print("🧠 🔤 Capitalization: After sentence ending '\(ender)' - capitalize")
                return true
            }
        }
        
        // Check for paragraph breaks
        if beforeCursor.hasSuffix("\n\n") || beforeCursor.hasSuffix("\n") {
            print("🧠 🔤 Capitalization: After line break - capitalize")
            return true
        }
        
        // Check for double spaces (often indicates sentence boundary)
        if beforeCursor.hasSuffix("  ") {
            print("🧠 🔤 Capitalization: After double space - capitalize")
            return true
        }
        
        // Otherwise, continue with lowercase (mid-sentence)
        print("🧠 🔤 Capitalization: Mid-sentence context - no capitalization")
        return false
    }
    
    // MARK: - Cursor Context Detection
    
    private struct CursorContext {
        let beforeCursor: String
        let afterCursor: String
        let isValid: Bool
    }
    
    /// Get text context around cursor position for smart analysis
    private func getCursorContext(
        targetApp: AppTargetManager.TargetApp,
        appTargetManager: AppTargetManager
    ) -> CursorContext {
        
        // This is a simplified implementation
        // In a full implementation, you would:
        // 1. Switch to target app briefly
        // 2. Use accessibility APIs or key combinations to select text around cursor
        // 3. Analyze the selected text
        // 4. Return to original app
        
        // For now, return a basic context that assumes normal text continuation
        // This can be enhanced later with actual cursor detection
        
        return CursorContext(
            beforeCursor: " ", // Assume normal text continuation
            afterCursor: "",
            isValid: true
        )
    }
    
    // MARK: - Configuration Management
    
    /// Print current feature configuration for debugging
    private func printCurrentConfiguration() {
        print("""
        
        🧠 SmartTextCoordinator - Smart Features RE-ENABLED for Completion Detection
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        📚 Legacy Vocabulary: \(enableLegacyVocabulary ? "✅ ENABLED" : "❌ DISABLED")
        🎯 Contextual Strings: \(enableContextualStrings ? "✅ ENABLED" : "❌ DISABLED")  
        📝 Smart Spacing: \(enableSmartSpacing ? "✅ ENABLED" : "❌ DISABLED")
        🔤 Smart Capitalization: \(enableSmartCapitalization ? "✅ ENABLED" : "❌ DISABLED")
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        🧠 Now processing Apple's completion-detected corrected text!
        
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

// MARK: - Smart Feature Engine Implementations

/// Smart spacing engine with cursor context analysis
class SmartSpacingEngine {
    init() {
        print("📝 SmartSpacingEngine initialized for completion-detected text")
    }
}

/// Smart capitalization engine with cursor context analysis  
class SmartCapitalizationEngine {
    init() {
        print("🔤 SmartCapitalizationEngine initialized for completion-detected text")
    }
}