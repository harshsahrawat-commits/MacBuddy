import Carbon

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    var action: (() -> Void)?
    static let keyCodes: [String: UInt32] = ["A":0,"B":11,"C":8,"D":2,"E":14,"F":3,"G":5,"H":4,"I":34,"J":38,"K":40,"L":37,"M":46,"N":45,"O":31,"P":35,"Q":12,"R":15,"S":1,"T":17,"U":32,"V":9,"W":13,"X":7,"Y":16,"Z":6]
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4D424459, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(key: String, control: Bool, option: Bool, command: Bool, shift: Bool) -> String? {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard handlerStatus == noErr, handler != nil else { return "The system shortcut handler is unavailable (\(handlerStatus)). Use the menu bar to access Mac Buddy." }
        guard control || option || command else { return "Choose Control, Option, or Command to avoid capturing ordinary typing. Menu-bar access remains available." }
        guard let code = Self.keyCodes[key] else { return "Choose a letter for the shortcut." }
        var modifiers: UInt32 = 0
        if control { modifiers |= UInt32(controlKey) }; if option { modifiers |= UInt32(optionKey) }
        if command { modifiers |= UInt32(cmdKey) }; if shift { modifiers |= UInt32(shiftKey) }
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x4D424459, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr ? nil : "Shortcut could not be registered (\(status)); another app may use it. Choose another combination. Menu-bar access remains available."
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}
