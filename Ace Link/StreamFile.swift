import Cocoa
import Foundation
import os

private struct GetStreamInfoResponse: Decodable {
    let response: StreamInfoResponse
    let error: String?
}

private struct StreamInfoResponse: Decodable {
    let statURLString: String
    let playbackSessionID: String?
    let streamURLString: String?
    let manifestURLString: String?

    enum CodingKeys: String, CodingKey {
        case statURLString = "stat_url"
        case playbackSessionID = "playback_session_id"
        case streamURLString = "stream_url"
        case playbackURLString = "playback_url"
        case urlString = "url"
        case manifestURLString = "manifest_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStreamURLString = try container.decodeIfPresent(
            String.self,
            forKey: .streamURLString
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .playbackURLString
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .urlString
        )
        let decodedManifestURLString = try container.decodeIfPresent(
            String.self,
            forKey: .manifestURLString
        )

        statURLString = try container.decode(String.self, forKey: .statURLString)
        playbackSessionID = try container.decodeIfPresent(
            String.self,
            forKey: .playbackSessionID
        ) ?? Self.queryValue(
            "playback_session_id",
            in: statURLString
        ) ?? Self.queryValue(
            "playback_session_id",
            in: decodedStreamURLString
        ) ?? Self.queryValue(
            "playback_session_id",
            in: decodedManifestURLString
        )
        streamURLString = decodedStreamURLString
        manifestURLString = decodedManifestURLString
    }

    private static func queryValue(_ name: String, in urlString: String?) -> String? {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        return queryItems.first { $0.name == name }?.value
    }
}

struct StreamFile {
    var hash: String
    var type: AppConstants.StreamType
    var title: String = "Unknown stream"
    var playlistURL = URL(string: "http://127.0.0.1:\(AppConstants.Docker.proxyPort)/acelink.m3u8")!
    var playbackSessionID: String?
    var playbackStreamURL: URL?
    var playbackManifestURL: URL?

    var param: String {
        switch type {
        case AppConstants.StreamType.magnet:
            return "infohash"
        default:
            return "id"
        }
    }

    var streamURL: URL {
        playbackStreamURL ?? engineURL(
            baseURL: AppConstants.Docker.baseURL,
            path: "/ace/getstream"
        )
    }

    var manifestURL: URL {
        playbackManifestURL ?? engineURL(
            baseURL: AppConstants.Docker.baseURL,
            path: "/ace/manifest.m3u8"
        )
    }

    var tvStreamURL: URL {
        if let playbackStreamURL = playbackStreamURL {
            return url(playbackStreamURL, replacingBaseWith: AppConfig.tvStreamBaseURL)
        }
        return engineURL(
            baseURL: AppConfig.tvStreamBaseURL,
            path: "/ace/getstream"
        )
    }

    var tvManifestURL: URL {
        if let playbackManifestURL = playbackManifestURL {
            return url(playbackManifestURL, replacingBaseWith: AppConfig.tvStreamBaseURL)
        }
        return engineURL(
            baseURL: AppConfig.tvStreamBaseURL,
            path: "/ace/manifest.m3u8"
        )
    }

    var m3uData: String {
        m3uData(
            for: engineURL(
                baseURL: AppConstants.Docker.baseURL,
                path: "/ace/getstream",
                includePlaybackSession: false
            )
        )
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

    func waitForPeers(callback: @escaping (StreamFile, AppError?) -> Void) {
        getStreamInfo { streamInfo in
            let stream = withPlaybackSession(streamInfo.response)
            let statURL = URL(string: streamInfo.response.statURLString)!
            StreamPeers(statURL: statURL).task { result in
                callback(stream, result)
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

    private func engineURL(
        baseURL: URL,
        path: String,
        includePlaybackSession: Bool = true
    ) -> URL {
        var url = baseURL
            .appendingPathComponent(path)
            .appendingQuery(param, hash)
        if includePlaybackSession, let playbackSessionID = playbackSessionID {
            url = url.appendingQuery("playback_session_id", playbackSessionID)
        }
        return url
    }

    private func withPlaybackSession(_ response: StreamInfoResponse) -> StreamFile {
        var stream = self
        stream.playbackSessionID = response.playbackSessionID
        stream.playbackStreamURL = response.streamURLString.flatMap(URL.init(string:))
        stream.playbackManifestURL = response.manifestURLString.flatMap(URL.init(string:))
        return stream
    }

    private func url(_ url: URL, replacingBaseWith baseURL: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = baseComponents.scheme
        components.host = baseComponents.host
        components.port = baseComponents.port
        return components.url ?? url
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
