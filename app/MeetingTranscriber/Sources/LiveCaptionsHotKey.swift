import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultLiveCaptions = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: "T"
    )

    var displayString: String {
        var value = ""

        if modifiers & UInt32(controlKey) != 0 {
            value += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            value += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            value += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            value += "⌘"
        }

        return value + keyLabel
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        let allowedFlags: NSEvent.ModifierFlags = [
            .command,
            .option,
            .control,
            .shift,
        ]
        let flags = event.modifierFlags.intersection(allowedFlags)
        let modifiers = carbonModifiers(from: flags)

        let primaryModifiers = UInt32(cmdKey | optionKey | controlKey)
        guard modifiers & primaryModifiers != 0 else {
            return nil
        }

        guard let keyLabel = keyLabel(for: event) else {
            return nil
        }

        return GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
    }

    private static func carbonModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> UInt32 {
        var value: UInt32 = 0

        if flags.contains(.command) {
            value |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            value |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            value |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            value |= UInt32(shiftKey)
        }

        return value
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "↩"
        case kVK_Tab:
            return "⇥"
        case kVK_Home:
            return "Home"
        case kVK_End:
            return "End"
        case kVK_PageUp:
            return "Page Up"
        case kVK_PageDown:
            return "Page Down"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_F1:
            return "F1"
        case kVK_F2:
            return "F2"
        case kVK_F3:
            return "F3"
        case kVK_F4:
            return "F4"
        case kVK_F5:
            return "F5"
        case kVK_F6:
            return "F6"
        case kVK_F7:
            return "F7"
        case kVK_F8:
            return "F8"
        case kVK_F9:
            return "F9"
        case kVK_F10:
            return "F10"
        case kVK_F11:
            return "F11"
        case kVK_F12:
            return "F12"
        default:
            guard
                let characters = event.charactersIgnoringModifiers,
                !characters.isEmpty
            else {
                return nil
            }

            return String(characters.prefix(1)).uppercased()
        }
    }
}

enum GlobalShortcutStorage {
    private struct StoredShortcut: Codable {
        let shortcut: GlobalShortcut?
    }

    private static let liveCaptionsKey = "liveCaptionsShortcut"

    static func loadLiveCaptionsShortcut(
        from defaults: UserDefaults
    ) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: liveCaptionsKey) else {
            return .defaultLiveCaptions
        }

        guard
            let stored = try? JSONDecoder().decode(
                StoredShortcut.self,
                from: data
            )
        else {
            return .defaultLiveCaptions
        }

        return stored.shortcut
    }

    static func saveLiveCaptionsShortcut(
        _ shortcut: GlobalShortcut?,
        to defaults: UserDefaults
    ) {
        let stored = StoredShortcut(shortcut: shortcut)

        guard let data = try? JSONEncoder().encode(stored) else {
            return
        }

        defaults.set(data, forKey: liveCaptionsKey)
    }
}

extension Notification.Name {
    static let toggleLiveCaptionsOverlay =
        Notification.Name("toggleLiveCaptionsOverlay")
}

private func liveCaptionsHotKeyEventHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let address = UInt(bitPattern: userData)

    Task { @MainActor in
        guard
            let pointer = UnsafeMutableRawPointer(bitPattern: address)
        else {
            return
        }

        let controller =
            Unmanaged<LiveCaptionsHotKeyController>
                .fromOpaque(pointer)
                .takeUnretainedValue()

        controller.handlePress()
    }

    return noErr
}

@Observable
@MainActor
final class LiveCaptionsHotKeyController {
    private static let hotKeySignature: OSType = 0x4D544343 // MTCC
    private static let hotKeyID: UInt32 = 1

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    private(set) var registrationError: String?

    func update(shortcut: GlobalShortcut?) {
        unregisterCurrentShortcut()
        registrationError = nil

        guard let shortcut else {
            return
        }

        guard ensureEventHandler() else {
            registrationError = "Could not initialize the global shortcut."
            return
        }

        var newHotKeyRef: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyID
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr else {
            registrationError =
                "Could not register \(shortcut.displayString). "
                + "It may already be used by macOS or another app "
                + "(OSStatus \(status))."
            return
        }

        hotKeyRef = newHotKeyRef
    }

    fileprivate func handlePress() {
        NotificationCenter.default.post(
            name: .toggleLiveCaptionsOverlay,
            object: nil
        )
    }

    private func ensureEventHandler() -> Bool {
        if eventHandlerRef != nil {
            return true
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var newHandlerRef: EventHandlerRef?

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            liveCaptionsHotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &newHandlerRef
        )

        guard status == noErr else {
            return false
        }

        eventHandlerRef = newHandlerRef
        return true
    }

    private func unregisterCurrentShortcut() {
        guard let hotKeyRef else {
            return
        }

        _ = UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}

struct GlobalShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut?

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(
        context: Context
    ) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onShortcut = { shortcut in
            context.coordinator.shortcut.wrappedValue = shortcut
        }
        button.update(shortcut: shortcut)
        return button
    }

    func updateNSView(
        _ nsView: ShortcutRecorderButton,
        context: Context
    ) {
        context.coordinator.shortcut = $shortcut
        nsView.onShortcut = { shortcut in
            context.coordinator.shortcut.wrappedValue = shortcut
        }
        nsView.update(shortcut: shortcut)
    }

    @MainActor
    final class Coordinator {
        var shortcut: Binding<GlobalShortcut?>

        init(shortcut: Binding<GlobalShortcut?>) {
            self.shortcut = shortcut
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var onShortcut: ((GlobalShortcut?) -> Void)?

    private var currentShortcut: GlobalShortcut?
    private var recording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(shortcut: GlobalShortcut?) {
        currentShortcut = shortcut

        if !recording {
            updateTitle()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        if Int(event.keyCode) == kVK_Escape {
            finishRecording()
            return
        }

        if Int(event.keyCode) == kVK_Delete
            || Int(event.keyCode) == kVK_ForwardDelete {
            onShortcut?(nil)
            currentShortcut = nil
            finishRecording()
            return
        }

        guard let shortcut = GlobalShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        onShortcut?(shortcut)
        currentShortcut = shortcut
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()

        if result, recording {
            finishRecording()
        }

        return result
    }

    private func configure() {
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        controlSize = .regular
        toolTip =
            "Click, then press a shortcut. Escape cancels. "
            + "Delete clears the shortcut."
        updateTitle()
    }

    @objc private func beginRecording() {
        recording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    private func finishRecording() {
        recording = false
        updateTitle()
    }

    private func updateTitle() {
        title = currentShortcut?.displayString ?? "Record Shortcut"
    }
}
