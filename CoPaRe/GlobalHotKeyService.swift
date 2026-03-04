import Carbon.HIToolbox
import Combine
import Foundation
import OSLog

@MainActor
final class GlobalHotKeyService: ObservableObject {
    static let shortcutDisplayName = "⌥⌘V"

    private static let hotKeySignature: OSType = 0x43505248 // CPRH
    private static let hotKeyIdentifier: UInt32 = 1

    private let logger = Logger(subsystem: "io.copare.app", category: "hotkey")
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    var onHotKeyPressed: (() -> Void)?
    private(set) var isRegistered = false

    func setEnabled(_ enabled: Bool) {
        if enabled {
            registerIfNeeded()
        } else {
            unregister()
        }
    }

    private func registerIfNeeded() {
        guard !isRegistered else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return noErr
            }

            let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            return service.handleHotKeyEvent(event)
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            logger.error("Unable to install global hotkey event handler: \(installStatus, privacy: .public)")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        let modifiers = UInt32(optionKey) | UInt32(cmdKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            logger.error("Unable to register global hotkey: \(registerStatus, privacy: .public)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return
        }

        isRegistered = true
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        isRegistered = false
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
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

        guard hotKeyID.signature == Self.hotKeySignature,
              hotKeyID.id == Self.hotKeyIdentifier
        else {
            return noErr
        }

        onHotKeyPressed?()
        return noErr
    }
}
