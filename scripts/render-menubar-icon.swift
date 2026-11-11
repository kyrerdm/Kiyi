import AppKit

// A monochrome vector version of Kıyı's notch and shoreline, sized for the menu bar.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = root.appendingPathComponent("App/boringNotch/Assets.xcassets/KiyiMenuBar.imageset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let data = NSMutableData()
let consumer = CGDataConsumer(data: data)!
var box = CGRect(x: 0, y: 0, width: 18, height: 18)
let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
context.beginPDFPage(nil)
context.setStrokeColor(NSColor.black.cgColor)
context.setLineWidth(1.35)
context.setLineCap(.round)
context.addPath(CGPath(roundedRect: CGRect(x: 3, y: 10, width: 12, height: 5.5),
                       cornerWidth: 2.75, cornerHeight: 2.75, transform: nil))
context.strokePath()
context.move(to: CGPoint(x: 2, y: 5.2))
context.addCurve(to: CGPoint(x: 9, y: 5.2), control1: CGPoint(x: 4.3, y: 3), control2: CGPoint(x: 6.3, y: 3))
context.addCurve(to: CGPoint(x: 16, y: 5.2), control1: CGPoint(x: 11.7, y: 7.4), control2: CGPoint(x: 13.7, y: 7.4))
context.strokePath()
context.endPDFPage()
context.closePDF()
try (data as Data).write(to: directory.appendingPathComponent("kiyi-menubar.pdf"))
