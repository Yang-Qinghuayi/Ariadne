import AppKit
import AriadneCore
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let showLauncherNotification = Notification.Name("com.ariadne.launcher.show")

    private var statusItem: NSStatusItem?
    private var openLauncherMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    private var settingsStore: AppSettingsStore!
    private var projectLauncher: ProjectLauncher!
    private var launcherViewModel: LauncherViewModel!
    private var panelController: LauncherPanelController!
    private var hotKeyManager: GlobalHotKeyManager!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfAlreadyRunning() {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        let store = AppSettingsStore()
        let launcher = ProjectLauncher()
        let viewModel = LauncherViewModel(settingsStore: store, launcher: launcher)

        self.settingsStore = store
        self.projectLauncher = launcher
        self.launcherViewModel = viewModel
        self.panelController = LauncherPanelController(viewModel: viewModel, settingsStore: store)

        self.hotKeyManager = GlobalHotKeyManager(initialHotKey: store.hotKey) { [weak self] in
            self?.panelController.toggle()
        }

        viewModel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        setupStatusItem()
        observeNotifications()
        observeHotKeyChanges()

        store.hasLaunchedBefore = true
        panelController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.suspend()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Single Instance

    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }

        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.showLauncherNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return true
        }
        return false
    }

    private func observeNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalShowRequest),
            name: Self.showLauncherNotification,
            object: nil
        )
    }

    @objc private func handleExternalShowRequest() {
        panelController?.show()
    }

    private func observeHotKeyChanges() {
        settingsStore.$hotKey
            .dropFirst()
            .sink { [weak self] descriptor in
                self?.hotKeyManager.register(descriptor)
                self?.updateMenuTitles()
            }
            .store(in: &cancellables)
    }

    // MARK: - Main Menu (Enables Copy/Paste/Select All)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ariadne", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "point.3.connected.trianglepath.dotted",
                accessibilityDescription: "Ariadne"
            ) ?? NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: "Ariadne"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Ariadne — VS Code & Kitty Project Launcher"
        }

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(
            title: "Open Launcher",
            action: #selector(showLauncherFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        self.openLauncherMenuItem = openItem

        let accessibilityItem = NSMenuItem(
            title: "Grant Accessibility Permission…",
            action: #selector(requestAccessibilityFromMenu),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        accessibilityItem.isHidden = true
        menu.addItem(accessibilityItem)
        self.accessibilityMenuItem = accessibilityItem

        let refreshItem = NSMenuItem(
            title: "Refresh Projects",
            action: #selector(refreshProjectsFromMenu),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)
        self.launchAtLoginMenuItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ariadne",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
        updateMenuTitles()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuTitles()
    }

    private func updateMenuTitles() {
        openLauncherMenuItem?.title = "Open Launcher (\(settingsStore.hotKey.displayString))"
        let needsAccessibility = hotKeyManager.status == .needsAccessibilityPermission
        accessibilityMenuItem?.isHidden = !needsAccessibility
        accessibilityMenuItem?.title = "Grant Accessibility for \(settingsStore.hotKey.displayString)…"
        launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func requestAccessibilityFromMenu() {
        hotKeyManager.requestAccessibilityPermission()
    }

    @objc private func showLauncherFromMenu() {
        panelController.show()
    }

    @objc private func refreshProjectsFromMenu() {
        launcherViewModel.refreshProjects()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Launch at Login"
            if !Bundle.main.bundlePath.hasSuffix(".app") {
                alert.informativeText = "Launch at Login can only be enabled when running the packaged Ariadne.app bundle."
            } else {
                alert.informativeText = error.localizedDescription
            }
            alert.runModal()
        }
        updateMenuTitles()
    }

    @objc func openSettings() {
        panelController.hide(restorePreviousApp: false)

        if settingsWindow == nil {
            let settingsView = SettingsView(
                settingsStore: settingsStore,
                hotKeyManager: hotKeyManager,
                launcherViewModel: launcherViewModel,
                launcher: projectLauncher
            )
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Ariadne Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.settingsWindow = window
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
