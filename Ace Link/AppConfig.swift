import Cocoa
import Darwin
import Foundation
import os

public enum AppConfig: String {
    case bundleIdentifier
    case googleTVADBAddressKey = "google-tv-adb-address"
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

    static var googleTVADBAddress: String? {
        get {
            guard let address = UserDefaults.standard.string(
                forKey: googleTVADBAddressKey.rawValue
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !address.isEmpty else {
                return nil
            }
            return address
        }
        set(value) {
            let address = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if address.isEmpty {
                UserDefaults.standard.removeObject(forKey: googleTVADBAddressKey.rawValue)
            } else {
                UserDefaults.standard.set(normalizedADBAddress(address), forKey: googleTVADBAddressKey.rawValue)
            }
        }
    }

    private static func normalizedADBAddress(_ address: String) -> String {
        if address.contains(":") {
            return address
        }
        return "\(address):5555"
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

    static var localNetworkHost: String {
        NetworkInterface.primaryIPv4Address ?? "127.0.0.1"
    }

    static var tvPlaylistURL: URL {
        URL(string: "http://\(localNetworkHost):\(AppConstants.Docker.proxyPort)/acelink.m3u8")!
    }

    static var tvCurrentURL: URL {
        URL(string: "http://\(localNetworkHost):\(AppConstants.Docker.proxyPort)/current")!
    }

    static var tvStreamBaseURL: URL {
        URL(string: "http://\(localNetworkHost):\(AppConstants.Docker.enginePort)")!
    }
}

private enum NetworkInterface {
    static var primaryIPv4Address: String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var candidates: [(name: String, address: String, score: Int)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            guard let address = interface.ifa_addr else {
                continue
            }
            guard address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isRunning, !isLoopback else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard let ipAddress = ipv4Address(from: address) else {
                continue
            }
            guard !ipAddress.hasPrefix("127."), !ipAddress.hasPrefix("169.254.") else {
                continue
            }

            candidates.append((name, ipAddress, score(name: name, address: ipAddress)))
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.name < rhs.name
            }
            return lhs.score > rhs.score
        }.first?.address
    }

    private static func ipv4Address(from address: UnsafePointer<sockaddr>) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else {
            return nil
        }
        return String(cString: hostname)
    }

    private static func score(name: String, address: String) -> Int {
        var score = 0

        if name.hasPrefix("en") {
            score += 100
        }
        if isPrivateIPv4(address) {
            score += 30
        }
        if name.hasPrefix("bridge") ||
            name.hasPrefix("utun") ||
            name.hasPrefix("awdl") ||
            name.hasPrefix("llw") {
            score -= 100
        }

        return score
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }
        if parts[0] == 172, (16...31).contains(parts[1]) {
            return true
        }
        return parts[0] == 192 && parts[1] == 168
    }
}
