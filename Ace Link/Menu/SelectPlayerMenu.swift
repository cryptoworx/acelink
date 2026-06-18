import Cocoa
import Foundation
import os

class SelectPlayerMenu: PartialMenu {
    private let liveBufferTimeMenuItem = NSMenuItem()
    private let liveBufferTimeField = NSTextField(frame: NSRect(x: 0, y: 0, width: 64, height: 22))
    private let vodBufferMenuItem = NSMenuItem()
    private let vodBufferField = NSTextField(frame: NSRect(x: 0, y: 0, width: 64, height: 22))

    private let selectPlayerMenuItem = NSMenuItem(
        title: "Change media player…",
        action: #selector(selectPlayer),
        keyEquivalent: ""
    )

    override public var items: [NSMenuItem] {
        [NSMenuItem.separator(), liveBufferTimeMenuItem, vodBufferMenuItem, selectPlayerMenuItem]
    }

    override init() {
        super.init()
        setUpBufferItem(
            menuItem: liveBufferTimeMenuItem,
            field: liveBufferTimeField,
            label: "live buffer (seconds)",
            value: AppConfig.liveBufferTime,
            action: #selector(updateLiveBufferTime(_:)),
            editingDidEnd: #selector(liveBufferTimeEditingDidEnd(_:))
        )
        setUpBufferItem(
            menuItem: vodBufferMenuItem,
            field: vodBufferField,
            label: "vod buffer (seconds)",
            value: AppConfig.vodBuffer,
            action: #selector(updateVodBuffer(_:)),
            editingDidEnd: #selector(vodBufferEditingDidEnd(_:))
        )
        selectPlayerMenuItem.target = self
        if AppConfig.playerBundleIdentifier == nil {
            setDefaultPlayer()
        }
    }

    private func setUpBufferItem(
        menuItem: NSMenuItem,
        field: NSTextField,
        label labelText: String,
        value: Int,
        action: Selector,
        editingDidEnd: Selector
    ) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        let label = NSTextField(labelWithString: labelText)
        let formatter = NumberFormatter()

        formatter.allowsFloats = false
        formatter.minimum = 0

        label.frame = NSRect(x: 16, y: 7, width: 152, height: 20)
        field.frame = NSRect(x: 176, y: 6, width: 64, height: 22)
        field.alignment = .right
        field.formatter = formatter
        field.integerValue = value
        field.target = self
        field.action = action

        NotificationCenter.default.addObserver(
            self,
            selector: editingDidEnd,
            name: NSControl.textDidEndEditingNotification,
            object: field
        )

        row.addSubview(label)
        row.addSubview(field)
        menuItem.view = row
    }

    @objc
    private func updateLiveBufferTime(_ sender: NSTextField) {
        AppConfig.liveBufferTime = sender.integerValue
        sender.integerValue = AppConfig.liveBufferTime
    }

    @objc
    private func liveBufferTimeEditingDidEnd(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }
        updateLiveBufferTime(field)
    }

    @objc
    private func updateVodBuffer(_ sender: NSTextField) {
        AppConfig.vodBuffer = sender.integerValue
        sender.integerValue = AppConfig.vodBuffer
    }

    @objc
    private func vodBufferEditingDidEnd(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }
        updateVodBuffer(field)
    }

    private func setDefaultPlayer() {
        let playerBundleIdentifiers = [
            "org.videolan.vlc",
            "com.colliderli.iina",
            "io.mpv",
            "com.apple.QuickTimePlayerX",
            "com.apple.Safari"
        ]
        if let player = getFirstInstalledBundle(bundleIdentifiers: playerBundleIdentifiers) {
            setPlayer(bundle: player)
        }
    }

    private func getFirstInstalledBundle(bundleIdentifiers: [String]) -> Bundle? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return Bundle(url: url)
            }
        }
        return nil
    }

    @objc
    func selectPlayer(_: NSMenuItem?) {
        let dialog = NSOpenPanel()

        dialog.message = "Select a media player"
        dialog.allowedFileTypes = ["app"]
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = true
        dialog.directoryURL = URL(string: "file:///Applications")
        dialog.showsHiddenFiles = false
        dialog.treatsFilePackagesAsDirectories = false

        if dialog.runModal() == NSApplication.ModalResponse.OK {
            if let url = dialog.url, let bundle = Bundle(url: url) {
                os_log("Selected app %{public}@", bundle.name)
                setPlayer(bundle: bundle)
            }
        }
    }

    func setPlayer(bundle: Bundle) {
        warnCapabilities(bundle: bundle)
        AppConfig.playerBundleIdentifier = bundle.bundleIdentifier
    }

    private func warnCapabilities(bundle: Bundle) {
        if bundle.supports(fileExtension: "mkv") {
            // Players that support mkv will likely play anything you throw at it.
            // Typically we need h264, ac3, adts and ts support, however streams could use any
            // codec.
            // Browsers are unable to play the adts audio codec, which is relatively popular in
            // streams.
            return
        }

        if bundle.bundleIdentifier == Bundle.main.infoDictionary!["CFBundleIdentifier"] as? String {
            NSAlert.error("This causes the universe to implode.")
            return
        }

        let recommendSentence = "Switch to VLC or IINA if you encounter " +
            "issues playing streams using this app."

        if bundle.isBrowser || bundle.supports(typeConformsTo: "public.movie") {
            NSAlert.warning(
                messageText: "Not all streams supported",
                informativeText: "\(bundle.name) does not support all audio and video encodings. " +
                    recommendSentence
            )
        } else {
            NSAlert.warning(
                messageText: "No player capabilities detected",
                informativeText: "\(bundle.name) will likely not be able to play streams. " +
                    recommendSentence
            )
        }
    }
}
