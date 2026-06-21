import Foundation

// QuickTime and Safari cannot play streams when loaded from a m3u8 file from the local filesystem.
class PlaylistServer: Service {
    private let engine: AceStreamEngine
    private let stream: StreamFile
    override var defaultError: String { "Cannot launch Python server." }
    private static let serverScript = """
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import json
    import sys
    from urllib.parse import urlsplit

    stream_url = sys.argv[1]
    manifest_url = sys.argv[2]
    title = sys.argv[3].replace("\\r", " ").replace("\\n", " ")
    port = int(sys.argv[4])
    state_path = "current-stream.json"

    def write_state():
        state = {
            "stream_url": stream_url,
            "manifest_url": manifest_url,
            "title": title,
        }
        with open(state_path, "w", encoding="utf-8") as file:
            json.dump(state, file)
        playlist = playlist_for(state)
        with open("acelink.m3u8", "w", encoding="utf-8", newline="") as file:
            file.write(playlist)
        with open("acelink.m3u", "w", encoding="utf-8", newline="") as file:
            file.write(playlist)

    def read_state():
        with open(state_path, "r", encoding="utf-8") as file:
            return json.load(file)

    def playlist_for(state):
        return (
            "#EXTM3U\\r\\n"
            "#EXTINF:-1, Ace Link - " + state["title"] + "\\r\\n"
            + state["manifest_url"] + "\\r\\n"
        )

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_OPTIONS(self):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
            self.end_headers()

        def do_HEAD(self):
            self.handle_request(send_body=False)

        def do_GET(self):
            self.handle_request(send_body=True)

        def handle_request(self, send_body=True):
            path = urlsplit(self.path).path
            state = read_state()

            if path in ("/acelink.m3u8", "/acelink.m3u"):
                self.send_playlist(state, send_body)
                return

            if path in ("/current", "/current.ts", "/current.raw"):
                self.redirect(state["stream_url"])
                return

            if path == "/current.m3u8":
                self.redirect(state["manifest_url"])
                return

            self.send_response(404)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

        def send_playlist(self, state, send_body):
            body = playlist_for(state).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "audio/x-mpegurl; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if send_body:
                self.wfile.write(body)

        def redirect(self, url):
            self.send_response(302)
            self.send_header("Location", url)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

    write_state()
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
    """

    init(engine: AceStreamEngine, stream: StreamFile) {
        self.engine = engine
        self.stream = stream
        super.init()
    }

    override func run() {
        _ = Process.runCommand(
            "docker", "exec", "--detach", "--workdir=/acelink", engine.containerID!,
            "python3", "-c", PlaylistServer.serverScript,
            stream.tvStreamURL.absoluteString,
            stream.tvManifestURL.absoluteString,
            stream.title,
            "\(AppConstants.Docker.proxyPort)"
        )
    }

    override func check() {
        urlSession.dataTask(with: stream.playlistURL) { _, response, _ in
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    self.callbackInMainThread()
                    return
                }
            }
            self.scheduleCheck()
        }.resume()
    }
}
