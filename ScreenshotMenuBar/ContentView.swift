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

struct ContentView: View {
    @StateObject private var manager = ScreenshotManager()
    @State private var floatingWindow: NSWindow?
    
    var body: some View {
        VStack(spacing: 16) {
            if let screenshot = manager.screenshot {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
}

struct FloatingWindowView: View {
    let image: NSImage
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(10)
    }
}
