import Cocoa
import os

class MainMenu: NSMenu {
    let partialMenus: [PartialMenu] = [
        InstallDockerMenu(),
        OpenStreamMenu(),
        HistoryMenu(),
        UpdateMenu(),
        SelectPlayerMenu()
    ]

    let openHelpDialogItem = NSMenuItem(
        title: "Help on opening streams…",
        action: #selector(openHelpDialog(_:)),
        keyEquivalent: ""
    )

    let copyTVPlaylistURLItem = NSMenuItem(
        title: "Copy TV stream URL",
        action: #selector(copyTVPlaylistURL(_:)),
        keyEquivalent: ""
    )

    let configureGoogleTVItem = NSMenuItem(
        title: "Set Google TV ADB address...",
        action: #selector(configureGoogleTV(_:)),
        keyEquivalent: ""
    )

    let openGoogleTVItem = NSMenuItem(
        title: "Open VLC on Google TV",
        action: #selector(openGoogleTV(_:)),
        keyEquivalent: ""
    )

    let quitItem = NSMenuItem(
        title: "Quit Ace Link",
        action: #selector(NSApplication.shared.terminate(_:)),
        keyEquivalent: "q"
    )

    required init(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }

    override init(title: String) {
        super.init(title: title)

        autoenablesItems = false
        openHelpDialogItem.target = self
        copyTVPlaylistURLItem.target = self
        configureGoogleTVItem.target = self
        openGoogleTVItem.target = self

        for partialMenu in partialMenus {
            for item in partialMenu.items {
                addItem(item)
            }
        }

        addItem(openHelpDialogItem)
        addItem(copyTVPlaylistURLItem)
        addItem(configureGoogleTVItem)
        addItem(openGoogleTVItem)
        addItem(quitItem)

        update()
    }

    override func update() {
        let canPlay = Process.runCommand("docker", "--version").terminationStatus == 0
        for menu in partialMenus {
            menu.update(canPlay: canPlay)
        }
    }

    @objc
    func openHelpDialog(_: NSMenuItem?) {
        let alert = NSAlert()
        alert.messageText = "How to open a stream using Ace Link?"
        alert.informativeText = """
        The Open stream option is enabled when a supported format is detected on your clipboard.

        Supported formats:

        • AceStream hash.
        Example: 049ea83561b6213dee5ae806cfdf52838a4c921e

        • AceStream hash including protocol.
        Example: acestream://049ea83561b6213dee5ae806cfdf52838a4c921e

        • Magnet URI starting with magnet:?x followed by parameters.
        Example: magnet:?xt=urn:btih:c12fe1c06bbe254a9dc9f519b335aa7c1367a88a

        You can also open streams by selecting Ace Link when opening acestream:// or magnet: links.
        """
        alert.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 0))
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    func copyTVPlaylistURL(_: NSMenuItem?) {
        let url = AppConfig.tvCurrentURL.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Copied TV stream URL"
        alert.informativeText = """
        Open this URL in VLC on Google TV after starting a stream:

        \(url)
        """
        alert.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 0))
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc
    func configureGoogleTV(_: NSMenuItem?) {
        _ = promptForGoogleTVADBAddress()
    }

    @objc
    func openGoogleTV(_: NSMenuItem?) {
        if AppConfig.googleTVADBAddress == nil, !promptForGoogleTVADBAddress() {
            return
        }

        guard let address = AppConfig.googleTVADBAddress else {
            return
        }

        let url = AppConfig.tvCurrentManifestURL.absoluteString
        DispatchQueue.global(qos: .userInitiated).async {
            let connect = Process.runCommand("adb", "connect", address)
            if self.adbCommandFailed(connect) {
                self.showGoogleTVError(
                    "Cannot connect to Google TV at \(address).",
                    process: connect
                )
                return
            }

            let launch = Process.runCommand(
                "adb", "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", url,
                "-t", "application/x-mpegURL",
                "-p", "org.videolan.vlc"
            )
            if self.adbCommandFailed(launch) {
                self.showGoogleTVError(
                    "Cannot open VLC on Google TV. Make sure VLC is installed.",
                    process: launch
                )
                return
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Sent stream to Google TV"
                alert.informativeText = url
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func promptForGoogleTVADBAddress() -> Bool {
        let alert = NSAlert()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))

        field.stringValue = AppConfig.googleTVADBAddress ?? ""
        alert.messageText = "Google TV ADB address"
        alert.informativeText = """
        Enter the TV address from Wireless debugging.
        Example: 192.168.8.120:5555
        """
        alert.accessoryView = field
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        AppConfig.googleTVADBAddress = field.stringValue
        return AppConfig.googleTVADBAddress != nil
    }

    private func adbCommandFailed(_ process: Process) -> Bool {
        if process.terminationStatus != 0 {
            return true
        }

        let output = "\(process.standardOutContents)\n\(process.standardErrorContents)".lowercased()
        return output.contains("failed") ||
            output.contains("unable") ||
            output.contains("cannot") ||
            output.contains("error:") ||
            output.contains("no devices")
    }

    private func showGoogleTVError(_ message: String, process: Process) {
        let output = "\(process.standardOutContents)\n\(process.standardErrorContents)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            NSAlert.error(
                output.isEmpty ? message : "\(message)\n\nADB output:\n\(output)"
            )
        }
    }
}
