import Cocoa
import AVFoundation
import CoreImage

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var catWindow: CatWindow!
    var settingsWindow: SettingsPanel?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if UserDefaults.standard.object(forKey: "soundOnSet") == nil {
            UserDefaults.standard.set(true,  forKey: "soundOn")
            UserDefaults.standard.set(100.0, forKey: "volume")   // default 100%
            UserDefaults.standard.set(true,  forKey: "soundOnSet")
        }

        // Cmd+Q in the main menu
        let mainMenu = NSMenu()
        let appMenu  = NSMenu()
        let appItem  = NSMenuItem(); appItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit VibeKitty", action: #selector(quit),
                                   keyEquivalent: "q"))
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            btn.title = "🐱"; btn.action = #selector(statusClicked); btn.target = self
        }

        catWindow = CatWindow()
        catWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func statusClicked() {
        let menu  = NSMenu()
        let onTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        let sound = UserDefaults.standard.bool(forKey: "soundOn")
        addItem(menu, (onTop  ? "✓ " : "") + "Always on Top", #selector(toggleTop))
        addItem(menu, (sound  ? "✓ " : "") + "Sound On",      #selector(toggleSound))
        menu.addItem(.separator())
        addItem(menu, "Settings…",      #selector(openSettings))
        menu.addItem(.separator())
        addItem(menu, "Quit VibeKitty", #selector(quit))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func addItem(_ m: NSMenu, _ t: String, _ s: Selector) {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: ""); i.target = self; m.addItem(i)
    }

    @objc func toggleTop() {
        let v = !UserDefaults.standard.bool(forKey: "alwaysOnTop")
        UserDefaults.standard.set(v, forKey: "alwaysOnTop")
        catWindow.applyAlwaysOnTop(v)
    }
    @objc func toggleSound() {
        let v = !UserDefaults.standard.bool(forKey: "soundOn")
        UserDefaults.standard.set(v, forKey: "soundOn")
        catWindow.applySound(v)
    }
    @objc func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsPanel() }
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Cat Window  (borderless, transparent background)
class CatWindow: NSWindow {
    var videoView: CatVideoView!

    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 300, width: 420, height: 320),
            // .borderless removes title bar; keep .resizable so user can drag edges
            styleMask: [.borderless, .resizable],
            backing: .buffered, defer: false)

        // Transparent window — content shows through wherever alpha = 0
        backgroundColor  = .clear
        isOpaque         = false
        hasShadow        = false          // no shadow on transparent window
        isMovableByWindowBackground = true
        minSize = NSSize(width: 120, height: 90)

        // Allow the window to sit above everything when "always on top" is on
        applyAlwaysOnTop(UserDefaults.standard.bool(forKey: "alwaysOnTop"))

        videoView = CatVideoView(frame: contentView!.bounds)
        videoView.autoresizingMask = [.width, .height]
        contentView?.addSubview(videoView)

        let url = Bundle.main.url(forResource: "cat", withExtension: "mp4")
            ?? URL(fileURLWithPath: Bundle.main.bundlePath + "/Contents/Resources/cat.mp4")

        if FileManager.default.fileExists(atPath: url.path) {
            videoView.loadVideo(url: url)
        } else {
            Swift.print("❌ Video not found: \(url.path)")
        }
    }

    // Borderless windows normally don't become key — override so we can receive Cmd+Q
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    func applyAlwaysOnTop(_ on: Bool) { level = on ? .floating : .normal }
    func applySound(_ on: Bool)       { videoView.setSound(on) }
    func applyVolume(_ v: Float)      { videoView.setVolume(v) }
}

// MARK: - CatVideoView
class CatVideoView: NSView {

    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var latestPixelBuffer: CVPixelBuffer?
    private var ciContext: CIContext!
    private var cubeFilter: CIFilter!

    override init(frame: NSRect) {
        super.init(frame: frame)
        ciContext = CIContext(options: [.useSoftwareRenderer: false])
        buildCube()
    }
    required init?(coder: NSCoder) { fatalError() }

    // Transparent background — essential for see-through window
    override var isOpaque: Bool { false }

    func loadVideo(url: URL) {
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output!)

        player = AVPlayer(playerItem: item)
        let vol = UserDefaults.standard.float(forKey: "volume") / 100.0
        player!.volume = UserDefaults.standard.bool(forKey: "soundOn") ? vol : 0.0
        player!.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero) { _ in self?.player?.play() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let t = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            self?.timer = t
        }
    }

    func setSound(_ on: Bool) {
        let vol = UserDefaults.standard.float(forKey: "volume") / 100.0
        player?.volume = on ? vol : 0.0
    }
    func setVolume(_ pct: Float) {
        UserDefaults.standard.set(pct, forKey: "volume")
        if UserDefaults.standard.bool(forKey: "soundOn") {
            player?.volume = pct / 100.0
        }
    }

    private func tick() {
        guard let out = output, let item = player?.currentItem else { return }
        let t = item.currentTime()
        guard t.isValid else { return }
        var displayTime = CMTime.zero
        if let pb = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: &displayTime) {
            latestPixelBuffer = pb
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Clear to fully transparent — lets the window background show through
        NSColor.clear.setFill()
        bounds.fill()

        guard let pb = latestPixelBuffer else { return }

        // Orientation is correct in the source video — just draw it right.
        // NSImage.draw(in:) flips by default in a non-flipped NSView.
        // Using the full draw method with respectFlipped:true fixes this.
        let raw = CIImage(cvPixelBuffer: pb)
        cubeFilter.setValue(raw, forKey: kCIInputImageKey)
        let keyed = cubeFilter.outputImage ?? raw

        let iw = keyed.extent.width, ih = keyed.extent.height
        guard iw > 0, ih > 0 else { return }
        guard let rendered = ciContext.createCGImage(keyed, from: keyed.extent) else { return }

        let scale = min(bounds.width / iw, bounds.height / ih)
        let dw = iw * scale, dh = ih * scale
        let dest = CGRect(x: (bounds.width - dw) / 2, y: (bounds.height - dh) / 2,
                          width: dw, height: dh)

        let nsImg = NSImage(cgImage: rendered, size: NSSize(width: iw, height: ih))
        // respectFlipped:true tells NSImage to honour the view's coordinate system
        // (NSView is NOT flipped by default, so this draws top→down correctly)
        nsImg.draw(in: dest,
                   from: NSRect(x: 0, y: 0, width: iw, height: ih),
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: nil)
    }

    // MARK: Chroma cube — green → transparent
    private func buildCube() {
        let N = 64
        var buf = [Float](repeating: 0, count: N * N * N * 4)
        var idx = 0
        for b in 0..<N {
            for g in 0..<N {
                for r in 0..<N {
                    let rf = Float(r) / Float(N-1)
                    let gf = Float(g) / Float(N-1)
                    let bf = Float(b) / Float(N-1)
                    let cmax = max(rf,gf,bf), cmin = min(rf,gf,bf), d = cmax - cmin
                    var hue: Float = 0
                    if d > 0.001 {
                        if cmax == gf      { hue = 2 + (bf - rf) / d }
                        else if cmax == rf { hue = (gf - bf) / d; if hue < 0 { hue += 6 } }
                        else               { hue = 4 + (rf - gf) / d }
                        hue /= 6
                    }
                    let sat = cmax > 0 ? d / cmax : Float(0)
                    var hd = abs(hue - 1.0/3.0)
                    if hd > 0.5 { hd = 1 - hd }
                    var alpha: Float = 1
                    if hd < 0.20 && sat > 0.30 && cmax > 0.10 {
                        alpha = (hd / 0.20) * (hd / 0.20)
                    }
                    buf[idx] = rf*alpha; buf[idx+1] = gf*alpha
                    buf[idx+2] = bf*alpha; buf[idx+3] = alpha
                    idx += 4
                }
            }
        }
        let data = Data(bytes: buf, count: buf.count * MemoryLayout<Float>.size)
        cubeFilter = CIFilter(name: "CIColorCube")!
        cubeFilter.setValue(N,    forKey: "inputCubeDimension")
        cubeFilter.setValue(data as AnyObject, forKey: "inputCubeData")
    }

    deinit { timer?.invalidate() }
}

// MARK: - Settings Panel
class SettingsPanel: NSWindowController {
    var topBox:    NSButton!
    var soundBox:  NSButton!
    var volSlider: NSSlider!
    var volLabel:  NSTextField!

    override init(window: NSWindow?) {
        let w = NSWindow(
            contentRect: NSRect(x:0,y:0,width:340,height:250),
            styleMask: [.titled,.closable], backing: .buffered, defer: false)
        w.title = "VibeKitty Settings"; w.center()
        super.init(window: w); buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let cv = window!.contentView!
        lbl(cv, "🐱  VibeKitty", x:20, y:205, sz:16, bold:true)

        // Always on Top
        topBox = chk(cv, "Always on Top",
                     note: "Float above all other windows",
                     x:20, y:162, key:"alwaysOnTop", sel:#selector(topChanged))

        // Sound On/Off
        soundBox = chk(cv, "Sound On",
                       note: "Toggle audio on/off",
                       x:20, y:115, key:"soundOn", sel:#selector(soundChanged))

        // Volume slider
        lbl(cv, "Volume", x:20, y:84, sz:13, bold:false)

        let curVol = UserDefaults.standard.float(forKey: "volume")
        volSlider = NSSlider(value: Double(curVol), minValue: 0, maxValue: 100,
                             target: self, action: #selector(volChanged))
        volSlider.frame = NSRect(x:20, y:62, width:240, height:22)
        volSlider.isContinuous = true
        cv.addSubview(volSlider)

        volLabel = NSTextField(labelWithString: "\(Int(curVol))%")
        volLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volLabel.frame = NSRect(x:268, y:63, width:50, height:18)
        cv.addSubview(volLabel)

        // Done button
        let done = NSButton(title:"Done", target:self, action:#selector(close))
        done.bezelStyle = .rounded
        done.frame = NSRect(x:250,y:14,width:72,height:28)
        done.keyEquivalent = "\r"
        cv.addSubview(done)
    }

    @discardableResult
    private func lbl(_ v:NSView,_ s:String,x:CGFloat,y:CGFloat,
                     sz:CGFloat=12,bold:Bool=false) -> NSTextField {
        let f = NSTextField(labelWithString:s)
        f.font = bold ? .systemFont(ofSize:sz,weight:.semibold) : .systemFont(ofSize:sz)
        f.frame = NSRect(x:x,y:y,width:290,height:sz+6)
        v.addSubview(f); return f
    }

    @discardableResult
    private func chk(_ v:NSView,_ title:String,note:String,x:CGFloat,y:CGFloat,
                     key:String,sel:Selector) -> NSButton {
        let cb = NSButton(checkboxWithTitle:title,target:self,action:sel)
        cb.frame = NSRect(x:x,y:y+20,width:290,height:22)
        cb.state = UserDefaults.standard.bool(forKey:key) ? .on : .off
        v.addSubview(cb)
        lbl(v,note,x:x+18,y:y,sz:11).textColor = .secondaryLabelColor
        return cb
    }

    @objc func topChanged() {
        let on = topBox.state == .on
        UserDefaults.standard.set(on, forKey:"alwaysOnTop")
        (NSApp.delegate as? AppDelegate)?.catWindow.applyAlwaysOnTop(on)
    }
    @objc func soundChanged() {
        let on = soundBox.state == .on
        UserDefaults.standard.set(on, forKey:"soundOn")
        (NSApp.delegate as? AppDelegate)?.catWindow.applySound(on)
    }
    @objc func volChanged() {
        let v = Float(volSlider.floatValue)
        volLabel.stringValue = "\(Int(v))%"
        (NSApp.delegate as? AppDelegate)?.catWindow.applyVolume(v)
    }
    @objc override func close() { window?.close() }
}
