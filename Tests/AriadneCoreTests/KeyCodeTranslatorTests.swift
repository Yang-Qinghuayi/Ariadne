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

    func testDoubleTapHotKeyDescriptorFormattingAndBackwardCompatibleCodable() throws {
        let doubleCmd = HotKeyDescriptor.doubleCommand
        XCTAssertEqual(doubleCmd.kind, .doubleTapModifier)
        XCTAssertEqual(doubleCmd.doubleTapModifier, .command)
        XCTAssertEqual(doubleCmd.displayString, "⌘ ⌘")
        XCTAssertEqual(doubleCmd.displayTokens, ["⌘", "⌘"])

        let encoded = try JSONEncoder().encode(doubleCmd)
        let decoded = try JSONDecoder().decode(HotKeyDescriptor.self, from: encoded)
        XCTAssertEqual(decoded, doubleCmd)

        // Legacy persisted JSON without 'kind' field
        let legacyJSON = #"{"keyCode":49,"carbonModifiers":2048}"#.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(HotKeyDescriptor.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded, .defaultLauncher)
        XCTAssertEqual(legacyDecoded.kind, .keyCombo)
    }

    func testModifierTapKeyLookup() {
        XCTAssertEqual(KeyCodeTranslator.modifierTapKey(for: UInt16(kVK_Command)), .command)
        XCTAssertEqual(KeyCodeTranslator.modifierTapKey(for: 0x36), .command)
        XCTAssertEqual(KeyCodeTranslator.modifierTapKey(for: UInt16(kVK_Option)), .option)
        XCTAssertEqual(KeyCodeTranslator.modifierTapKey(for: UInt16(kVK_Control)), .control)
        XCTAssertEqual(KeyCodeTranslator.modifierTapKey(for: UInt16(kVK_Shift)), .shift)
        XCTAssertNil(KeyCodeTranslator.modifierTapKey(for: UInt16(kVK_Space)))
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

        reloaded.hotKey = .doubleCommand
        let reloadedDoubleTap = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloadedDoubleTap.hotKey, .doubleCommand)
    }
}
