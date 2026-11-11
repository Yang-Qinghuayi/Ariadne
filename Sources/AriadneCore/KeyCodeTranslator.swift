import AppKit
import Carbon.HIToolbox
import Foundation

public enum KeyCodeTranslator {
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    public static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    public static func modifierTokens(carbonModifiers: UInt32) -> [String] {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts
    }

    public static func tokens(keyCode: UInt32, carbonModifiers: UInt32) -> [String] {
        modifierTokens(carbonModifiers: carbonModifiers) + [keyString(for: keyCode)]
    }

    public static func format(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        let mods = modifierTokens(carbonModifiers: carbonModifiers).joined()
        let key = keyString(for: keyCode)
        return mods.isEmpty ? key : "\(mods) \(key)"
    }

    public static func modifierTapKey(for keyCode: UInt16) -> ModifierTapKey? {
        switch Int(keyCode) {
        case kVK_Command, 0x36:
            return .command
        case kVK_Option, kVK_RightOption:
            return .option
        case kVK_Control, kVK_RightControl:
            return .control
        case kVK_Shift, kVK_RightShift:
            return .shift
        default:
            return nil
        }
    }

    public static func singleModifierTapKey(from flags: NSEvent.ModifierFlags) -> ModifierTapKey? {
        let relevant = flags.intersection([.command, .option, .control, .shift])
        switch relevant {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        case .shift:
            return .shift
        default:
            return nil
        }
    }

    public static func isModifierOnlyKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, 0x36, // Left & Right Command
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    public static func isFunctionKeyCode(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
             kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
             kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18,
             kVK_F19, kVK_F20:
            return true
        default:
            return false
        }
    }

    public static func keyString(for keyCode: UInt32) -> String {
        if let mapped = keyMap[Int(keyCode)] {
            return mapped
        }
        return "Key(\(keyCode))"
    }

    private static let keyMap: [Int: String] = [
        kVK_ANSI_A: "A",
        kVK_ANSI_B: "B",
        kVK_ANSI_C: "C",
        kVK_ANSI_D: "D",
        kVK_ANSI_E: "E",
        kVK_ANSI_F: "F",
        kVK_ANSI_G: "G",
        kVK_ANSI_H: "H",
        kVK_ANSI_I: "I",
        kVK_ANSI_J: "J",
        kVK_ANSI_K: "K",
        kVK_ANSI_L: "L",
        kVK_ANSI_M: "M",
        kVK_ANSI_N: "N",
        kVK_ANSI_O: "O",
        kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q",
        kVK_ANSI_R: "R",
        kVK_ANSI_S: "S",
        kVK_ANSI_T: "T",
        kVK_ANSI_U: "U",
        kVK_ANSI_V: "V",
        kVK_ANSI_W: "W",
        kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0",
        kVK_ANSI_1: "1",
        kVK_ANSI_2: "2",
        kVK_ANSI_3: "3",
        kVK_ANSI_4: "4",
        kVK_ANSI_5: "5",
        kVK_ANSI_6: "6",
        kVK_ANSI_7: "7",
        kVK_ANSI_8: "8",
        kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=",
        kVK_ANSI_Minus: "-",
        kVK_ANSI_RightBracket: "]",
        kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_Quote: "'",
        kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Comma: ",",
        kVK_ANSI_Slash: "/",
        kVK_ANSI_Period: ".",
        kVK_ANSI_Grave: "`",
        kVK_Space: "Space",
        kVK_Return: "⏎",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20",
        kVK_ANSI_Keypad0: "Num0",
        kVK_ANSI_Keypad1: "Num1",
        kVK_ANSI_Keypad2: "Num2",
        kVK_ANSI_Keypad3: "Num3",
        kVK_ANSI_Keypad4: "Num4",
        kVK_ANSI_Keypad5: "Num5",
        kVK_ANSI_Keypad6: "Num6",
        kVK_ANSI_Keypad7: "Num7",
        kVK_ANSI_Keypad8: "Num8",
        kVK_ANSI_Keypad9: "Num9",
        kVK_ANSI_KeypadDecimal: "Num.",
        kVK_ANSI_KeypadMultiply: "Num*",
        kVK_ANSI_KeypadPlus: "Num+",
        kVK_ANSI_KeypadClear: "Clear",
        kVK_ANSI_KeypadDivide: "Num/",
        kVK_ANSI_KeypadMinus: "Num-",
        kVK_ANSI_KeypadEquals: "Num="
    ]
}
