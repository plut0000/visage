import AppKit
import Darwin

/// Private SkyLight space so the overlay can appear on the lock screen.
/// Adapted from SkyLightWindow (MIT). `shared` is nil if symbols are gone.
final class LockScreenSpace {
    static let shared: LockScreenSpace? = LockScreenSpace()

    private let connection: Int32
    private let space: Int32

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let addWindows: AddWindows
    private let removeWindows: RemoveWindows

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else { return nil }

        guard
            let mainSym = dlsym(handle, "SLSMainConnectionID"),
            let createSym = dlsym(handle, "SLSSpaceCreate"),
            let levelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSym = dlsym(handle, "SLSShowSpaces"),
            let addSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
            let removeSym = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else { return nil }

        let mainConnectionID = unsafeBitCast(mainSym, to: MainConnectionID.self)
        let spaceCreate = unsafeBitCast(createSym, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(levelSym, to: SetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSym, to: ShowSpaces.self)
        addWindows = unsafeBitCast(addSym, to: AddWindows.self)
        removeWindows = unsafeBitCast(removeSym, to: RemoveWindows.self)

        connection = mainConnectionID()
        space = spaceCreate(connection, 1, 0)
        _ = setLevel(connection, space, 400)
        _ = showSpaces(connection, [space] as CFArray)
    }

    func attach(_ window: NSWindow) {
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }

    func detach(_ window: NSWindow) {
        _ = removeWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
