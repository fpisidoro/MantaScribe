import Cocoa

/// Main view controller for MantaScribe preferences
/// Provides a Mac-like preferences interface following HIG guidelines
class PreferencesViewController: NSViewController {
    
    // MARK: - Outlets (will be connected after creating the view)
    
    private var scrollView: NSScrollView!
    private var contentView: NSView!
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        // Create the main view
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
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
        // Create a placeholder message for now
        let titleLabel = NSTextField(labelWithString: "MantaScribe Preferences")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let messageLabel = NSTextField(labelWithString: "Preferences will be organized here as we develop the app.\nFor now, this window is ready for future preference controls.")
        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.textColor = NSColor.secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let versionLabel = NSTextField(labelWithString: "MantaScribe v1.0")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = NSColor.tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add sample preference sections (placeholders)
        let generalSectionLabel = createSectionLabel("General")
        let dictationSectionLabel = createSectionLabel("Dictation")
        let advancedSectionLabel = createSectionLabel("Advanced")
        
        // Add all to content view
        contentView.addSubview(titleLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(versionLabel)
        contentView.addSubview(generalSectionLabel)
        contentView.addSubview(dictationSectionLabel)
        contentView.addSubview(advancedSectionLabel)
        
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
            
            // Advanced section
            advancedSectionLabel.topAnchor.constraint(equalTo: dictationSectionLabel.bottomAnchor, constant: 40),
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
    
    // MARK: - Future Preference Controls
    
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
    
    // MARK: - Notification Handlers
    
    @objc private func preferenceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    private func updateUI() {
        // This will update UI controls when preferences change
        // Will be implemented as we add actual preference controls
        print("🔧 Updating preferences UI")
    }
    
    // MARK: - Future Action Methods
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        // Handle checkbox state changes
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
        updateUI()
    }
    
    /// Validate all current preference values
    func validatePreferences() -> Bool {
        // Future: validate preference combinations
        return true
    }
}