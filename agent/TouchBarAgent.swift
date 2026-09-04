// ZCode Touch Bar 助手
// 常驻 accessory 进程，监听 hook 写入的 request.json，在 Touch Bar 上显示按钮；
// 用户点选后写回 response.json（协议见 plugin/hooks/parse.jxa 头注释）。
//
// Touch Bar 展示采用 MTMR 验证过的私有 API（无窗口 App 也能全条接管）:
//   +[NSTouchBarItem addSystemTrayItem:]
//   +[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]
//   +[NSTouchBar dismissSystemModalTouchBar:]
//   DFRElementSetControlStripPresenceForIdentifier / DFRSystemModalShowsCloseBoxWhenFrontMost (DFRFoundation)
// 若系统升级导致这些 API 失效，进程启动即以 0 退出（LaunchAgent 不再拉起），
// hook 侧 2s 无 ack 自动降级，ZCode 原生询问不受任何影响。

import AppKit
import Darwin
import ObjectiveC.runtime

// MARK: - 私有 API 绑定

private let dfrHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

private func classIMP<A>(_ cls: AnyClass, _ selectorName: String) -> A? {
    let sel = NSSelectorFromString(selectorName)
    guard let method = class_getClassMethod(cls, sel) else { return nil }
    return unsafeBitCast(method_getImplementation(method), to: A.self)
}

private typealias AddTrayFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
private typealias PresentFn = @convention(c) (AnyObject, Selector, AnyObject, Int, AnyObject) -> Void
private typealias DismissFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
private typealias DFRSetPresenceFn = @convention(c) (CFString, Bool) -> Void
private typealias DFRShowsCloseBoxFn = @convention(c) (Bool) -> Void

private let dfrSetPresence: DFRSetPresenceFn? = {
    guard let h = dfrHandle, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return nil }
    return unsafeBitCast(sym, to: DFRSetPresenceFn.self)
}()

private let dfrShowsCloseBox: DFRShowsCloseBoxFn? = {
    guard let h = dfrHandle, let sym = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return nil }
    return unsafeBitCast(sym, to: DFRShowsCloseBoxFn.self)
}()

private let addTrayItem: AddTrayFn? = classIMP(NSTouchBarItem.self, "addSystemTrayItem:")
private let presentModal: PresentFn? =
    classIMP(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
private let dismissModal: DismissFn? = classIMP(NSTouchBar.self, "dismissSystemModalTouchBar:")

private func privateAPIAvailable() -> Bool {
    dfrHandle != nil
        && dfrSetPresence != nil
        && addTrayItem != nil
        && presentModal != nil
        && dismissModal != nil
}

// MARK: - 带回调的按钮

final class HandlerButton: NSButton {
    var handler: (() -> Void)?

    convenience init(title: String, color: NSColor? = nil, fontSize: CGFloat = 15, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        self.target = self
        self.action = #selector(clicked)
        if let color = color { self.bezelColor = color }
        self.font = NSFont.systemFont(ofSize: fontSize)
    }

    @objc private func clicked() { handler?() }
}

// MARK: - 控制器

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let stripIdentifier = "com.zpy.zcode-touchbar.strip"

    private let stateDir: String
    private var stripItem: NSCustomTouchBarItem?
    private var touchBar: NSTouchBar?
    private var barRequest: [String: Any]?
    private var currentID: String?

    init(stateDir: String) {
        self.stateDir = stateDir
        super.init()
    }

    private static func resolveStateDir() -> String {
        if let env = getenv("ZCODE_TOUCHBAR_STATE_DIR") {
            return String(cString: env)
        }
        return ("~/Library/Application Support/zcode-touchbar" as NSString).expandingTildeInPath
    }

    static let shared = TouchBarController(stateDir: resolveStateDir())

    func start() {
        setupControlStrip()
        let timer = Timer(timeInterval: 0.3, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        poll()
    }

    // 与应用图标同款的猫咪气泡剪影模板图（菜单栏 / Touch Bar 自动适配深浅色）
    static func catBubbleImage(height: CGFloat) -> NSImage {
        let aspect: CGFloat = 1.25            // 设计稿 25×20 单位
        let scale: CGFloat = 4                // 4x 位图，小尺寸依然锐利
        let w = height * aspect
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: w, height: height)
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let u = height * scale / 20           // 每单位像素

        // 气泡 + 双耳 + 尾巴（同色描边把耳尖圆角化）
        let shape = NSBezierPath()
        shape.append(NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 22, height: 13), xRadius: 5.5, yRadius: 5.5))
        shape.move(to: NSPoint(x: 4.6, y: 14.2)); shape.line(to: NSPoint(x: 6.0, y: 19.2)); shape.line(to: NSPoint(x: 8.8, y: 14.7)); shape.close()
        shape.move(to: NSPoint(x: 20.4, y: 14.2)); shape.line(to: NSPoint(x: 19.0, y: 19.2)); shape.line(to: NSPoint(x: 16.2, y: 14.7)); shape.close()
        shape.move(to: NSPoint(x: 4.8, y: 3.2)); shape.line(to: NSPoint(x: 3.0, y: 0.3)); shape.line(to: NSPoint(x: 8.6, y: 2.7)); shape.close()
        NSColor.black.setFill()
        shape.fill()
        NSColor.black.setStroke()
        shape.lineWidth = 0.9 * u
        shape.lineJoinStyle = .round
        shape.stroke()

        // 镂空双眼（destinationOut 打孔，保留模板图透明度）
        ctx.cgContext.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.5, y: 8.3, width: 2.6, height: 2.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14.9, y: 8.3, width: 2.6, height: 2.6)).fill()
        ctx.cgContext.setBlendMode(.normal)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: w, height: height))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    // 控制条小图标：仅在有待处理询问时出现（空闲时 Touch Bar 完全交还前台应用）
    private func setupControlStrip() {
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(Self.stripIdentifier))
        let button = NSButton(image: Self.catBubbleImage(height: 20), target: self, action: #selector(stripTapped))
        button.bezelColor = .controlAccentColor
        item.view = button
        stripItem = item
        addTrayItem?(NSTouchBarItem.self, NSSelectorFromString("addSystemTrayItem:"), item)
    }

    @objc private func stripTapped() {
        if let bar = touchBar {
            present(bar)
        }
    }

    @objc private func poll() {
        let now = Date().timeIntervalSince1970 * 1000
        guard let req = Self.readJSON(stateDir + "/request.json"),
              let id = req["id"] as? String,
              let deadline = req["deadline"] as? Double, deadline > now else {
            if touchBar != nil { dismiss() } // hook 超时清理了 request，收起
            return
        }
        guard id != currentID else { return }
        if touchBar != nil { dismiss() } // 新询问到来，先收起旧条
        currentID = id
        barRequest = req
        Self.writeJSON(stateDir + "/ack.json", ["id": id])
        show(req)
    }

    private func show(_ req: [String: Any]) {
        dfrShowsCloseBox?(false)
        let bar = buildBar(req)
        touchBar = bar
        present(bar)
        setStripPresence(true)
    }

    private func present(_ bar: NSTouchBar) {
        presentModal?(
            NSTouchBar.self,
            NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"),
            bar, 1, Self.stripIdentifier as NSString
        )
    }

    private func dismiss() {
        if let bar = touchBar {
            dismissModal?(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:"), bar)
        }
        touchBar = nil
        barRequest = nil
        currentID = nil
        setStripPresence(false)
    }

    private func setStripPresence(_ visible: Bool) {
        dfrSetPresence?(Self.stripIdentifier as CFString, visible)
    }

    // MARK: Touch Bar 内容

    private func buildBar(_ req: [String: Any]) -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        var identifiers: [NSTouchBarItem.Identifier] = [NSTouchBarItem.Identifier("zb.header")]
        if req["kind"] as? String == "question" {
            let count = (req["options"] as? [[String: Any]])?.count ?? 0
            for i in 0..<count {
                identifiers.append(NSTouchBarItem.Identifier("zb.opt\(i)"))
            }
        } else {
            identifiers.append(contentsOf: [
                NSTouchBarItem.Identifier("zb.allow"),
                NSTouchBarItem.Identifier("zb.deny"),
            ])
        }
        bar.defaultItemIdentifiers = identifiers
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let req = barRequest else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier.rawValue {
        case "zb.header":
            let text: String
            if req["kind"] as? String == "question" {
                text = "❓ " + Self.truncate(req["header"] as? String ?? "提问", 14)
            } else {
                let mark = (req["risk"] as? String) == "high" ? "⚠️" : "🔐"
                text = mark + " " + Self.truncate(req["tool"] as? String ?? "工具", 14)
            }
            item.view = HandlerButton(title: text, fontSize: 13) { [weak self] in
                self?.present(touchBar)
            }
        case "zb.allow":
            item.view = HandlerButton(title: "✓ 允许", color: .systemGreen) { [weak self] in
                self?.respond(["action": "allow"])
            }
        case "zb.deny":
            item.view = HandlerButton(title: "✕ 拒绝", color: .systemRed) { [weak self] in
                self?.respond(["action": "deny"])
            }
        default:
            guard identifier.rawValue.hasPrefix("zb.opt"),
                  let idx = Int(identifier.rawValue.dropFirst("zb.opt".count)) else { return nil }
            let options = req["options"] as? [[String: Any]] ?? []
            guard idx < options.count else { return nil }
            let label = options[idx]["label"] as? String ?? "?"
            let title = "\(idx + 1) " + Self.truncate(label, 10)
            item.view = HandlerButton(title: title, color: .controlAccentColor) { [weak self] in
                self?.respond(["choice": idx])
            }
        }
        return item
    }

    private func respond(_ payload: [String: Any]) {
        guard let id = currentID else { return }
        var body = payload
        body["id"] = id
        Self.writeJSON(stateDir + "/response.json", body)
        dismiss()
    }

    // MARK: 文件 IO

    static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func writeJSON(_ path: String, _ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let tmp = path + ".tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: data) else { return }
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    static func truncate(_ s: String, _ limit: Int) -> String {
        guard s.count > limit else { return s }
        let idx = s.index(s.startIndex, offsetBy: limit - 1)
        return String(s[..<idx]) + "…"
    }
}

// MARK: - Coding Plan 额度监控
//
// 读取 ~/.zcode/v2/ 配置里当前选中的 Coding Plan API Key（仅本机查询额度用），
// 调用监控接口拿 GLM Coding Plan 剩余额度，供状态栏菜单灰显展示。
// 默认 5 分钟节流，菜单项「刷新额度」可强制刷新。

final class UsageMonitor: NSObject {
    static let refreshInterval: TimeInterval = 300

    private static let domesticUsageURL = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    private static let intlUsageURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    private(set) var quotaLines: [String] = []   // 展示行：套餐 / 5 小时窗口 / 本周窗口 / MCP（≤4 行）
    private(set) var lastUpdated: Date?
    private(set) var isFetching = false
    private var lastFetchStart: Date?
    private var onUpdate: (() -> Void)?

    init(onUpdate: @escaping () -> Void) {
        self.onUpdate = onUpdate
        super.init()
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refresh(force: false)
        }
    }

    /// 菜单展开时调用；距上次拉取超过间隔才在后台刷新，平时展示缓存
    func menuWillOpen() {
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard !isFetching else { return }
        if !force, let last = lastFetchStart, Date().timeIntervalSince(last) < Self.refreshInterval { return }
        isFetching = true
        lastFetchStart = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = Self.fetchQuota()
            DispatchQueue.main.async {
                self.isFetching = false
                switch result {
                case .success(let lines):
                    self.quotaLines = lines
                    self.lastUpdated = Date()
                case .failure(let reason):
                    // 已有缓存数据时保留旧数据继续展示，仅无数据时给出错误行
                    if self.lastUpdated == nil {
                        self.quotaLines = ["额度：\(reason)"]
                    }
                }
                self.onUpdate?()
            }
        }
    }

    var refreshItemTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if isFetching {
            if let at = lastUpdated { return "刷新额度（更新于 \(formatter.string(from: at))，刷新中…）" }
            return "刷新额度（首次查询中…）"
        }
        if let at = lastUpdated { return "刷新额度（更新于 \(formatter.string(from: at))）" }
        return "刷新额度"
    }

    // MARK: 凭证解析

    private struct Credential {
        var apiKey: String
        var usageURL: URL
    }

    // Result 的 Failure 必须是 Error，这里只需要携带文案，用轻量枚举代替
    private enum QuotaResult<T> {
        case success(T)
        case failure(String)
    }

    private static func resolveCredential() -> QuotaResult<Credential> {
        if let env = getenv("ZCODE_TOUCHBAR_USAGE_API_KEY") {
            let key = String(cString: env)
            if !key.isEmpty {
                var url = domesticUsageURL
                if let envURL = getenv("ZCODE_TOUCHBAR_USAGE_URL"), let parsed = URL(string: String(cString: envURL)) {
                    url = parsed
                }
                return .success(Credential(apiKey: key, usageURL: url))
            }
        }
        let home = NSHomeDirectory() as NSString
        guard let settings = TouchBarController.readJSON(home.appendingPathComponent(".zcode/v2/setting.json")),
              let config = TouchBarController.readJSON(home.appendingPathComponent(".zcode/v2/config.json")),
              let providers = config["provider"] as? [String: Any] else {
            return .failure("未找到 ~/.zcode/v2 配置")
        }
        // setting.json 指向当前选中的 provider，形如 "coding-plan:builtin:bigmodel-coding-plan"
        var candidates: [String] = []
        if let selected = (settings["modelProviderFamilySelectedKeys"] as? [String: Any])?["bigmodel"] as? String {
            candidates.append(selected)
            if selected.hasPrefix("coding-plan:") {
                candidates.append(String(selected.dropFirst("coding-plan:".count)))
            }
        }
        candidates.append(contentsOf: ["builtin:bigmodel-coding-plan", "builtin:bigmodel-start-plan"])
        for id in candidates {
            if let cred = credential(for: id, in: providers) { return .success(cred) }
        }
        // 兜底：任意配置了 apiKey 的 provider，国内 bigmodel 端点优先
        var fallback: Credential?
        for (_, node) in providers {
            guard let dict = node as? [String: Any], let cred = credential(fromNode: dict) else { continue }
            if cred.usageURL == domesticUsageURL { return .success(cred) }
            fallback = fallback ?? cred
        }
        if let fallback = fallback { return .success(fallback) }
        return .failure("未读取到 ZCode API Key")
    }

    private static func credential(for id: String, in providers: [String: Any]) -> Credential? {
        guard let node = providers[id] as? [String: Any] else { return nil }
        return credential(fromNode: node)
    }

    private static func credential(fromNode node: [String: Any]) -> Credential? {
        guard let options = node["options"] as? [String: Any],
              let key = options["apiKey"] as? String, !key.isEmpty else { return nil }
        let base = options["baseURL"] as? String ?? ""
        return Credential(apiKey: key, usageURL: base.contains("z.ai") ? intlUsageURL : domesticUsageURL)
    }

    // MARK: 请求与解析

    private static func fetchQuota() -> QuotaResult<[String]> {
        switch resolveCredential() {
        case .failure(let reason):
            return .failure(reason)
        case .success(let cred):
            let first = request(cred: cred, bearer: false)
            if case .failure(let reason) = first, reason == "HTTP 401" || reason == "HTTP 403" {
                // 有的 key 要求 Bearer 前缀，重试一次
                if case .success(let lines) = request(cred: cred, bearer: true) { return .success(lines) }
            }
            return first
        }
    }

    private static func request(cred: Credential, bearer: Bool) -> QuotaResult<[String]> {
        var req = URLRequest(url: cred.usageURL)
        req.timeoutInterval = 15
        req.setValue(bearer ? "Bearer \(cred.apiKey)" : cred.apiKey, forHTTPHeaderField: "Authorization")
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        var status = 0
        var transportError: String?
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse { status = http.statusCode }
            if let error = error { transportError = error.localizedDescription }
            body = data
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        if status == 401 || status == 403 { return .failure("HTTP \(status)") }
        if let transportError = transportError { return .failure("网络错误：\(transportError)") }
        guard status == 200, let data = body else { return .failure("HTTP \(status)") }
        return parseQuota(data)
    }

    private static func parseQuota(_ data: Data) -> QuotaResult<[String]> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("响应解析失败")
        }
        let ok = (root["success"] as? Bool) ?? ((root["code"] as? Int) == 200)
        guard ok, let payload = root["data"] as? [String: Any] else {
            return .failure(root["msg"] as? String ?? "接口返回异常")
        }
        var lines: [String] = []
        if let level = payload["level"] as? String, !level.isEmpty {
            lines.append("GLM Coding Plan（\(level.capitalized)）")
        }
        let limits = payload["limits"] as? [[String: Any]] ?? []
        // 实测为 CREDIT_LIMIT；旧接口版本为 TOKENS_LIMIT。统一按重置时间升序，先重置的是 5 小时窗口
        let tokenLimits = limits
            .filter { ["CREDIT_LIMIT", "TOKENS_LIMIT"].contains($0["type"] as? String ?? "") }
            .sorted { resetInterval($0) < resetInterval($1) }
        let names = ["5 小时窗口", "本周窗口"]
        for (index, limit) in tokenLimits.prefix(2).enumerated() {
            lines.append(windowLine(named: names[index], limit))
        }
        if let mcp = limits.first(where: { ($0["type"] as? String) == "TIME_LIMIT" }) {
            lines.append(mcpLine(mcp))
        }
        guard !lines.isEmpty else { return .failure("接口未返回额度数据") }
        return .success(lines)
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func resetInterval(_ limit: [String: Any]) -> Double {
        number(limit["nextResetTime"]) ?? .infinity
    }

    private static func windowLine(named name: String, _ limit: [String: Any]) -> String {
        let usage = number(limit["usage"])
        let remaining = number(limit["remaining"])
        var remainPct: Int?
        if let usage = usage, usage > 0, let remaining = remaining {
            remainPct = Int((remaining / usage * 100).rounded())
        } else if let used = number(limit["percentage"]) {
            remainPct = Int((100 - used).rounded()) // percentage 为已用比例
        }
        var text = name
        if let pct = remainPct { text += " 剩余 \(min(max(pct, 0), 100))%" }
        if let reset = resetDate(limit["nextResetTime"]) {
            text += "（\(resetText(reset)) 重置）"
        }
        return text
    }

    private static func mcpLine(_ limit: [String: Any]) -> String {
        if let usage = number(limit["usage"]).map(Int.init),
           let used = number(limit["currentValue"]).map(Int.init) {
            return "MCP 月度 已用 \(used)/\(usage)"
        }
        if let used = number(limit["percentage"]) { return "MCP 月度 已用 \(Int(used))%" }
        return "MCP 月度额度"
    }

    private static func resetDate(_ value: Any?) -> Date? {
        guard let raw = number(value), raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
    }

    private static func resetText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 应用入口

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var usageMonitor: UsageMonitor?
    private var usageInfoItems: [NSMenuItem] = []   // 套餐 / 5 小时窗口 / 本周窗口 / MCP，空缺时隐藏
    private var usageRefreshItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard privateAPIAvailable() else {
            let msg = "zcode-touchbar-agent: Touch Bar 私有 API 不可用（机型无 Touch Bar 或系统已移除），退出\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(0) // SuccessfulExit=false：正常退出后 LaunchAgent 不再拉起
        }

        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = TouchBarController.catBubbleImage(height: 14)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "ZCode Touch Bar 助手运行中", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        for _ in 0..<4 {
            usageInfoItems.append(menu.addItem(withTitle: "", action: nil, keyEquivalent: ""))
        }
        let refreshItem = menu.addItem(withTitle: "刷新额度", action: #selector(refreshUsage), keyEquivalent: "")
        refreshItem.target = self
        usageRefreshItem = refreshItem
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        item.menu = menu
        statusItem = item

        let monitor = UsageMonitor(onUpdate: { [weak self] in self?.applyUsage() })
        usageMonitor = monitor
        applyUsage()
        monitor.start()

        TouchBarController.shared.start()
    }

    // NSMenuDelegate：每次展开菜单时应用缓存文案，并按节流决定是否后台拉取
    func menuNeedsUpdate(_ menu: NSMenu) {
        applyUsage()
        usageMonitor?.menuWillOpen()
    }

    @objc private func refreshUsage() {
        usageMonitor?.refresh(force: true)
        applyUsage()
    }

    private func applyUsage() {
        guard let monitor = usageMonitor else { return }
        let lines = monitor.quotaLines
        for (index, item) in usageInfoItems.enumerated() {
            if index < lines.count {
                item.title = lines[index]
                item.isHidden = false
            } else {
                item.isHidden = true
            }
        }
        usageRefreshItem?.title = monitor.refreshItemTitle
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let statePath = ("~/Library/Application Support/zcode-touchbar" as NSString).expandingTildeInPath
try? FileManager.default.createDirectory(atPath: statePath, withIntermediateDirectories: true)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
