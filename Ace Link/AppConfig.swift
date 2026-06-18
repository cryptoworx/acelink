import Cocoa
import Foundation
import os

public enum AppConfig: String {
    case bundleIdentifier
    case liveBufferTimeKey = "live-buffer-time"
    case vodBufferKey = "vod-buffer"

    static let defaultLiveBufferTime = 30
    static let defaultVodBuffer = 15

    static var streamsDir: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Ace Link/streams")
    }

    static var playerBundleIdentifier: String? {
        get {
            UserDefaults.standard.string(forKey: bundleIdentifier.rawValue)
        }
        set(value) {
            UserDefaults.standard.set(value, forKey: bundleIdentifier.rawValue)
        }
    }

    static var vodBuffer: Int {
        get {
            guard UserDefaults.standard.object(forKey: vodBufferKey.rawValue) != nil else {
                return defaultVodBuffer
            }
            return max(0, UserDefaults.standard.integer(forKey: vodBufferKey.rawValue))
        }
        set(value) {
            UserDefaults.standard.set(max(0, value), forKey: vodBufferKey.rawValue)
        }
    }

    static var liveBufferTime: Int {
        get {
            guard UserDefaults.standard.object(forKey: liveBufferTimeKey.rawValue) != nil else {
                return defaultLiveBufferTime
            }
            return max(0, UserDefaults.standard.integer(forKey: liveBufferTimeKey.rawValue))
        }
        set(value) {
            UserDefaults.standard.set(max(0, value), forKey: liveBufferTimeKey.rawValue)
        }
    }

    static var playerBundle: Bundle? {
        guard let playerBundleIdentifier = playerBundleIdentifier else {
            os_log("No player selected")
            return nil
        }
        guard let bundle = NSWorkspace.shared.getBundle(bundleID: playerBundleIdentifier) else {
            os_log("No such bundle %{public}@", playerBundleIdentifier)
            return nil
        }
        return bundle
    }
}
