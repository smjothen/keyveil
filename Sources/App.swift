import AppKit
import Carbon.HIToolbox
import WebKit

// ── Corner enum ───────────────────────────────────────────────────────────────

enum Corner: String, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft
    var title: String {
        switch self {
        case .topRight:    return "Top Right"
        case .topLeft:     return "Top Left"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft:  return "Bottom Left"
        }
    }
}

// ── AppDelegate ───────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {

    // Existing
    private var sidebar: NSPanel?
    private var webView: WKWebView?
    private var hotKeyRef: EventHotKeyRef?
    private var fileMonitors: [(source: DispatchSourceFileSystemObject, fd: CInt)] = []
    private var statusItem: NSStatusItem?
    private var savedScroll: CGPoint = .zero
    var svgFiles: [URL] = []
    private var compactSpacing = false

    // Feature 1 – Opacity
    private var overlayOpacity: Double = 1.0

    // Feature 2 – Corner snapping
    private var corner: Corner = .topRight

    // Feature 3 – Draggable
    private var isRepositioning = false
    private var customPosition: CGPoint? = nil

    // Feature 5 – Auto-hide
    private var autoHideSeconds: Int = 0
    private var autoHideTask: DispatchWorkItem? = nil

    // Feature 7 – Per-display
    private var selectedScreenIndex: Int = 0

    // Feature 8 – Trim padding
    private var trimPadding: Int = 4

    // Feature 9 – Scale
    private var scalePercent: Int = 100

    // Feature 10 – WebKit SVG sanitization
    private var sanitizeSVGForWebKitEnabled = true

    // Feature 11 – Optional per-image card
    private var showPerImageWhiteCard = false

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        loadPersistedState()

        if let path = CommandLine.arguments.dropFirst().first {
            let url = URL(fileURLWithPath: path)
            if !svgFiles.contains(url) { svgFiles.append(url) }
        }

        buildSidebar()
        registerHotKey()
        buildStatusItem()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hideSidebar(); return nil }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAllMonitors()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func loadPersistedState() {
        compactSpacing = UserDefaults.standard.bool(forKey: "compactSpacing")
        let paths = UserDefaults.standard.stringArray(forKey: "svgFilePaths") ?? []
        svgFiles = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        overlayOpacity      = UserDefaults.standard.object(forKey: "overlayOpacity")      as? Double ?? 1.0
        corner              = Corner(rawValue: UserDefaults.standard.string(forKey: "corner") ?? "") ?? .topRight
        autoHideSeconds     = UserDefaults.standard.object(forKey: "autoHideSeconds")     as? Int ?? 0
        selectedScreenIndex = UserDefaults.standard.object(forKey: "selectedScreenIndex") as? Int ?? 0
        trimPadding         = UserDefaults.standard.object(forKey: "trimPadding")         as? Int ?? 4
        scalePercent        = UserDefaults.standard.object(forKey: "scalePercent")        as? Int ?? 100
        if UserDefaults.standard.object(forKey: "sanitizeSVGForWebKitEnabled") != nil {
            sanitizeSVGForWebKitEnabled = UserDefaults.standard.bool(forKey: "sanitizeSVGForWebKitEnabled")
        }
        showPerImageWhiteCard = UserDefaults.standard.bool(forKey: "showPerImageWhiteCard")

        if UserDefaults.standard.object(forKey: "customPositionX") != nil {
            customPosition = CGPoint(
                x: UserDefaults.standard.double(forKey: "customPositionX"),
                y: UserDefaults.standard.double(forKey: "customPositionY")
            )
        }
    }

    private func saveState() {
        UserDefaults.standard.set(svgFiles.map(\.path), forKey: "svgFilePaths")
        UserDefaults.standard.set(compactSpacing,       forKey: "compactSpacing")
        UserDefaults.standard.set(overlayOpacity,       forKey: "overlayOpacity")
        UserDefaults.standard.set(corner.rawValue,      forKey: "corner")
        UserDefaults.standard.set(autoHideSeconds,      forKey: "autoHideSeconds")
        UserDefaults.standard.set(selectedScreenIndex,  forKey: "selectedScreenIndex")
        UserDefaults.standard.set(trimPadding,          forKey: "trimPadding")
        UserDefaults.standard.set(scalePercent,         forKey: "scalePercent")
        UserDefaults.standard.set(sanitizeSVGForWebKitEnabled, forKey: "sanitizeSVGForWebKitEnabled")
        UserDefaults.standard.set(showPerImageWhiteCard, forKey: "showPerImageWhiteCard")

        if let pos = customPosition {
            UserDefaults.standard.set(pos.x, forKey: "customPositionX")
            UserDefaults.standard.set(pos.y, forKey: "customPositionY")
        } else {
            UserDefaults.standard.removeObject(forKey: "customPositionX")
            UserDefaults.standard.removeObject(forKey: "customPositionY")
        }
    }

    // ── Status bar ───────────────────────────────────────────────────────────

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "SVG Popup")
        item.menu = NSMenu()
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        // ── A: Files ──────────────────────────────────────────────────────────
        menu.addItem(target(title: "Add SVG…", action: #selector(addSVG)))

        if !svgFiles.isEmpty {
            menu.addItem(.separator())
            for (i, url) in svgFiles.enumerated() {
                let it = target(title: url.lastPathComponent, action: #selector(removeSVG(_:)))
                it.tag = i
                it.toolTip = "Click to remove"
                menu.addItem(it)
            }
        }

        // ── B: Display / layout ───────────────────────────────────────────────
        menu.addItem(.separator())

        menu.addItem(target(title: "Reload SVGs", action: #selector(reloadSVGs)))

        let compact = target(title: "Compact Spacing", action: #selector(toggleCompact))
        compact.state = compactSpacing ? .on : .off
        menu.addItem(compact)

        menu.addItem(submenu("Scale", items: [50, 75, 100, 125, 150, 200].map { pct in
            checked("\(pct)%", action: #selector(setScale(_:)), value: pct, current: scalePercent)
        }))

        let trimOptions: [(String, Int)] = [("Off", 0), ("Tight (2px)", 2), ("Normal (4px)", 4), ("Loose (8px)", 8)]
        menu.addItem(submenu("Trim Whitespace", items: trimOptions.map { label, val in
            checked(label, action: #selector(setTrimPadding(_:)), value: val, current: trimPadding)
        }))

        let webkitFix = target(title: "SVG Compatibility Mode", action: #selector(toggleWebKitSVGFix))
        webkitFix.state = sanitizeSVGForWebKitEnabled ? .on : .off
        menu.addItem(webkitFix)

        let whiteCard = target(title: "White Image Card", action: #selector(toggleWhiteImageCard))
        whiteCard.state = showPerImageWhiteCard ? .on : .off
        menu.addItem(whiteCard)

        // ── C: Opacity ────────────────────────────────────────────────────────
        menu.addItem(.separator())

        let opacityOptions: [(String, Double)] = [("25%", 0.25), ("50%", 0.50), ("75%", 0.75), ("100%", 1.0)]
        menu.addItem(submenu("Opacity", items: opacityOptions.map { label, val in
            checked(label, action: #selector(setOpacity(_:)), value: val, current: overlayOpacity)
        }))

        // ── D: Position ───────────────────────────────────────────────────────
        menu.addItem(.separator())

        menu.addItem(submenu("Corner", items: Corner.allCases.map { c in
            let it = checked(c.title, action: #selector(setCorner(_:)),
                             value: c.rawValue, current: corner.rawValue)
            it.state = (customPosition == nil && corner == c) ? .on : .off
            return it
        }))

        let repoTitle = isRepositioning ? "Lock Position" : "Reposition…"
        menu.addItem(target(title: repoTitle, action: #selector(toggleReposition)))

        let screens = NSScreen.screens
        if screens.count > 1 {
            menu.addItem(submenu("Display", items: screens.enumerated().map { i, screen in
                let name: String
                if #available(macOS 10.15, *) { name = screen.localizedName }
                else { name = "Screen \(i + 1)" }
                let it = target(title: name, action: #selector(setScreen(_:)))
                it.tag = i
                it.state = selectedScreenIndex == i ? .on : .off
                return it
            }))
        }

        // ── E: Behaviour ──────────────────────────────────────────────────────
        menu.addItem(.separator())

        let autoHideOptions: [(String, Int)] = [("Off", 0), ("5 seconds", 5), ("10 seconds", 10), ("30 seconds", 30)]
        menu.addItem(submenu("Auto-hide", items: autoHideOptions.map { label, val in
            checked(label, action: #selector(setAutoHide(_:)), value: val, current: autoHideSeconds)
        }))

        let loginItem = target(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        // ── F: App ────────────────────────────────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // ── Menu helpers ──────────────────────────────────────────────────────────

    private func target(title: String, action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    /// Creates a menu item whose check state is determined by whether `value == current`.
    /// Uses `representedObject` to ferry the value to the selector.
    private func checked<T: Equatable>(_ title: String, action: Selector,
                                       value: T, current: T) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.representedObject = value as AnyObject
        it.state = value == current ? .on : .off
        return it
    }

    // ── File actions ──────────────────────────────────────────────────────────

    @objc private func addSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Add SVG files"
        guard panel.runModal() == .OK else { return }

        let wasEmpty = svgFiles.isEmpty
        for url in panel.urls where !svgFiles.contains(url) { svgFiles.append(url) }
        saveState(); rebuildMenu(); resizeSidebar(); rebuildContent()
        startMonitoring(for: panel.urls)
        if wasEmpty && !svgFiles.isEmpty { showSidebar() }
    }

    @objc private func removeSVG(_ sender: NSMenuItem) {
        guard svgFiles.indices.contains(sender.tag) else { return }
        svgFiles.remove(at: sender.tag)
        stopAllMonitors(); startMonitoring(for: svgFiles)
        saveState(); rebuildMenu(); resizeSidebar(); rebuildContent()
    }

    // ── Setting actions ───────────────────────────────────────────────────────

    @objc private func reloadSVGs() {
        rebuildContent()
    }

    @objc private func toggleCompact() {
        compactSpacing.toggle()
        saveState(); rebuildMenu(); rebuildContent()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Double else { return }
        overlayOpacity = val
        saveState(); rebuildMenu()
        guard let wv = webView, sidebar?.isVisible == true else { return }
        wv.evaluateJavaScript("document.body.style.opacity = '\(overlayOpacity)'", completionHandler: nil)
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Int else { return }
        scalePercent = val
        saveState(); rebuildMenu(); resizeSidebar(); rebuildContent()
    }

    @objc private func setTrimPadding(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Int else { return }
        trimPadding = val
        saveState(); rebuildMenu(); rebuildContent()
    }

    @objc private func toggleWebKitSVGFix() {
        sanitizeSVGForWebKitEnabled.toggle()
        saveState(); rebuildMenu(); rebuildContent()
    }

    @objc private func toggleWhiteImageCard() {
        showPerImageWhiteCard.toggle()
        saveState(); rebuildMenu(); rebuildContent()
    }

    @objc private func setCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = Corner(rawValue: raw) else { return }
        corner = c
        customPosition = nil
        saveState(); rebuildMenu(); resizeSidebar()
    }

    @objc private func toggleReposition() {
        isRepositioning.toggle()
        sidebar?.ignoresMouseEvents = !isRepositioning
        sidebar?.isMovableByWindowBackground = isRepositioning
        if !isRepositioning, let origin = sidebar?.frame.origin {
            customPosition = origin
            saveState()
        }
        rebuildMenu()
    }

    @objc private func setScreen(_ sender: NSMenuItem) {
        selectedScreenIndex = sender.tag
        saveState(); rebuildMenu(); resizeSidebar()
    }

    @objc private func setAutoHide(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Int else { return }
        autoHideSeconds = val
        saveState(); rebuildMenu()
    }

    // ── Launch at login ───────────────────────────────────────────────────────

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.svgpopup.plist")
    }

    private var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @objc private func toggleLaunchAtLogin() {
        if isLaunchAtLoginEnabled {
            launchctl("unload", launchAgentURL.path)
            try? FileManager.default.removeItem(at: launchAgentURL)
        } else {
            let plist: [String: Any] = [
                "Label": "com.keyveil",
                "ProgramArguments": [CommandLine.arguments[0]],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: launchAgentURL)
                launchctl("load", launchAgentURL.path)
            }
        }
        rebuildMenu()
    }

    private func launchctl(_ verb: String, _ path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = [verb, path]
        try? proc.run(); proc.waitUntilExit()
    }

    // ── Sidebar panel ─────────────────────────────────────────────────────────

    private func buildSidebar() {
        let frame = sidebarFrame()

        let wv = WKWebView(frame: NSRect(origin: .zero, size: frame.size))
        wv.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { wv.underPageBackgroundColor = .clear }
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        webView = wv

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = wv
        panel.alphaValue = 1
        sidebar = panel

        if !svgFiles.isEmpty {
            rebuildContent()
            startMonitoring(for: svgFiles)
        }
    }

    private func activeScreen() -> NSScreen {
        let screens = NSScreen.screens
        return screens.indices.contains(selectedScreenIndex)
            ? screens[selectedScreenIndex]
            : (NSScreen.main ?? screens[0])
    }

    private func sidebarFrame() -> NSRect {
        let sf = activeScreen().visibleFrame
        let margin: CGFloat = 8
        let raw: CGFloat = svgFiles.isEmpty ? 400 : min(maxSVGWidth(), sf.width - margin * 2)
        let w = (raw * CGFloat(scalePercent) / 100).rounded()
        let h = (sf.height * 0.9).rounded()

        if let pos = customPosition {
            return NSRect(origin: pos, size: CGSize(width: w, height: h))
        }

        let x: CGFloat, y: CGFloat
        switch corner {
        case .topRight:    x = sf.maxX - w - margin; y = sf.maxY - h
        case .topLeft:     x = sf.minX + margin;     y = sf.maxY - h
        case .bottomRight: x = sf.maxX - w - margin; y = sf.minY + margin
        case .bottomLeft:  x = sf.minX + margin;     y = sf.minY + margin
        }
        return NSRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
    }

    private func resizeSidebar() {
        guard let panel = sidebar, let wv = webView else { return }
        let frame = sidebarFrame()
        panel.setFrame(frame, display: true)
        wv.setFrameSize(frame.size)
    }

    // ── SVG content ───────────────────────────────────────────────────────────

    func rebuildContent() {
        guard let wv = webView else { return }

        var items = ""
        for (i, url) in svgFiles.enumerated() {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let svg = sanitizeSVGForWebKitEnabled ? sanitizeSVGForWebKit(raw) : raw
            if i > 0 { items += "<div class='divider'></div>" }
            let label = svgFiles.count > 1 ? "<p class='label'>\(url.lastPathComponent)</p>" : ""
            let visual = showPerImageWhiteCard ? "<div class='svg-card'>\(svg)</div>" : svg
            items += "<div class='item'>\(visual)\(label)</div>"
        }

        let bodyClass = showPerImageWhiteCard ? "with-image-card" : ""

        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        * { margin: 0; padding: 0; }
        html, body { background: transparent; font-family: -apple-system, sans-serif; }
        body { zoom: \(scalePercent)%; opacity: \(overlayOpacity); transition: opacity 0.15s linear; }
        ::-webkit-scrollbar { display: none; }
        .item { padding: \(compactSpacing ? "0" : "8px 0"); }
        .svg-card { display: inline-block; background: transparent; }
        body.with-image-card .svg-card {
            background: #fff;
            border-radius: 12px;
            padding: 8px;
        }
        .item svg { display: block; }
        .label { font-size: 10px; font-weight: 600; letter-spacing: 0.04em;
                 text-transform: uppercase; color: white;
                 text-shadow: 0 1px 3px rgba(0,0,0,0.7);
                 margin-top: \(compactSpacing ? "2px" : "4px"); padding: 0 8px;
                 margin-bottom: \(compactSpacing ? "2px" : "4px"); }
        .divider { height: \(compactSpacing ? "4px" : "12px"); }
        </style></head>
        <body class='\(bodyClass)'>\(items)</body></html>
        """
        wv.loadHTMLString(html, baseURL: nil)
    }

    // ── WKNavigationDelegate ─────────────────────────────────────────────────

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let restore = { [weak self] in
            guard let self else { return }
            webView.evaluateJavaScript(
                "window.scrollTo(\(savedScroll.x), \(savedScroll.y))", completionHandler: nil)
        }

        guard trimPadding > 0 else { restore(); return }

        let trim = """
        document.querySelectorAll('svg').forEach(function(svg) {
            try {
                var b = svg.getBBox(), p = \(trimPadding);
                if (!b.width || !b.height) return;
                svg.setAttribute('viewBox',(b.x-p)+' '+(b.y-p)+' '+(b.width+p*2)+' '+(b.height+p*2));
                svg.setAttribute('width',  b.width  + p * 2);
                svg.setAttribute('height', b.height + p * 2);
            } catch(e) {}
        });
        """
        webView.evaluateJavaScript(trim) { _, _ in restore() }
    }

    private func sanitizeSVGForWebKit(_ content: String) -> String {
        var svg = content
        svg = svg.replacingOccurrences(of: "<defs>/* start glyphs */", with: "<defs>")
        svg = svg.replacingOccurrences(of: "</defs>/* end glyphs */", with: "</defs>")
        svg = convertNestedGlyphSVGsToSymbols(in: svg)
        svg = normalizeFragmentIDs(in: svg)
        return svg
    }

    private func convertNestedGlyphSVGsToSymbols(in content: String) -> String {
        let pattern = #"<svg\s+id="([^"]+)">\s*<svg([^>]*)>(.*?)</svg>\s*</svg>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: range,
            withTemplate: #"<symbol id="$1"$2>$3</symbol>"#
        )
    }

    private func normalizeFragmentIDs(in content: String) -> String {
        guard let idRegex = try? NSRegularExpression(pattern: #"id="([^"]*:[^"]*)""#) else {
            return content
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = idRegex.matches(in: content, options: [], range: range)
        if matches.isEmpty { return content }

        var ids: [(old: String, new: String)] = []
        var seen = Set<String>()

        for match in matches {
            guard let idRange = Range(match.range(at: 1), in: content) else { continue }
            let oldID = String(content[idRange])
            guard seen.insert(oldID).inserted else { continue }
            ids.append((old: oldID, new: oldID.replacingOccurrences(of: ":", with: "_")))
        }

        var svg = content
        for id in ids {
            svg = svg.replacingOccurrences(of: "id=\"\(id.old)\"", with: "id=\"\(id.new)\"")
            svg = svg.replacingOccurrences(of: "href=\"#\(id.old)\"", with: "href=\"#\(id.new)\"")
            svg = svg.replacingOccurrences(of: "xlink:href=\"#\(id.old)\"", with: "xlink:href=\"#\(id.new)\"")
            svg = svg.replacingOccurrences(of: "url(#\(id.old))", with: "url(#\(id.new))")
        }
        return svg
    }

    // ── File monitoring ───────────────────────────────────────────────────────

    private func startMonitoring(for urls: [URL]) {
        for url in urls {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let mon = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .global(qos: .utility))
            mon.setEventHandler { [weak self] in DispatchQueue.main.async { self?.rebuildContent() } }
            mon.setCancelHandler { close(fd) }
            mon.resume()
            fileMonitors.append((source: mon, fd: fd))
        }
    }

    private func stopAllMonitors() {
        fileMonitors.forEach { $0.source.cancel() }
        fileMonitors.removeAll()
    }

    // ── SVG size parsing ──────────────────────────────────────────────────────

    private func maxSVGWidth() -> CGFloat {
        svgFiles.compactMap { url -> CGFloat? in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parseSVGSize(content).width
        }.max() ?? 400
    }

    private func parseSVGSize(_ content: String) -> NSSize {
        if let vb = firstCapture(#"viewBox="([^"]+)""#, in: content) {
            let parts = vb.split(separator: " ").compactMap { Double($0) }
            if parts.count == 4 { return NSSize(width: parts[2], height: parts[3]) }
        }
        let w = firstCapture(#"<svg[^>]*\swidth="([0-9.]+)"#, in: content).flatMap(Double.init)
        let h = firstCapture(#"<svg[^>]*\sheight="([0-9.]+)"#, in: content).flatMap(Double.init)
        if let w, let h { return NSSize(width: w, height: h) }
        return NSSize(width: 400, height: 200)
    }

    private func firstCapture(_ pattern: String, in string: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let r = Range(m.range(at: 1), in: string)
        else { return nil }
        return String(string[r])
    }

    // ── Hotkey ───────────────────────────────────────────────────────────────

    private func registerHotKey() {
        let keyCode: UInt32   = 40
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var id = EventHotKeyID()
        id.signature = fourCharCode("svgp")
        id.id = 1

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue().toggleSidebar()
                return OSStatus(noErr)
            },
            1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil
        )
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // ── Toggle / show / hide ─────────────────────────────────────────────────

    @objc func toggleSidebar() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = sidebar else { return }
            if panel.isVisible { hideSidebar() } else { showSidebar() }
        }
    }

    private func showSidebar() {
        guard let panel = sidebar else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        autoHideTask?.cancel()
        if autoHideSeconds > 0 {
            let task = DispatchWorkItem { [weak self] in self?.hideSidebar(duration: 0.8) }
            autoHideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(autoHideSeconds), execute: task)
        }
    }

    private func hideSidebar(duration: TimeInterval = 0.15) {
        autoHideTask?.cancel(); autoHideTask = nil
        webView?.evaluateJavaScript("[window.scrollX, window.scrollY]") { [weak self] result, _ in
            if let arr = result as? [Double], arr.count == 2 {
                self?.savedScroll = CGPoint(x: arr[0], y: arr[1])
            }
        }
        guard let panel = sidebar else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func fourCharCode(_ s: String) -> FourCharCode {
    s.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
}
