// 生成 zcode-touchbar 应用图标 —— 奶油底 + 圆滚滚的猫咪提问气泡 + 珊瑚色 "?" 徽章
// 用法: make-icon <iconset输出目录> <预览png路径>
// 之后用 `iconutil -c icns <iconset目录> -o AppIcon.icns` 打包。
import AppKit

let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let previewPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon.png"

// ── 调色板(奶油色系)──────────────────────────────────────────────────────
let bgTop = NSColor(srgbRed: 1.00, green: 0.968, blue: 0.933, alpha: 1)      // #FFF7EE
let bgBottom = NSColor(srgbRed: 1.00, green: 0.902, blue: 0.812, alpha: 1)   // #FFE6CF
let cream = NSColor.white
let ink = NSColor(srgbRed: 0.353, green: 0.275, blue: 0.220, alpha: 1)       // #5A4638 暖棕
let blush = NSColor(srgbRed: 1.00, green: 0.690, blue: 0.749, alpha: 0.75)   // #FFB0BF 腮红
let badgeTop = NSColor(srgbRed: 1.00, green: 0.706, blue: 0.478, alpha: 1)   // #FFB47A
let badgeBottom = NSColor(srgbRed: 1.00, green: 0.529, blue: 0.341, alpha: 1)// #FF8757
let softShadow = NSColor(srgbRed: 0.878, green: 0.659, blue: 0.463, alpha: 0.35)

let S: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS squircle 背景
    let squircle = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    bgBottom.setFill()
    squircle.fill()
    NSGradient(starting: bgTop, ending: bgBottom)?.draw(in: squircle, angle: -90)

    // 猫耳朵(先画,同色描边把尖端圆角化,底部会被气泡身体盖住)
    let ears = NSBezierPath()
    ears.move(to: NSPoint(x: 312, y: 690)); ears.line(to: NSPoint(x: 330, y: 846)); ears.line(to: NSPoint(x: 428, y: 702)); ears.close()
    ears.move(to: NSPoint(x: 672, y: 690)); ears.line(to: NSPoint(x: 654, y: 846)); ears.line(to: NSPoint(x: 556, y: 702)); ears.close()
    cream.setFill()
    ears.fill()
    cream.setStroke()
    ears.lineWidth = 22
    ears.lineJoinStyle = .round
    ears.stroke()

    // 圆滚滚的气泡身体 + 左下垂尾巴
    let body = NSBezierPath(roundedRect: NSRect(x: 212, y: 262, width: 560, height: 470), xRadius: 200, yRadius: 200)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 330, y: 276)); tail.line(to: NSPoint(x: 298, y: 178)); tail.line(to: NSPoint(x: 452, y: 276)); tail.close()
    body.append(tail)
    ctx.saveGState()
    ctx.setShadow(offset: NSSize(width: 0, height: -16), blur: 34, color: softShadow.cgColor)
    cream.setFill()
    body.fill()
    ctx.restoreGState()

    // 脸:眼睛 / ω 猫嘴 / 腮红
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: 355, y: 475, width: 46, height: 60)).fill()
    NSBezierPath(ovalIn: NSRect(x: 583, y: 475, width: 46, height: 60)).fill()
    blush.setFill()
    NSBezierPath(ovalIn: NSRect(x: 267, y: 429, width: 66, height: 38)).fill()
    NSBezierPath(ovalIn: NSRect(x: 651, y: 429, width: 66, height: 38)).fill()
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: 450, y: 474))
    mouth.appendArc(withCenter: NSPoint(x: 470, y: 474), radius: 20, startAngle: 180, endAngle: 360, clockwise: false)
    mouth.appendArc(withCenter: NSPoint(x: 514, y: 474), radius: 20, startAngle: 180, endAngle: 360, clockwise: false)
    ink.setStroke()
    mouth.lineWidth = 13
    mouth.lineCapStyle = .round
    mouth.stroke()

    // 珊瑚色 "?" 徽章(小尾巴指向猫咪)
    let badge = NSBezierPath(roundedRect: NSRect(x: 640, y: 646, width: 170, height: 170), xRadius: 56, yRadius: 56)
    let badgeTail = NSBezierPath()
    badgeTail.move(to: NSPoint(x: 660, y: 662)); badgeTail.line(to: NSPoint(x: 616, y: 610)); badgeTail.line(to: NSPoint(x: 706, y: 656)); badgeTail.close()
    badge.append(badgeTail)
    ctx.saveGState()
    ctx.setShadow(offset: NSSize(width: 0, height: -10), blur: 22, color: softShadow.cgColor)
    NSGradient(starting: badgeTop, ending: badgeBottom)?.draw(in: badge, angle: -90)
    ctx.restoreGState()
    let q = NSAttributedString(string: "?", attributes: [
        .font: NSFont.systemFont(ofSize: 118, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    let qSize = q.size()
    q.draw(at: NSPoint(x: 725 - qSize.width / 2, y: 731 - qSize.height / 2 - 4))
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

func writePNG(width: Int, height: Int, to path: String) {
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
let names: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"), (512, "icon_256x256@2x.png"),
    (1024, "icon_512x512@2x.png"),
]
for (size, name) in names {
    writePNG(width: size, height: size, to: iconsetDir + "/" + name)
}
writePNG(width: 512, height: 512, to: iconsetDir + "/icon_512x512.png")
writePNG(width: 1024, height: 1024, to: previewPath)
print("iconset → \(iconsetDir), preview → \(previewPath)")
