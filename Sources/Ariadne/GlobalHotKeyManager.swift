import AriadneCore
import Carbon.HIToolbox
import Combine
import Foundation

public enum HotKeyRegistrationStatus: Equatable {
    case registered
    case suspended
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
    private var isSuspended = false
    private let onTrigger: () -> Void

    private static let signature: FourCharCode = 0x4152_4941 // 'ARIA'
    private static let hotKeyIDValue: UInt32 = 1

    init(initialHotKey: HotKeyDescriptor, onTrigger: @escaping () -> Void) {
        self.currentHotKey = initialHotKey
        self.onTrigger = onTrigger
        installHandlerIfNeeded()
        register(initialHotKey)
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    func register(_ descriptor: HotKeyDescriptor) {
        currentHotKey = descriptor
        unregisterCurrentHotKey()

        guard !isSuspended else {
            status = .suspended
            return
        }

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

    func suspend() {
        isSuspended = true
        unregisterCurrentHotKey()
        status = .suspended
    }

    func resume() {
        isSuspended = false
        register(currentHotKey)
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
        guard id == Self.hotKeyIDValue, !isSuspended else { return }
        onTrigger()
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
