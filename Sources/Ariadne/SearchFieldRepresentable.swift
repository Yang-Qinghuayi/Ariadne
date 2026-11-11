import AppKit
import SwiftUI

struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFieldReady: (NSTextField) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: (_ commandPressed: Bool, _ optionPressed: Bool) -> Void
    let onEscape: () -> Void
    let onToggleActions: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator

        DispatchQueue.main.async {
            onFieldReady(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.currentEditor()?.hasMarkedText == true {
            return
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchFieldRepresentable

        init(_ parent: SearchFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                // Still allow live filtering or wait until marked text updates?
                // Updating stringValue during IME composition is safe as long as updateNSView checks hasMarkedText.
                parent.text = field.stringValue
            } else {
                parent.text = field.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if textView.hasMarkedText() {
                return false
            }

            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                parent.onSubmit(
                    flags.contains(.command),
                    flags.contains(.option)
                )
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onToggleActions()
                return true
            default:
                return false
            }
        }
    }
}
