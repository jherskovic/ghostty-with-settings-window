import AppKit
import SwiftUI

/// The panes of the Settings window, in toolbar order.
enum SettingsPaneID: String, CaseIterable {
    case general
    case appearance
    case text
    case window
    case terminal
    case mouse
    case keyboard
    case quickTerminal
    case advanced

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .text: return "Text"
        case .window: return "Window"
        case .terminal: return "Terminal"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .quickTerminal: return "Quick Terminal"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .text: return "textformat"
        case .window: return "macwindow"
        case .terminal: return "terminal"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .quickTerminal: return "rectangle.tophalf.inset.filled"
        case .advanced: return "gearshape.2"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .text: TextSettingsView()
        case .window: WindowSettingsView()
        case .terminal: TerminalSettingsView()
        case .mouse: MouseSettingsView()
        case .keyboard: KeyboardSettingsView()
        case .quickTerminal: QuickTerminalSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

/// The controller for the Settings window. The window uses a classic macOS
/// preferences toolbar where each item selects a pane.
class SettingsController: NSWindowController, NSWindowDelegate {
    private static var instance: SettingsController?

    private static let selectedPaneKey = "SettingsSelectedPane"

    let model: SettingsModel
    private let tabController = SettingsTabViewController()

    /// Show the settings window, creating it if needed.
    static func show(ghostty: Ghostty.App, pane: SettingsPaneID? = nil) {
        let controller = instance ?? SettingsController(ghostty: ghostty)
        instance = controller
        if let pane { controller.select(pane) }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(ghostty: Ghostty.App) {
        self.model = SettingsModel(ghostty: ghostty)

        tabController.tabStyle = .toolbar
        tabController.transitionOptions = [.allowUserInteraction]
        for pane in SettingsPaneID.allCases {
            let host = NSHostingController(rootView: AnyView(pane.view.environmentObject(model)))
            host.sizingOptions = []
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabController.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 660, height: 420)
        window.setContentSize(NSSize(width: 700, height: 640))
        window.identifier = NSUserInterfaceItemIdentifier("com.mitchellh.ghostty.settings")
        window.center()
        window.setFrameAutosaveName("GhosttySettingsWindow")

        super.init(window: window)
        window.delegate = self

        if let raw = UserDefaults.ghostty.string(forKey: Self.selectedPaneKey),
           let pane = SettingsPaneID(rawValue: raw) {
            select(pane)
        }
        tabController.onSelect = { pane in
            UserDefaults.ghostty.set(pane.rawValue, forKey: Self.selectedPaneKey)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func select(_ pane: SettingsPaneID) {
        guard let index = SettingsPaneID.allCases.firstIndex(of: pane) else { return }
        tabController.selectedTabViewItemIndex = index
    }

    // MARK: First Responder

    @IBAction func close(_ sender: Any) {
        window?.performClose(sender)
    }

    @IBAction func closeWindow(_ sender: Any) {
        window?.performClose(sender)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Pick up any changes made in a text editor while we were away.
        model.reloadFromDisk()
        ThemeLibrary.shared.invalidate()
    }

    func windowWillClose(_ notification: Notification) {
        model.save()
    }
}

/// A tab view controller that reports pane selection changes.
private class SettingsTabViewController: NSTabViewController {
    var onSelect: ((SettingsPaneID) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let raw = tabViewItem?.identifier as? String,
              let pane = SettingsPaneID(rawValue: raw) else { return }
        onSelect?(pane)
    }
}
