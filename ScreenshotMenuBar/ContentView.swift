import SwiftUI
import AppKit

class ScreenshotManager: ObservableObject {
    @Published var screenshot: NSImage? {
        didSet {
            saveScreenshot()
        }
    }
    
    init() {
        loadScreenshot()
    }
    
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            screenshot = resizeImage(image: image, maxDimension: 800)
        }
    }
    
    private func saveScreenshot() {
        guard let screenshot = screenshot,
              let tiffData = screenshot.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            UserDefaults.standard.removeObject(forKey: "savedScreenshot")
            return
        }
        
        UserDefaults.standard.set(pngData, forKey: "savedScreenshot")
    }
    
    private func loadScreenshot() {
        guard let data = UserDefaults.standard.data(forKey: "savedScreenshot"),
              let image = NSImage(data: data) else {
            return
        }
        
        screenshot = image
    }
    
    private func resizeImage(image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let maxSize = max(size.width, size.height)
        
        if maxSize <= maxDimension {
            return image
        }
        
        let scale = maxDimension / maxSize
        let newWidth = size.width * scale
        let newHeight = size.height * scale
        
        let newImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        newImage.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight))
        newImage.unlockFocus()
        
        return newImage
    }
}

// MARK: - Interactive Image View with Color Picker

class InteractiveImageNSView: NSView {
    var image: NSImage?
    var onColorHover: ((String?) -> Void)?
    var onColorClick: ((String) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var currentMouseLocation: NSPoint?
    private var bitmapCache: NSBitmapImageRep?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        setupTrackingArea()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let image = image else { return }

        let imageRect = getImageRect()
        image.draw(in: imageRect)

        // Draw magnifier loupe if mouse is over the view
        if let mouseLocation = currentMouseLocation, imageRect.contains(mouseLocation) {
            drawMagnifier(at: mouseLocation, imageRect: imageRect)
        }
    }

    private func getImageRect() -> NSRect {
        guard let image = image else { return bounds }

        let imageSize = image.size
        let viewSize = bounds.size

        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var drawRect: NSRect

        if imageAspect > viewAspect {
            // Image is wider
            let height = viewSize.width / imageAspect
            let y = (viewSize.height - height) / 2
            drawRect = NSRect(x: 0, y: y, width: viewSize.width, height: height)
        } else {
            // Image is taller or equal
            let width = viewSize.height * imageAspect
            let x = (viewSize.width - width) / 2
            drawRect = NSRect(x: x, y: 0, width: width, height: viewSize.height)
        }

        return drawRect
    }

    private func getBitmap() -> NSBitmapImageRep? {
        if let cached = bitmapCache {
            return cached
        }

        guard let image = image,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        bitmapCache = bitmap
        return bitmap
    }

    private func getPixelColor(at point: NSPoint) -> (color: NSColor, imageX: Int, imageY: Int)? {
        guard let image = image else { return nil }

        let imageRect = getImageRect()

        // Check if point is inside image bounds
        guard imageRect.contains(point) else { return nil }

        // Convert view coordinates to image coordinates
        let relativeX = (point.x - imageRect.origin.x) / imageRect.width
        let relativeY = (point.y - imageRect.origin.y) / imageRect.height

        let imageX = Int(relativeX * image.size.width)
        let imageY = Int((1 - relativeY) * image.size.height) // Flip Y coordinate

        // Get pixel data
        guard let bitmap = getBitmap(),
              imageX >= 0, imageX < Int(image.size.width),
              imageY >= 0, imageY < Int(image.size.height),
              let color = bitmap.colorAt(x: imageX, y: imageY) else {
            return nil
        }

        return (color, imageX, imageY)
    }

    private func drawMagnifier(at point: NSPoint, imageRect: NSRect) {
        guard let image = image,
              let bitmap = getBitmap(),
              let pixelInfo = getPixelColor(at: point) else { return }

        let loupeSize: CGFloat = 120
        let loupeRadius = loupeSize / 2
        let magnification: CGFloat = 8
        let pixelSize = loupeSize / 11 // Show 11x11 grid

        // Position loupe above and to the right of cursor
        var loupeX = point.x + 20
        var loupeY = point.y + 20

        // Keep loupe within bounds
        if loupeX + loupeSize > bounds.width {
            loupeX = point.x - loupeSize - 20
        }
        if loupeY + loupeSize + 80 > bounds.height {
            loupeY = point.y - loupeSize - 20
        }

        let loupeRect = NSRect(x: loupeX, y: loupeY, width: loupeSize, height: loupeSize)

        // Draw loupe background and border
        let loupePath = NSBezierPath(ovalIn: loupeRect)
        NSColor.white.setFill()
        loupePath.fill()

        // Clip to circle for magnified content
        loupePath.addClip()

        // Calculate the region to magnify (5 pixels around cursor in image space)
        let centerImageX = pixelInfo.imageX
        let centerImageY = pixelInfo.imageY
        let gridSize = 5

        // Draw magnified pixels
        for dy in -gridSize...gridSize {
            for dx in -gridSize...gridSize {
                let sampleX = centerImageX + dx
                let sampleY = centerImageY + dy

                if sampleX >= 0 && sampleX < Int(image.size.width) &&
                   sampleY >= 0 && sampleY < Int(image.size.height),
                   let pixelColor = bitmap.colorAt(x: sampleX, y: sampleY) {

                    pixelColor.setFill()

                    let pixelX = loupeX + loupeRadius + CGFloat(dx) * pixelSize - pixelSize / 2
                    let pixelY = loupeY + loupeRadius + CGFloat(dy) * pixelSize - pixelSize / 2

                    let pixelRect = NSRect(x: pixelX, y: pixelY, width: pixelSize, height: pixelSize)
                    NSBezierPath(rect: pixelRect).fill()
                }
            }
        }

        // Draw crosshair in center
        NSGraphicsContext.saveGraphicsState()
        loupePath.setClip()

        NSColor.white.setStroke()
        let crosshairPath = NSBezierPath()
        crosshairPath.lineWidth = 1.5

        // Horizontal line
        crosshairPath.move(to: NSPoint(x: loupeX + loupeRadius - 15, y: loupeY + loupeRadius))
        crosshairPath.line(to: NSPoint(x: loupeX + loupeRadius + 15, y: loupeY + loupeRadius))

        // Vertical line
        crosshairPath.move(to: NSPoint(x: loupeX + loupeRadius, y: loupeY + loupeRadius - 15))
        crosshairPath.line(to: NSPoint(x: loupeX + loupeRadius, y: loupeY + loupeRadius + 15))

        crosshairPath.stroke()

        // Black outline for crosshair
        NSColor.black.setStroke()
        crosshairPath.lineWidth = 0.5
        crosshairPath.stroke()

        NSGraphicsContext.restoreGraphicsState()

        // Draw loupe border
        let borderPath = NSBezierPath(ovalIn: loupeRect)
        borderPath.lineWidth = 3
        NSColor.darkGray.setStroke()
        borderPath.stroke()

        // Draw color info below loupe
        let hexCode = colorToHex(pixelInfo.color)
        let infoY = loupeY - 35

        // Color swatch
        let swatchRect = NSRect(x: loupeX, y: infoY, width: 30, height: 30)
        pixelInfo.color.setFill()
        NSBezierPath(rect: swatchRect).fill()
        NSColor.white.setStroke()
        let swatchBorder = NSBezierPath(rect: swatchRect)
        swatchBorder.lineWidth = 2
        swatchBorder.stroke()

        // Hex code text
        let textRect = NSRect(x: loupeX + 35, y: infoY, width: 85, height: 30)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = NSSize(width: 0, height: 0)
        shadow.shadowBlurRadius = 3

        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]

        (hexCode as NSString).draw(in: textRect, withAttributes: shadowAttrs)
    }

    private func colorToHex(_ color: NSColor) -> String {
        guard let rgbColor = color.usingColorSpace(.sRGB) else { return "#000000" }

        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        currentMouseLocation = location

        if let pixelInfo = getPixelColor(at: location) {
            let hexCode = colorToHex(pixelInfo.color)
            onColorHover?(hexCode)
        } else {
            onColorHover?(nil)
        }

        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        currentMouseLocation = nil
        onColorHover?(nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if let pixelInfo = getPixelColor(at: location) {
            let hexCode = colorToHex(pixelInfo.color)
            onColorClick?(hexCode)
        }
    }
}

struct InteractiveImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var hoveredColor: String?
    var onColorClick: ((String) -> Void)?

    func makeNSView(context: Context) -> InteractiveImageNSView {
        let view = InteractiveImageNSView()
        view.image = image
        view.onColorHover = { color in
            hoveredColor = color
        }
        view.onColorClick = onColorClick
        return view
    }

    func updateNSView(_ nsView: InteractiveImageNSView, context: Context) {
        nsView.image = image
        nsView.onColorHover = { color in
            hoveredColor = color
        }
        nsView.onColorClick = onColorClick
        nsView.needsDisplay = true
    }
}

struct ContentView: View {
    @StateObject private var manager = ScreenshotManager()
    @State private var floatingWindow: NSWindow?
    @State private var hoveredColor: String?

    var body: some View {
        VStack(spacing: 16) {
            if let screenshot = manager.screenshot {
                InteractiveImageView(
                    image: screenshot,
                    hoveredColor: $hoveredColor,
                    onColorClick: { hexCode in
                        copyToClipboard(hexCode)
                    }
                )
                .frame(maxWidth: 380, maxHeight: 380)
                .border(Color.gray.opacity(0.3), width: 1)
                
                HStack(spacing: 12) {
                    Button("Paste New") {
                        manager.pasteFromClipboard()
                    }
                    
                    Button("Pop Out") {
                        showFloatingWindow()
                    }
                    
                    Button("Clear") {
                        manager.screenshot = nil
                        closeFloatingWindow()
                    }
                    .foregroundColor(.red)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No screenshot stored")
                        .foregroundColor(.secondary)
                    
                    Button("Paste from Clipboard") {
                        manager.pasteFromClipboard()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    func showFloatingWindow() {
        guard let screenshot = manager.screenshot else { return }
        
        // Close existing window if any
        closeFloatingWindow()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: screenshot.size.width + 20, height: screenshot.size.height + 20),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Screenshot"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        
        let hostingView = NSHostingView(rootView: FloatingWindowView(image: screenshot))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        
        floatingWindow = window
    }
    
    func closeFloatingWindow() {
        floatingWindow?.close()
        floatingWindow = nil
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct FloatingWindowView: View {
    let image: NSImage
    @State private var hoveredColor: String?

    var body: some View {
        InteractiveImageView(
            image: image,
            hoveredColor: $hoveredColor,
            onColorClick: { hexCode in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hexCode, forType: .string)
            }
        )
        .padding(10)
    }
}

// MARK: - NSColor Extension for Hex Support

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
