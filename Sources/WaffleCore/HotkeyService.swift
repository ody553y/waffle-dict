import ApplicationServices
import Carbon.HIToolbox
import Foundation

public struct GlobalHotkey: Sendable, Equatable {
    public struct StoragePayload: Codable, Equatable, Sendable {
        public let keyCode: UInt16
        public let modifiers: UInt64
        public let displayValue: String

        public init(keyCode: UInt16, modifiers: UInt64, displayValue: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.displayValue = displayValue
        }
    }

    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags
    public let displayValue: String

    public static let supportedModifiers: CGEventFlags = [
        .maskCommand,
        .maskShift,
        .maskControl,
        .maskAlternate,
        .maskSecondaryFn,
    ]

    public init(keyCode: CGKeyCode, modifiers: CGEventFlags, displayValue: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers)
        self.displayValue = displayValue
    }

    public init(storagePayload: StoragePayload) {
        self.init(
            keyCode: CGKeyCode(storagePayload.keyCode),
            modifiers: CGEventFlags(rawValue: storagePayload.modifiers),
            displayValue: storagePayload.displayValue
        )
    }

    public var storagePayload: StoragePayload {
        StoragePayload(
            keyCode: UInt16(keyCode),
            modifiers: modifiers.rawValue,
            displayValue: displayValue
        )
    }

    public func encodedJSONString() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(storagePayload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func decoded(from jsonString: String) -> GlobalHotkey? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(StoragePayload.self, from: data) else {
            return nil
        }
        return GlobalHotkey(storagePayload: payload)
    }

    public static let optionSpace = GlobalHotkey(
        keyCode: CGKeyCode(kVK_Space),
        modifiers: [.maskAlternate],
        displayValue: "⌥Space"
    )
}

public protocol HotkeyServiceProtocol: AnyObject {
    var hotkeyDisplayValue: String { get }
    var isRunning: Bool { get }

    @discardableResult
    func start(onPress: @escaping @Sendable () -> Void) -> Bool

    func updateHotkey(_ hotkey: GlobalHotkey)
    func stop()
}

public final class HotkeyService: HotkeyServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var hotkey: GlobalHotkey
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var workerThread: Thread?
    private var onPress: (@Sendable () -> Void)?
    private var startupSemaphore: DispatchSemaphore?
    private var startupSucceeded = false

    public init(hotkey: GlobalHotkey = .optionSpace) {
        self.hotkey = hotkey
    }

    public var hotkeyDisplayValue: String {
        lock.lock()
        defer { lock.unlock() }
        return hotkey.displayValue
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    @discardableResult
    public func start(onPress: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        if eventTap != nil {
            self.onPress = onPress
            lock.unlock()
            return true
        }

        self.onPress = onPress
        let semaphore = DispatchSemaphore(value: 0)
        startupSemaphore = semaphore
        startupSucceeded = false

        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "Waffle.HotkeyEventTap"
        workerThread = thread
        lock.unlock()

        thread.start()
        let didSignal = semaphore.wait(timeout: .now() + 2) == .success

        lock.lock()
        let didStart = didSignal && startupSucceeded
        startupSemaphore = nil
        lock.unlock()

        if didStart == false {
            stop()
        }

        return didStart
    }

    public func stop() {
        lock.lock()
        let localRunLoop = runLoop
        if let localTap = eventTap {
            CGEvent.tapEnable(tap: localTap, enable: false)
        }
        onPress = nil
        lock.unlock()

        if let localRunLoop {
            CFRunLoopPerformBlock(localRunLoop, CFRunLoopMode.defaultMode.rawValue) {}
            CFRunLoopWakeUp(localRunLoop)
            CFRunLoopStop(localRunLoop)
        }
    }

    public func updateHotkey(_ hotkey: GlobalHotkey) {
        lock.lock()
        if self.hotkey == hotkey {
            lock.unlock()
            return
        }

        self.hotkey = hotkey
        let shouldRestart = eventTap != nil
        let callback = onPress
        lock.unlock()

        guard shouldRestart, let callback else { return }
        stop()
        _ = start(onPress: callback)
    }

    private func runEventTapLoop() {
        autoreleasepool {
            let mask = (1 << CGEventType.keyDown.rawValue)
            guard
                let localEventTap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: CGEventMask(mask),
                    callback: { proxy, eventType, event, userInfo in
                        guard let userInfo else {
                            return Unmanaged.passUnretained(event)
                        }
                        let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                        return service.handleEvent(proxy: proxy, type: eventType, event: event)
                    },
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                completeStartup(success: false)
                return
            }

            let localRunLoop = CFRunLoopGetCurrent()
            let localSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, localEventTap, 0)
            CFRunLoopAddSource(localRunLoop, localSource, .defaultMode)
            CGEvent.tapEnable(tap: localEventTap, enable: true)

            lock.lock()
            eventTap = localEventTap
            runLoop = localRunLoop
            runLoopSource = localSource
            lock.unlock()

            completeStartup(success: true)
            CFRunLoopRun()

            lock.lock()
            eventTap = nil
            runLoop = nil
            runLoopSource = nil
            workerThread = nil
            lock.unlock()
        }
    }

    private func completeStartup(success: Bool) {
        lock.lock()
        startupSucceeded = success
        let semaphore = startupSemaphore
        lock.unlock()
        semaphore?.signal()
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let localTap = eventTap
            lock.unlock()
            if let localTap {
                CGEvent.tapEnable(tap: localTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard isRepeat == false else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let normalizedFlags = event.flags.intersection(GlobalHotkey.supportedModifiers)

        lock.lock()
        let activeHotkey = hotkey
        let callback = onPress
        lock.unlock()

        guard keyCode == activeHotkey.keyCode, normalizedFlags == activeHotkey.modifiers else {
            return Unmanaged.passUnretained(event)
        }

        callback?()

        // Consume the hotkey event so Option+Space does not leak into foreground apps.
        return nil
    }
}
