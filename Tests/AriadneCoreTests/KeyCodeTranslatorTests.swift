import AppKit
import AriadneCore
import Carbon.HIToolbox
import XCTest

final class KeyCodeTranslatorTests: XCTestCase {
    func testCarbonModifierRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .shift]
        let carbon = KeyCodeTranslator.carbonModifiers(from: flags)
        XCTAssertEqual(carbon, UInt32(cmdKey | optionKey | shiftKey))

        let roundTripped = KeyCodeTranslator.modifierFlags(from: carbon)
        XCTAssertEqual(roundTripped, flags)
    }

    func testFormatsDefaultLauncherHotKey() {
        let hotKey = HotKeyDescriptor.defaultLauncher
        XCTAssertEqual(hotKey.displayString, "⌥ Space")
        XCTAssertEqual(hotKey.displayTokens, ["⌥", "Space"])
    }

    func testFormatsComplexShortcut() {
        let hotKey = HotKeyDescriptor(
            keyCode: UInt32(kVK_ANSI_P),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(hotKey.displayString, "⌃⌥⇧⌘ P")
    }

    @MainActor
    func testAppSettingsStorePersistsValues() {
        let suiteName = "AriadneSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.hotKey, .defaultLauncher)
        XCTAssertEqual(store.defaultEnterAction, .vscode)
        XCTAssertEqual(store.kittyLaunchMode, .newOSWindow)

        let customHotKey = HotKeyDescriptor(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | shiftKey))
        store.hotKey = customHotKey
        store.defaultEnterAction = .both
        store.kittyLaunchMode = .newTab
        store.togglePin(for: "/tmp/demo")

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotKey, customHotKey)
        XCTAssertEqual(reloaded.defaultEnterAction, .both)
        XCTAssertEqual(reloaded.kittyLaunchMode, .newTab)
        XCTAssertTrue(reloaded.pinnedPaths.contains("/tmp/demo"))
    }
}
