import AppKit
import AriadneCore
import Carbon.HIToolbox
import Combine
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
    private let panel: LauncherPanel
    private let viewModel: LauncherViewModel
    private var hostingController: NSHostingController<LauncherView>!
    private weak var searchField: NSTextField?
    private weak var previousFrontmostApp: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private let panelWidth: CGFloat = 680

    init(viewModel: LauncherViewModel, settingsStore: AppSettingsStore) {
        self.viewModel = viewModel
        self.panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        let rootView = LauncherView(
            viewModel: viewModel,
            settingsStore: settingsStore,
            onSearchFieldReady: { [weak self] field in
                self?.searchField = field
                self?.focusSearchField()
            }
        )
        self.hostingController = NSHostingController(rootView: rootView)

        self.panel.delegate = self
        self.panel.isFloatingPanel = true
        self.panel.level = .floating
        self.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel.isOpaque = false
        self.panel.backgroundColor = .clear
        self.panel.hasShadow = true
        self.panel.isMovableByWindowBackground = false
        self.panel.hidesOnDeactivate = false
        self.panel.becomesKeyOnlyIfNeeded = false

        self.hostingController.view.wantsLayer = true
        self.hostingController.view.layer?.cornerRadius = 16
        self.hostingController.view.layer?.masksToBounds = true
        self.panel.contentViewController = self.hostingController

        viewModel.onDismiss = { [weak self] in
            self?.hide(restorePreviousApp: true)
        }

        // Resize panel height smoothly whenever displayed rows/banners change
        Publishers.CombineLatest4(
            viewModel.$filteredProjects,
            viewModel.$showingActionMenu,
            viewModel.$errorMessage,
            viewModel.$statusToast
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.scheduleLayoutResize()
        }
        .store(in: &cancellables)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if panel.isVisible {
            hide(restorePreviousApp: true)
        } else {
            show()
        }
    }

    func show() {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            previousFrontmostApp = frontApp
        }

        viewModel.prepareForDisplay()
        positionPanelOnActiveScreen(initialShow: true)
        installLocalKeyMonitor()

        panel.makeKeyAndOrderFront(nil)
        if !panel.isKeyWindow {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            panel.makeKeyAndOrderFront(nil)
        }

        focusSearchField()
        scheduleLayoutResize()
    }

    func hide(restorePreviousApp: Bool) {
        removeLocalKeyMonitor()
        if panel.isVisible {
            panel.orderOut(nil)
        }
        if restorePreviousApp, let previousApp = previousFrontmostApp, !previousApp.isTerminated {
            if NSApp.isActive {
                previousApp.activate(options: [])
            }
        }
        previousFrontmostApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide(restorePreviousApp: false)
    }

    private func focusSearchField() {
        guard panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, let searchField = self.searchField else { return }
            self.panel.makeFirstResponder(searchField)
            if let editor = searchField.currentEditor() {
                let len = (searchField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
    }

    private func scheduleLayoutResize() {
        guard panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updatePanelHeightKeepingTopAnchored()
        }
    }

    private func positionPanelOnActiveScreen(initialShow: Bool) {
        let screen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let targetHeight = computePanelHeight()
        let x = round(visibleFrame.midX - panelWidth / 2)
        let topY = round(visibleFrame.maxY - visibleFrame.height * 0.18)
        let y = max(visibleFrame.minY + 24, topY - targetHeight)

        let frame = NSRect(x: x, y: y, width: panelWidth, height: targetHeight)
        panel.setFrame(frame, display: !initialShow)
    }

    private func updatePanelHeightKeepingTopAnchored() {
        let currentFrame = panel.frame
        let targetHeight = computePanelHeight()
        guard abs(currentFrame.height - targetHeight) > 1 else { return }

        let currentTop = currentFrame.maxY
        let screenMinY = (panel.screen ?? activeScreen())?.visibleFrame.minY ?? 0
        let newY = max(screenMinY + 24, currentTop - targetHeight)
        let newFrame = NSRect(x: currentFrame.origin.x, y: newY, width: panelWidth, height: targetHeight)
        panel.setFrame(newFrame, display: true)
    }

    private func computePanelHeight() -> CGFloat {
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingHeight = hostingController.view.fittingSize.height
        if fittingHeight > 120 {
            return min(fittingHeight, 620)
        }
        return 300
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Local Key Monitor

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyEvent(event)
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.window === panel else {
            return event
        }

        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        // ⌘, -> Open Settings
        if flags == [.command], keyCode == kVK_ANSI_Comma {
            viewModel.onOpenSettings?()
            return nil
        }

        // ⌘R -> Refresh projects
        if flags == [.command], keyCode == kVK_ANSI_R {
            viewModel.refreshProjects()
            return nil
        }

        // ⌘P -> Pin/Unpin selected project
        if flags == [.command], keyCode == kVK_ANSI_P {
            viewModel.togglePinSelected()
            return nil
        }

        // ⌘K -> Toggle Actions Menu
        if flags == [.command], keyCode == kVK_ANSI_K {
            viewModel.toggleActionMenu()
            return nil
        }

        // ⌃N / ⌃P -> Next / Previous selection
        if flags == [.control], keyCode == kVK_ANSI_N {
            viewModel.moveSelectionDown()
            return nil
        }
        if flags == [.control], keyCode == kVK_ANSI_P {
            viewModel.moveSelectionUp()
            return nil
        }

        // ⌘⏎ / ⌥⏎ -> Kitty / Both
        if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
            if flags.contains(.command) || flags.contains(.option) {
                viewModel.triggerReturn(
                    commandPressed: flags.contains(.command),
                    optionPressed: flags.contains(.option)
                )
                return nil
            }
        }

        // ⌘1 .. ⌘9 -> Quick launch row 1..9
        if flags == [.command], let index = numberKeyIndex(for: keyCode) {
            viewModel.triggerQuickIndex(index)
            return nil
        }

        return event
    }

    private func numberKeyIndex(for keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }
}
