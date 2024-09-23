import Cocoa
import Vision
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var eventHotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBarItem()
        registerGlobalHotKey()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let eventHotKey = eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }
    }

    func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Capture")
            button.imagePosition = .imageLeft
            
            let menu = NSMenu()
            let captureMenuItem = NSMenuItem(title: "Capture", action: #selector(captureScreenshot), keyEquivalent: "m")
            captureMenuItem.keyEquivalentModifierMask = [.control, .command]
            menu.addItem(captureMenuItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusItem.menu = menu
        }
    }

    func registerGlobalHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("JPOC".utf8.reduce(0) { ($0 << 8) + OSType($1) })
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Install event handler
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            let appDelegate = unsafeBitCast(userData, to: AppDelegate.self)
            appDelegate.captureScreenshot()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // Register hotkey (Control + Command + M)
        let hotKeyError = RegisterEventHotKey(UInt32(kVK_ANSI_M), 
                                              UInt32(controlKey | cmdKey), 
                                              hotKeyID, 
                                              GetApplicationEventTarget(), 
                                              0, 
                                              &eventHotKey)
        
        if hotKeyError != noErr {
            print("Failed to register hotkey")
        }
    }

    @objc func captureScreenshot() {
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-c", "-x"]

        task.launch()
        task.waitUntilExit()

        if let imageData = NSPasteboard.general.data(forType: .tiff),
           let image = NSImage(data: imageData) {
            print("Screenshot captured. Image size: \(image.size)")
            performOCROnCapturedImage()
        } else {
            print("Failed to capture screenshot")
        }
    }

    func performOCROnCapturedImage() {
        if let imageData = NSPasteboard.general.data(forType: .tiff),
           let image = NSImage(data: imageData),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            performOCR(on: cgImage)
        } else {
            print("Failed to process the captured image")
        }
    }

    func performOCR(on cgImage: CGImage) {
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
            if !recognizedText.isEmpty {
                print("Recognized text:\n\(recognizedText)")
                self.copyToClipboard(recognizedText)
            } else {
                print("No text recognized")
            }
        }
        
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform OCR: \(error)")
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("Text copied to clipboard")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()