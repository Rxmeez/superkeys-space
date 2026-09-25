import Foundation

/// Clears the hardware Caps Lock latch and LED through IOHIDSystem.
/// IOKit is resolved with dlopen/dlsym so no bridging header is needed.
enum CapsLock {
    private typealias IOObject = UInt32
    private typealias IOConnect = UInt32

    private typealias MatchingFn = @convention(c) (UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
    private typealias GetServiceFn = @convention(c) (UInt32, CFDictionary?) -> IOObject
    private typealias OpenFn = @convention(c) (IOObject, UInt32, UInt32, UnsafeMutablePointer<IOConnect>) -> Int32
    private typealias SetLockFn = @convention(c) (IOConnect, Int32, Bool) -> Int32
    private typealias CloseFn = @convention(c) (IOConnect) -> Int32
    private typealias ReleaseFn = @convention(c) (IOObject) -> Int32

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static let matching = symbol("IOServiceMatching", as: MatchingFn.self)
    private static let getService = symbol("IOServiceGetMatchingService", as: GetServiceFn.self)
    private static let open = symbol("IOServiceOpen", as: OpenFn.self)
    private static let setLock = symbol("IOHIDSetModifierLockState", as: SetLockFn.self)
    private static let close = symbol("IOServiceClose", as: CloseFn.self)
    private static let release = symbol("IOObjectRelease", as: ReleaseFn.self)

    private static let kIOHIDParamConnectType: UInt32 = 1
    private static let kIOHIDCapsLockState: Int32 = 1

    private static var cachedConnect: IOConnect?

    /// Runs inside the event tap callback, so the connection is opened once and
    /// kept: reopening per event is slow enough for macOS to disable the tap.
    static func unlock() {
        guard let setLock, let connect = connection() else { return }
        _ = setLock(connect, kIOHIDCapsLockState, false)
    }

    private static func connection() -> IOConnect? {
        if let cachedConnect { return cachedConnect }
        guard let matching, let getService, let open else { return nil }
        guard let dict = matching("IOHIDSystem") else { return nil }
        // IOServiceGetMatchingService consumes the +1 matching dictionary, so
        // Swift must not release it too.
        let service = getService(0, dict.takeUnretainedValue())
        guard service != 0 else { return nil }
        defer { _ = release?(service) }

        var connect: IOConnect = 0
        guard open(service, mach_task_self_, kIOHIDParamConnectType, &connect) == 0 else { return nil }
        cachedConnect = connect
        return connect
    }
}

/// Remaps Caps Lock to F18 (the Hyper Key) and right Command to F19 (the Meh
/// Key) at the HID layer, so the tap sees plain key down/up events that no app
/// treats as a modifier. Caps Lock alone only reports flagsChanged, which cannot
/// distinguish press from release once the latch is cleared.
///
/// The mappings are merged into whatever `UserKeyMapping` the user already has,
/// and their own entries are put back when Superkeys stops. This talks to the
/// HID event system in-process, the same client `hidutil` uses, via dlsym.
enum HIDRemap {
    private typealias Mapping = [String: UInt64]
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetFn = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> UInt8
    private typealias ServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServicePropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static let client: CFTypeRef? = symbol("IOHIDEventSystemClientCreateSimpleClient", as: CreateFn.self)?(nil)?
        .takeRetainedValue()
    private static let setProperty = symbol("IOHIDEventSystemClientSetProperty", as: SetFn.self)
    private static let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: ServicesFn.self)
    private static let serviceProperty = symbol("IOHIDServiceClientCopyProperty", as: ServicePropertyFn.self)

    private static let key = "UserKeyMapping" as CFString
    private static let source = "HIDKeyboardModifierMappingSrc"
    private static let destination = "HIDKeyboardModifierMappingDst"
    private static let capsLockUsage: UInt64 = 0x7_0000_0039
    private static let rightCommandUsage: UInt64 = 0x7_0000_00E7
    private static let f18Usage: UInt64 = 0x7_0000_006D
    private static let f19Usage: UInt64 = 0x7_0000_006E
    private static let ours: [Mapping] = [
        [source: capsLockUsage, destination: f18Usage],
        [source: rightCommandUsage, destination: f19Usage]
    ]
    private static let ourSources = Set(ours.compactMap { $0[source] })

    /// The user's own mappings, held while ours is installed.
    private static var saved: [Mapping]?

    static func enable() {
        guard saved == nil else { return }
        let theirs = current().filter { !ours.contains($0) }
        // Superkeys owns Caps Lock and right Command while it runs; any other
        // entry stays.
        let kept = theirs.filter { !ourSources.contains($0[source] ?? 0) }
        if write(kept + ours) {
            saved = theirs
            Watchdog.start(restoring: theirs)
        }
    }

    static func disable() {
        Watchdog.stop()
        if let saved {
            if write(saved) { self.saved = nil }
        } else {
            // A crashed earlier run can leave our entries behind.
            let mappings = current()
            if mappings.contains(where: ours.contains) {
                _ = write(mappings.filter { !ours.contains($0) })
            }
        }
    }

    /// Mappings are applied to every keyboard service, so the first one that
    /// carries any is representative.
    private static func current() -> [Mapping] {
        guard let client, let copyServices, let serviceProperty,
              let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        for service in services {
            guard let raw = serviceProperty(service, key)?.takeRetainedValue() as? [[String: Any]],
                  !raw.isEmpty else { continue }
            return raw.compactMap { entry in
                guard let src = (entry[source] as? NSNumber)?.uint64Value,
                      let dst = (entry[destination] as? NSNumber)?.uint64Value else { return nil }
                return [source: src, destination: dst]
            }
        }
        return []
    }

    /// If Superkeys is force-quit or crashes, nothing would take its
    /// mappings back out, and Caps Lock would stay dead until the next launch.
    /// A tiny shell process outlives it, notices within two seconds that it's
    /// gone, and restores the user's own mappings with hidutil.
    private enum Watchdog {
        private static let pidKey = "remapWatchdogPID"
        private static var process: Process?

        static func start(restoring mappings: [Mapping]) {
            stop()
            let json = mappings.map { m in
                "{\"\(source)\":\(m[source] ?? 0),\"\(destination)\":\(m[destination] ?? 0)}"
            }.joined(separator: ",")
            let script = """
            while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 2; done
            /usr/bin/hidutil property --set '{"UserKeyMapping":[\(json)]}' >/dev/null
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            guard (try? task.run()) != nil else { return }
            process = task
            UserDefaults.standard.set(Int(task.processIdentifier), forKey: pidKey)
        }

        /// Stops this run's watcher, and one left over from a run that
        /// crashed, before it could undo the mapping about to be installed.
        static func stop() {
            process?.terminate()
            process = nil
            let stale = UserDefaults.standard.integer(forKey: pidKey)
            if stale > 0, isWatchdog(pid_t(stale)) { kill(pid_t(stale), SIGTERM) }
            UserDefaults.standard.removeObject(forKey: pidKey)
        }

        private static func isWatchdog(_ pid: pid_t) -> Bool {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            return String(cString: buffer) == "/bin/sh"
        }
    }

    private static func write(_ mappings: [Mapping]) -> Bool {
        guard let client, let setProperty else { return false }
        let value = mappings.map { $0.mapValues { NSNumber(value: $0) } } as CFArray
        return setProperty(client, key, value) != 0
    }
}
