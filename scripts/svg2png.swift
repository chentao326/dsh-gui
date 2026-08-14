// Render an SVG file into a PNG at the given pixel size using AppKit.
// Usage: svg2png <input.svg> <output.png> <size>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[3]) else {
    print("usage: svg2png <in.svg> <out.png> <size>")
    exit(1)
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    print("failed to load SVG: \(args[1])")
    exit(1)
}
let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
guard let data = out.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
