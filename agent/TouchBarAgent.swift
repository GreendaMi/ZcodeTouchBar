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

    // 与应用图标同款的“问号气泡”模板图（菜单栏 / Touch Bar 自动适配深浅色）
    static func questionBubbleImage(pointSize: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "questionmark.bubble", accessibilityDescription: "ZCode Touch Bar") else {
            return nil
        }
        let configured = base.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium)) ?? base
        configured.isTemplate = true
        return configured
    }

    // 控制条小图标：仅在有待处理询问时出现（空闲时 Touch Bar 完全交还前台应用）
    private func setupControlStrip() {
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(Self.stripIdentifier))
        let button: NSButton
        if let image = Self.questionBubbleImage(pointSize: 20) {
            button = NSButton(image: image, target: self, action: #selector(stripTapped))
        } else {
            button = NSButton(title: "💬", target: self, action: #selector(stripTapped))
        }
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

// MARK: - 应用入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard privateAPIAvailable() else {
            let msg = "zcode-touchbar-agent: Touch Bar 私有 API 不可用（机型无 Touch Bar 或系统已移除），退出\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(0) // SuccessfulExit=false：正常退出后 LaunchAgent 不再拉起
        }

        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = TouchBarController.questionBubbleImage(pointSize: 14)
        if item.button?.image == nil {
            item.button?.title = "💬"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "ZCode Touch Bar 助手运行中", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        item.menu = menu
        statusItem = item

        TouchBarController.shared.start()
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
