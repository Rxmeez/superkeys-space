import ApplicationServices
import Foundation

/// Private CoreGraphics/SkyLight symbols resolved at runtime. Every symbol is
/// optional: callers must handle nil and fall back.
enum SkyLightBridge {
    typealias MainConnectionFn = @convention(c) () -> Int32
    typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias MoveWindowsFn = @convention(c) (Int32, CFArray, UInt64) -> Void
    typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64
    typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let hiServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)

    private static func resolve<T>(_ names: [String], in handles: [UnsafeMutableRawPointer?], as type: T.Type) -> T? {
        for handle in handles {
            guard let handle else { continue }
            for name in names {
                if let sym = dlsym(handle, name) { return unsafeBitCast(sym, to: type) }
            }
        }
        return nil
    }

    static let mainConnectionID = resolve(["CGSMainConnectionID", "SLSMainConnectionID"], in: [skyLight], as: MainConnectionFn.self)
    static let copyManagedDisplaySpaces = resolve(["CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces"], in: [skyLight], as: CopyDisplaySpacesFn.self)
    static let moveWindowsToManagedSpace = resolve(["CGSMoveWindowsToManagedSpace", "SLSMoveWindowsToManagedSpace"], in: [skyLight], as: MoveWindowsFn.self)
    static let getActiveSpace = resolve(["CGSGetActiveSpace", "SLSGetActiveSpace"], in: [skyLight], as: ActiveSpaceFn.self)
    static let copySpacesForWindows = resolve(["CGSCopySpacesForWindows", "SLSCopySpacesForWindows"], in: [skyLight], as: SpacesForWindowsFn.self)
    static let axGetWindow = resolve(["_AXUIElementGetWindow"], in: [hiServices, skyLight, dlopen(nil, RTLD_LAZY)], as: AXGetWindowFn.self)

    static var spacesAvailable: Bool {
        mainConnectionID != nil && copyManagedDisplaySpaces != nil
    }
}
