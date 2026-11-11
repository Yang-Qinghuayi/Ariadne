import AppKit
import ApplicationServices
import AriadneCore
import Carbon.HIToolbox
import Combine
import Foundation

public enum HotKeyRegistrationStatus: Equatable {
    case registered
    case suspended
    case needsAccessibilityPermission
    case failed(OSStatus)

    public var isActive: Bool {
        if case .registered = self { return true }
        return false
    }
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    @Published private(set) var status: HotKeyRegistrationStatus = .suspended
    @Published private(set) var currentHotKey: HotKeyDescriptor

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var accessibilityPollTimer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?

    private let doubleTapDetector = DoubleTapModifierDetector()
    private var isSuspended = false
    private let onTrigger: () -> Void

    private static let signature: FourCharCode = 0x4152_4941 // 'ARIA'
    private static let hotKeyIDValue: UInt32 = 1

    init(initialHotKey: HotKeyDescriptor, onTrigger: @escaping () -> Void) {
        self.currentHotKey = initialHotKey
        self.onTrigger = onTrigger
        installHandlerIfNeeded()
        installAppActiveObserver()
        register(initialHotKey)
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        accessibilityPollTimer?.invalidate()
        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func register(_ descriptor: HotKeyDescriptor) {
        currentHotKey = descriptor
        unregisterCurrentHotKey()
        stopDoubleTapMonitoring()

        guard !isSuspended else {
            status = .suspended
            return
        }

        switch descriptor.kind {
        case .keyCombo:
            registerCarbonHotKey(descriptor)
        case .doubleTapModifier:
            startDoubleTapMonitoring(modifier: descriptor.doubleTapModifier ?? .command)
        }
    }

    func suspend() {
        isSuspended = true
        unregisterCurrentHotKey()
        stopDoubleTapMonitoring()
        status = .suspended
    }

    func resume(with descriptor: HotKeyDescriptor? = nil) {
        isSuspended = false
        register(descriptor ?? currentHotKey)
    }

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            if !isSuspended, currentHotKey.kind == .doubleTapModifier {
                register(currentHotKey)
            }
            return
        }
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    // MARK: - Carbon Key Combo

    private func registerCarbonHotKey(_ descriptor: HotKeyDescriptor) {
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyIDValue)
        var newRef: EventHotKeyRef?
        let osStatus = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if osStatus == noErr, let newRef {
            hotKeyRef = newRef
            status = .registered
        } else {
            hotKeyRef = nil
            status = .failed(osStatus)
        }
    }

    private func unregisterCurrentHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            &eventType,
            userData,
            &ref
        )

        if result == noErr {
            eventHandlerRef = ref
        }
    }

    fileprivate func handleCarbonHotKeyEvent(id: UInt32) {
        guard id == Self.hotKeyIDValue, !isSuspended, currentHotKey.kind == .keyCombo else { return }
        onTrigger()
    }

    // MARK: - Double-Tap Modifier Monitoring

    private func startDoubleTapMonitoring(modifier: ModifierTapKey) {
        doubleTapDetector.targetModifier = modifier
        doubleTapDetector.reset()

        let mask: NSEvent.EventTypeMask = [
            .flagsChanged,
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitoredEvent(event)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitoredEvent(event)
            return event
        }

        updateAccessibilityStatusAndPolling()
    }

    private func stopDoubleTapMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        doubleTapDetector.reset()
    }

    private func handleMonitoredEvent(_ event: NSEvent) {
        guard !isSuspended, currentHotKey.kind == .doubleTapModifier else { return }

        switch event.type {
        case .flagsChanged:
            if doubleTapDetector.processFlagsChanged(
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp
            ) != nil {
                onTrigger()
            }
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            doubleTapDetector.processInterruptingEvent()
        default:
            break
        }
    }

    private func installAppActiveObserver() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityTrustState()
            }
        }
    }

    private func updateAccessibilityStatusAndPolling() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            status = .registered
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        } else {
            status = .needsAccessibilityPermission
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAccessibilityTrustState()
                }
            }
        }
    }

    private func refreshAccessibilityTrustState() {
        guard !isSuspended, currentHotKey.kind == .doubleTapModifier else { return }
        let trusted = AXIsProcessTrusted()
        if trusted && status == .needsAccessibilityPermission {
            // Re-install global monitors now that Accessibility trust is granted
            let activeHotKey = currentHotKey
            register(activeHotKey)
        } else if !trusted && status == .registered {
            updateAccessibilityStatusAndPolling()
        }
    }
}

private func hotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return status
    }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleCarbonHotKeyEvent(id: hotKeyID.id)
    }

    return noErr
}
