import Cocoa

/// Main view controller for MantaScribe preferences
/// Provides a Mac-like preferences interface following HIG guidelines
class PreferencesViewController: NSViewController {
    
    // MARK: - Outlets
    
    private var scrollView: NSScrollView!
    private var contentView: NSView!
    
    // Smart Text Developer controls
    private var legacyVocabularyCheckbox: NSButton!
    private var contextualStringsCheckbox: NSButton!
    private var smartSpacingCheckbox: NSButton!
    private var smartCapitalizationCheckbox: NSButton!
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        // Create the main view
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        setupUI()
        setupConstraints()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Listen for preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferenceDidChange(_:)),
            name: PreferencesManager.preferenceDidChangeNotification,
            object: nil
        )
        
        // Load current preference values
        updateUIFromPreferences()
        
        print("🔧 PreferencesViewController loaded")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Create scroll view for future expansion
        scrollView = NSScrollView(frame: view.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create content view
        contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to hierarchy
        view.addSubview(scrollView)
        scrollView.documentView = contentView
        
        setupPreferencesContent()
    }
    
    private func setupConstraints() {
        // Scroll view constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Content view constraints
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor)
        ])
    }
    
    private func setupPreferencesContent() {
        // Create main title
        let titleLabel = NSTextField(labelWithString: "MantaScribe Preferences")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Create section labels
        let generalSectionLabel = createSectionLabel("General")
        let dictationSectionLabel = createSectionLabel("Dictation")
        let developerSectionLabel = createSectionLabel("Developer")
        let advancedSectionLabel = createSectionLabel("Advanced")
        
        // Create developer section description
        let developerDescriptionLabel = NSTextField(labelWithString: "Toggle individual SmartText features for testing and debugging")
        developerDescriptionLabel.font = NSFont.systemFont(ofSize: 11)
        developerDescriptionLabel.textColor = NSColor.secondaryLabelColor
        developerDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Create Smart Text feature checkboxes
        legacyVocabularyCheckbox = createCheckbox(
            title: "Legacy Vocabulary Processing",
            action: #selector(legacyVocabularyToggled(_:))
        )
        
        contextualStringsCheckbox = createCheckbox(
            title: "Contextual Strings (Medical Vocabulary)",
            action: #selector(contextualStringsToggled(_:))
        )
        
        smartSpacingCheckbox = createCheckbox(
            title: "Smart Spacing Engine",
            action: #selector(smartSpacingToggled(_:))
        )
        
        smartCapitalizationCheckbox = createCheckbox(
            title: "Smart Capitalization Engine",
            action: #selector(smartCapitalizationToggled(_:))
        )
        
        // Create placeholder message for other sections
        let messageLabel = NSTextField(labelWithString: "Additional preferences will be organized here as features are developed.\nFor now, you can control the SmartText processing features below.")
        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.textColor = NSColor.secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Create version label
        let versionLabel = NSTextField(labelWithString: "MantaScribe v1.0")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = NSColor.tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add all to content view
        contentView.addSubview(titleLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(generalSectionLabel)
        contentView.addSubview(dictationSectionLabel)
        contentView.addSubview(developerSectionLabel)
        contentView.addSubview(developerDescriptionLabel)
        contentView.addSubview(legacyVocabularyCheckbox)
        contentView.addSubview(contextualStringsCheckbox)
        contentView.addSubview(smartSpacingCheckbox)
        contentView.addSubview(smartCapitalizationCheckbox)
        contentView.addSubview(advancedSectionLabel)
        contentView.addSubview(versionLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // General section
            generalSectionLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 30),
            generalSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Dictation section
            dictationSectionLabel.topAnchor.constraint(equalTo: generalSectionLabel.bottomAnchor, constant: 40),
            dictationSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Developer section
            developerSectionLabel.topAnchor.constraint(equalTo: dictationSectionLabel.bottomAnchor, constant: 40),
            developerSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Developer description
            developerDescriptionLabel.topAnchor.constraint(equalTo: developerSectionLabel.bottomAnchor, constant: 8),
            developerDescriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            developerDescriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Smart Text checkboxes
            legacyVocabularyCheckbox.topAnchor.constraint(equalTo: developerDescriptionLabel.bottomAnchor, constant: 15),
            legacyVocabularyCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            
            contextualStringsCheckbox.topAnchor.constraint(equalTo: legacyVocabularyCheckbox.bottomAnchor, constant: 8),
            contextualStringsCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            
            smartSpacingCheckbox.topAnchor.constraint(equalTo: contextualStringsCheckbox.bottomAnchor, constant: 8),
            smartSpacingCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            
            smartCapitalizationCheckbox.topAnchor.constraint(equalTo: smartSpacingCheckbox.bottomAnchor, constant: 8),
            smartCapitalizationCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            
            // Advanced section
            advancedSectionLabel.topAnchor.constraint(equalTo: smartCapitalizationCheckbox.bottomAnchor, constant: 30),
            advancedSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            // Version
            versionLabel.topAnchor.constraint(equalTo: advancedSectionLabel.bottomAnchor, constant: 40),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    private func createSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    // MARK: - UI Control Creation
    
    private func createCheckbox(title: String, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        return checkbox
    }
    
    private func createPopUpButton(items: [String], action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24), pullsDown: false)
        popup.addItems(withTitles: items)
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }
    
    private func createSlider(minValue: Double, maxValue: Double, currentValue: Double, action: Selector) -> NSSlider {
        let slider = NSSlider(target: self, action: action)
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = currentValue
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }
    
    // MARK: - Smart Text Action Methods
    
    @objc private func legacyVocabularyToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        PreferencesManager.shared.enableLegacyVocabulary = enabled
        print("🔧 Legacy Vocabulary toggled: \(enabled ? "ON" : "OFF")")
    }
    
    @objc private func contextualStringsToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        PreferencesManager.shared.enableContextualStrings = enabled
        print("🔧 Contextual Strings toggled: \(enabled ? "ON" : "OFF")")
    }
    
    @objc private func smartSpacingToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        PreferencesManager.shared.enableSmartSpacing = enabled
        print("🔧 Smart Spacing toggled: \(enabled ? "ON" : "OFF")")
    }
    
    @objc private func smartCapitalizationToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        PreferencesManager.shared.enableSmartCapitalization = enabled
        print("🔧 Smart Capitalization toggled: \(enabled ? "ON" : "OFF")")
    }
    
    // MARK: - Notification Handlers
    
    @objc private func preferenceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUIFromPreferences()
        }
    }
    
    private func updateUIFromPreferences() {
        // Update Smart Text checkboxes to match current preference values
        legacyVocabularyCheckbox?.state = PreferencesManager.shared.enableLegacyVocabulary ? .on : .off
        contextualStringsCheckbox?.state = PreferencesManager.shared.enableContextualStrings ? .on : .off
        smartSpacingCheckbox?.state = PreferencesManager.shared.enableSmartSpacing ? .on : .off
        smartCapitalizationCheckbox?.state = PreferencesManager.shared.enableSmartCapitalization ? .on : .off
        
        print("🔧 Preferences UI updated from current settings")
    }
    
    // MARK: - Future Action Methods (Placeholders)
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        // Handle checkbox state changes for future preferences
        print("🔧 Checkbox toggled: \(sender.title) = \(sender.state == .on)")
    }
    
    @objc private func popupSelectionChanged(_ sender: NSPopUpButton) {
        // Handle popup selection changes
        print("🔧 Popup changed: \(sender.titleOfSelectedItem ?? "unknown")")
    }
    
    @objc private func sliderValueChanged(_ sender: NSSlider) {
        // Handle slider value changes
        print("🔧 Slider changed: \(sender.doubleValue)")
    }
    
    // MARK: - Utility Methods
    
    /// Refresh all preference controls to match current settings
    func refreshFromPreferences() {
        updateUIFromPreferences()
    }
    
    /// Validate all current preference values
    func validatePreferences() -> Bool {
        // Future: validate preference combinations
        return true
    }
}
