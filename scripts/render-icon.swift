import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!; NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: Double(size)/1024, y: Double(size)/1024)
    NSColor(calibratedRed: 0.063, green: 0.09, blue: 0.098, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64,y: 64,width: 896,height: 896), xRadius: 200,yRadius: 200).fill()
    NSColor(calibratedRed: 0.008, green: 0.027, blue: 0.031, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 300,y: 540,width: 424,height: 180), xRadius: 78,yRadius: 78).fill()
    let accent = NSColor(calibratedRed: 0.333, green: 0.859, blue: 0.773, alpha: 1)
    accent.setFill(); NSBezierPath(ovalIn: NSRect(x: 340,y: 608,width: 44,height: 44)).fill()
    NSColor(calibratedRed: 0.89, green: 0.98, blue: 0.96, alpha: 1).setStroke()
    for (x,y,h): (CGFloat,CGFloat,CGFloat) in [(608,616,28),(632,604,52),(656,620,16)] {
        let p = NSBezierPath(); p.lineWidth = 12; p.lineCapStyle = .round; p.move(to: CGPoint(x:x,y:y)); p.line(to: CGPoint(x:x,y:y+h)); p.stroke()
    }
    accent.setStroke(); let wave = NSBezierPath(); wave.lineWidth = 36; wave.lineCapStyle = .round
    wave.move(to: CGPoint(x:240,y:342)); wave.curve(to: CGPoint(x:512,y:342), controlPoint1: CGPoint(x:331,y:272), controlPoint2: CGPoint(x:395,y:272)); wave.curve(to: CGPoint(x:784,y:342), controlPoint1: CGPoint(x:629,y:412), controlPoint2: CGPoint(x:693,y:412)); wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
let assets = root.appendingPathComponent("App/boringNotch/Assets.xcassets")
let icons = assets.appendingPathComponent("AppIcon.appiconset")
let info = try JSONSerialization.jsonObject(with: Data(contentsOf: icons.appendingPathComponent("Contents.json"))) as! [String: Any]
for image in info["images"] as! [[String:String]] {
    let base = Int(image["size"]!.split(separator:"x")[0])!; let scale = image["scale"] == "2x" ? 2 : 1
    try render(base*scale).write(to: icons.appendingPathComponent(image["filename"]!))
}
let logo = assets.appendingPathComponent("logo2.imageset")
let logoInfo = try JSONSerialization.jsonObject(with: Data(contentsOf: logo.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in logoInfo["images"] as! [[String:String]] { if let file = entry["filename"] { try render(1024).write(to: logo.appendingPathComponent(file)) } }
try render(512).write(to: root.appendingPathComponent("Assets/kiyi-icon.png"))
