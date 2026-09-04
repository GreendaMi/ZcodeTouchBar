// 生成 zcode-touchbar 应用图标（macOS 风格：深色 squircle + 对话气泡 + Touch Bar 按键）
// 用法: make-icon <iconset输出目录> <预览png路径>
// 之后用 `iconutil -c icns <iconset目录> -o AppIcon.icns` 打包。
import AppKit

let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let previewPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon.png"

// ── 调色板 ──────────────────────────────────────────────────────────────────
let bgTop = NSColor(srgbRed: 0.149, green: 0.149, blue: 0.173, alpha: 1)      // #26262C
let bgBottom = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.070, alpha: 1)   // #0E0E12
let bubbleTop = NSColor(srgbRed: 0.353, green: 0.722, blue: 1.0, alpha: 1)    // #5AB8FF
let bubbleBottom = NSColor(srgbRed: 0.541, green: 0.361, blue: 1.0, alpha: 1) // #8A5CFF
let barBlack = NSColor(srgbRed: 0.031, green: 0.031, blue: 0.043, alpha: 1)   // Touch Bar 纯黑
let keyGray = NSColor(srgbRed: 0.235, green: 0.235, blue: 0.259, alpha: 1)    // #3C3C42
let keyBlueTop = NSColor(srgbRed: 0.353, green: 0.784, blue: 0.980, alpha: 1) // #5AC8FA
let keyBlueBottom = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)// #0A84FF
let keyGreen = NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)   // #30D158
let keyRed = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)       // #FF453A

let S: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // squircle 背景（Big Sur 网格：824 居中，圆角 185）
    let squircle = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: NSSize(width: 0, height: -20), blur: 42, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    bgBottom.setFill()
    squircle.fill()
    ctx.restoreGState()

    NSGradient(starting: bgTop, ending: bgBottom)?
        .draw(in: squircle, angle: -90)
    NSColor.white.withAlphaComponent(0.06).setStroke()
    squircle.lineWidth = 6
    squircle.stroke()

    // 对话气泡 + 下垂尾巴（尾巴尖端会被 Touch Bar 条盖住，形成“指向”关系）
    let bubble = NSBezierPath(roundedRect: NSRect(x: 212, y: 430, width: 600, height: 330), xRadius: 105, yRadius: 105)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 350, y: 442))
    tail.line(to: NSPoint(x: 328, y: 320))
    tail.line(to: NSPoint(x: 492, y: 442))
    tail.close()
    bubble.append(tail)
    NSGradient(starting: bubbleTop, ending: bubbleBottom)?.draw(in: bubble, angle: -90)

    // “?”（AI 在提问）
    let font = NSFont.systemFont(ofSize: 258, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let q = NSAttributedString(string: "?", attributes: attrs)
    let qSize = q.size()
    q.draw(at: NSPoint(x: 512 - qSize.width / 2, y: 430 + (330 - qSize.height) / 2 - 8))

    // Touch Bar 黑条
    let bar = NSBezierPath(roundedRect: NSRect(x: 212, y: 175, width: 600, height: 165), xRadius: 48, yRadius: 48)
    barBlack.setFill()
    bar.fill()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    bar.lineWidth = 4
    bar.stroke()

    // 三个按键：高亮选项键 / 允许 / 拒绝
    let keyRects = [
        NSRect(x: 237, y: 200, width: 176, height: 115),
        NSRect(x: 435, y: 200, width: 176, height: 115),
        NSRect(x: 633, y: 200, width: 176, height: 115),
    ]
    NSGradient(starting: keyBlueTop, ending: keyBlueBottom)?.draw(in: NSBezierPath(roundedRect: keyRects[0], xRadius: 28, yRadius: 28), angle: -90)
    keyGray.setFill()
    NSBezierPath(roundedRect: keyRects[1], xRadius: 28, yRadius: 28).fill()
    NSBezierPath(roundedRect: keyRects[2], xRadius: 28, yRadius: 28).fill()

    // 键1 上的小 “?”
    let smallAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 78, weight: .bold), .foregroundColor: NSColor.white]
    let small = NSAttributedString(string: "?", attributes: smallAttrs)
    let sSize = small.size()
    small.draw(at: NSPoint(x: keyRects[0].midX - sSize.width / 2, y: keyRects[0].midY - sSize.height / 2 - 2))

    // 键2 绿色对勾
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 480, y: 260))
    check.line(to: NSPoint(x: 512, y: 228))
    check.line(to: NSPoint(x: 566, y: 288))
    keyGreen.setStroke()
    check.lineWidth = 17
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()

    // 键3 红色叉
    let cross = NSBezierPath()
    cross.move(to: NSPoint(x: 692, y: 230))
    cross.line(to: NSPoint(x: 752, y: 288))
    cross.move(to: NSPoint(x: 752, y: 230))
    cross.line(to: NSPoint(x: 692, y: 288))
    keyRed.setStroke()
    cross.lineWidth = 17
    cross.lineCapStyle = .round
    cross.stroke()
}

// ── 渲染 master 并导出各尺寸 ────────────────────────────────────────────────
let masterRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: masterRep)
NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)
drawIcon(in: NSGraphicsContext.current!.cgContext)
NSGraphicsContext.restoreGraphicsState()

let masterCG = masterRep.cgImage!

func writePNG(_ cg: CGImage, width: Int, height: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    NSImage(cgImage: masterCG, size: NSSize(width: S, height: S))
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let name: String
    switch s {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_16x16@2x.png"
    case 64: name = "icon_32x32@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_128x128@2x.png"
    case 512: name = "icon_256x256@2x.png"
    default: name = "icon_512x512@2x.png"
    }
    writePNG(masterCG, width: s, height: s, to: iconsetDir + "/" + name)
}
// 512 独立尺寸（iconset 规范要求 icon_512x512.png）
writePNG(masterCG, width: 512, height: 512, to: iconsetDir + "/icon_512x512.png")
// 仓库预览图
writePNG(masterCG, width: 1024, height: 1024, to: previewPath)
print("iconset → \(iconsetDir), preview → \(previewPath)")
