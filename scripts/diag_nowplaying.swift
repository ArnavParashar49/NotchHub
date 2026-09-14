import Foundation
import AppKit

// Diagnostic harness: tests the MediaRemote private API directly.
// Prints what MRMediaRemoteGetNowPlayingInfo returns, and observes the
// distributed notification to confirm its exact name.

let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
    print("FAIL: could not dlopen MediaRemote")
    exit(1)
}

let getFn = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
let regFn = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
print("getNowPlayingInfo symbol: \(getFn == nil ? "MISSING" : "present")")
print("registerForNowPlayingNotifications symbol: \(regFn == nil ? "MISSING" : "present")")

guard let getNowPlayingInfo = getFn.map({ unsafeBitCast($0, to: GetNowPlayingInfoFn.self) }) else {
    print("FAIL: MRMediaRemoteGetNowPlayingInfo unavailable")
    exit(1)
}

// Observe the change notification to confirm its exact name.
let center = DistributedNotificationCenter.default()
let obsName = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
print("Observing distributed notification: \(obsName)")
let token = center.addObserver(
    forName: NSNotification.Name(obsName),
    object: nil,
    queue: .main
) { note in
    print(">>> NOTIFICATION FIRED: \(note.name.rawValue)")
    print("    userInfo keys: \(note.userInfo?.keys.map { String(describing: $0) } ?? [])")
}

// Register, then fetch after a delay.
if let reg = regFn.map({ unsafeBitCast($0, to: RegisterFn.self) }) {
    print("Registering for now-playing notifications...")
    reg(DispatchQueue.main)
}

func fetch(label: String) {
    getNowPlayingInfo(DispatchQueue.global(qos: .utility)) { dict in
        let raw = (dict as? [String: Any]) ?? [:]
        let title = raw["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = raw["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let hasArt = (raw["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)?.isEmpty == false
        print("[\(label)] title=\(title ?? "nil") artist=\(artist ?? "nil") artwork=\(hasArt)")
        print("[\(label)] raw keys: \(raw.keys.sorted())")
    }
}

// Fetch immediately, then after 1s, 2s, 3s.
fetch(label: "t0")
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { fetch(label: "t1") }
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { fetch(label: "t2") }
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { fetch(label: "t3") }

// Keep running for 8 seconds to catch notifications.
DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
    print("DONE")
    exit(0)
}

RunLoop.main.run()
