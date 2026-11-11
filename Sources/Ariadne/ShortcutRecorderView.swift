import AppKit
import AriadneCore
import Carbon.HIToolbox
import SwiftUI

@MainActor
private final class ShortcutRecorderController: ObservableObject {
    @Published var isRecording = false
    @Published var liveModifierTokens: [String] = []
    @Published var pendingDoubleTapModifier: ModifierTapKey?
    @Published var validationHint: String?

    private var keyDownMonitor: Any?
    private var flagsChangedMonitor: Any?
    private weak var hotKeyManager: GlobalHotKeyManager?
    private let doubleTapDetector = DoubleTapModifierDetector(targetModifier: nil)

    func toggleRecording(
        hotKeyManager: GlobalHotKeyManager,
        onCaptured: @escaping (HotKeyDescriptor) -> Void
    ) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(hotKeyManager: hotKeyManager, onCaptured: onCaptured)
        }
    }

    func startRecording(
        hotKeyManager: GlobalHotKeyManager,
        onCaptured: @escaping (HotKeyDescriptor) -> Void
    ) {
        stopRecording()
        self.hotKeyManager = hotKeyManager
        hotKeyManager.suspend()
        doubleTapDetector.reset()
        isRecording = true
        liveModifierTokens = []
        pendingDoubleTapModifier = nil
        validationHint = nil

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.isRecording else { return event }

            let relevant = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let carbon = KeyCodeTranslator.carbonModifiers(from: relevant)
            self.liveModifierTokens = KeyCodeTranslator.modifierTokens(carbonModifiers: carbon)

            if let doubleTapped = self.doubleTapDetector.processFlagsChanged(
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp
            ) {
                let descriptor = HotKeyDescriptor.doubleTap(doubleTapped)
                self.stopRecording(resumeHotKey: false)
                onCaptured(descriptor)
                return nil
            }

            if case .firstTapReleased(let mod, _) = self.doubleTapDetector.state {
                self.pendingDoubleTapModifier = mod
            } else if case .secondPressDown(let mod, _) = self.doubleTapDetector.state {
                self.pendingDoubleTapModifier = mod
            } else {
                self.pendingDoubleTapModifier = nil
            }

            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }

            self.doubleTapDetector.processInterruptingEvent()
            self.pendingDoubleTapModifier = nil

            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])

            if keyCode == UInt32(kVK_Escape) && flags.isEmpty {
                self.stopRecording()
                return nil
            }

            if KeyCodeTranslator.isModifierOnlyKeyCode(event.keyCode) {
                return nil
            }

            let hasPrimaryModifier = !flags.intersection([.command, .option, .control]).isEmpty
            let isFunctionKey = KeyCodeTranslator.isFunctionKeyCode(keyCode)

            guard hasPrimaryModifier || isFunctionKey else {
                self.validationHint = "Include ⌘, ⌥, or ⌃ (or double-tap ⌘ / ⌥ / ⌃ / ⇧)"
                NSSound.beep()
                return nil
            }

            let carbonMods = KeyCodeTranslator.carbonModifiers(from: flags)
            let descriptor = HotKeyDescriptor(keyCode: keyCode, carbonModifiers: carbonMods)
            self.stopRecording(resumeHotKey: false)
            onCaptured(descriptor)
            return nil
        }
    }

    func stopRecording(resumeHotKey: Bool = true) {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        doubleTapDetector.reset()
        isRecording = false
        liveModifierTokens = []
        pendingDoubleTapModifier = nil
        if resumeHotKey {
            hotKeyManager?.resume()
        }
    }

    deinit {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

struct ShortcutRecorderView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var hotKeyManager: GlobalHotKeyManager
    @StateObject private var recorder = ShortcutRecorderController()

    private let presets: [(String, HotKeyDescriptor)] = [
        ("⌥ Space", .defaultLauncher),
        ("⌘ ⌘", .doubleTap(.command)),
        ("⌥ ⌥", .doubleTap(.option)),
        ("⌘⇧ Space", HotKeyDescriptor(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))),
        ("⌃ Space", HotKeyDescriptor(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey)))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    recorder.toggleRecording(hotKeyManager: hotKeyManager) { captured in
                        settingsStore.hotKey = captured
                        hotKeyManager.resume(with: captured)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if recorder.isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            if let pendingMod = recorder.pendingDoubleTapModifier {
                                Text("Tap \(pendingMod.symbol) again for \(pendingMod.symbol) \(pendingMod.symbol)…")
                                    .font(.system(size: 12.5, weight: .semibold))
                            } else if recorder.liveModifierTokens.isEmpty {
                                Text("Press shortcut or double-tap ⌘…")
                                    .font(.system(size: 12.5, weight: .medium))
                            } else {
                                Text(recorder.liveModifierTokens.joined(separator: " ") + " …")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            }
                        } else {
                            ForEach(Array(settingsStore.hotKey.displayTokens.enumerated()), id: \.offset) { _, token in
                                Text(token)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(Color.primary.opacity(0.09))
                                    )
                            }
                            Text("Click to change")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(recorder.isRecording ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                recorder.isRecording ? Color.accentColor : Color.primary.opacity(0.18),
                                lineWidth: recorder.isRecording ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)

                statusBadge

                Spacer()

                if settingsStore.hotKey != .defaultLauncher {
                    Button("Reset") {
                        recorder.stopRecording(resumeHotKey: false)
                        settingsStore.resetHotKeyToDefault()
                        hotKeyManager.resume(with: .defaultLauncher)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if recorder.isRecording {
                Text("Supports combos (e.g. ⌥ Space) or double-tapping a modifier (⌘ ⌘, ⌥ ⌥, ⌃ ⌃, ⇧ ⇧). Press Esc to cancel.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let hint = recorder.validationHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if hotKeyManager.status == .needsAccessibilityPermission {
                HStack(spacing: 8) {
                    Text("Double-tap modifier shortcuts need macOS Accessibility access to monitor keys across apps without interfering with ⌘C / ⌘V.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Grant Access…") {
                        hotKeyManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            HStack(spacing: 6) {
                Text("Presets:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(presets, id: \.0) { label, descriptor in
                    Button(label) {
                        recorder.stopRecording(resumeHotKey: false)
                        settingsStore.hotKey = descriptor
                        hotKeyManager.resume(with: descriptor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(settingsStore.hotKey == descriptor && !recorder.isRecording)
                }
            }
        }
        .onDisappear {
            recorder.stopRecording()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch hotKeyManager.status {
        case .registered:
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.green)
        case .suspended:
            Label("Recording", systemImage: "record.circle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        case .needsAccessibilityPermission:
            Label("Needs Accessibility", systemImage: "lock.shield")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.orange)
        case .failed:
            Label("Conflict — pick another", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.orange)
        }
    }
}
