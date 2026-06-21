import Cocoa
import Foundation
import os

private struct GetStreamInfoResponse: Decodable {
    let response: StreamInfoResponse
    let error: String?
}

private struct StreamInfoResponse: Decodable {
    let statURLString: String
    enum CodingKeys: String, CodingKey {
        case statURLString = "stat_url"
    }
}

struct StreamFile {
    var hash: String
    var type: AppConstants.StreamType
    var title: String = "Unknown stream"
    var playlistURL = URL(string: "http://127.0.0.1:\(AppConstants.Docker.proxyPort)/acelink.m3u8")!

    var param: String {
        switch type {
        case AppConstants.StreamType.magnet:
            return "infohash"
        default:
            return "id"
        }
    }

    var streamURL: URL {
        AppConstants.Docker.baseURL
            .appendingPathComponent("/ace/getstream")
            .appendingQuery(param, hash)
    }

    var manifestURL: URL {
        AppConstants.Docker.baseURL
            .appendingPathComponent("/ace/manifest.m3u8")
            .appendingQuery(param, hash)
    }

    var tvStreamURL: URL {
        AppConfig.tvStreamBaseURL
            .appendingPathComponent("/ace/getstream")
            .appendingQuery(param, hash)
    }

    var tvManifestURL: URL {
        AppConfig.tvStreamBaseURL
            .appendingPathComponent("/ace/manifest.m3u8")
            .appendingQuery(param, hash)
    }

    var m3uData: String {
        m3uData(for: streamURL)
    }

    var tvM3UData: String {
        m3uData(for: tvManifestURL)
    }

    func addToHistory() {
        let file = AppConfig.streamsDir.appendingPathComponent("\(title).m3u8")
        os_log("Writing data file to %{public}s to maintain history.", file.path)
        do {
            try m3uData.write(to: file, atomically: false, encoding: .utf8)
        } catch {
            os_log("Writing data file failed.")
        }
    }

    func waitForPeers(callback: @escaping (AppError?) -> Void) {
        getStreamInfo { streamInfo in
            let statURL = URL(string: streamInfo.response.statURLString)!
            StreamPeers(statURL: statURL).task { result in
                callback(result)
            }
        }
    }

    func getURLForBundleType(_ bundle: Bundle) -> URL {
        if bundle.isBrowser {
            return AppConstants.Docker.baseURL.appendingPathComponent("/webui/player/\(hash)")
        } else {
            return playlistURL
        }
    }

    private func m3uData(for url: URL) -> String {
        "#EXTM3U\r\n#EXTINF:-1, Ace Link - \(title)\r\n\(url.absoluteString)\r\n"
    }

    private func getStreamInfo(callback: @escaping (GetStreamInfoResponse) -> Void) {
        os_log("Getting stream session urls…")
        let urlSession = URLSession(configuration: .ephemeral)
        let url = streamURL.appendingQuery("format", "json")
        urlSession.jsonDataTask(with: url, decodable: GetStreamInfoResponse.self) { streamInfo in
            if let streamInfo = streamInfo {
                callback(streamInfo)
                return
            }
        }.resume()
    }
}
