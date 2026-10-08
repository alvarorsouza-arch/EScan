// main.swift - interface grafica para escanear via eSCL (AirScan). macOS, AppKit, sem dependencias.
// Preview rapido -> seleciona a area arrastando -> escolhe dpi/cor/formato -> scan final.
// A matematica de coordenadas esta em scanview.swift.
import AppKit

// O script `scan` fica ao lado deste binario (mesmo diretorio) ou em ~/.local/bin/scan.
let SCAN: String = {
    let fm = FileManager.default
    if let exe = Bundle.main.executablePath {
        let candidate = (exe as NSString).deletingLastPathComponent + "/scan"
        if fm.isExecutableFile(atPath: candidate) { return candidate }
    }
    let here = #filePath as NSString
    let candidate = here.deletingLastPathComponent + "/scan"
    if fm.isExecutableFile(atPath: candidate) { return candidate }
    let home = fm.homeDirectoryForCurrentUser.path
    let fallback = home + "/.local/bin/scan"
    if fm.isExecutableFile(atPath: fallback) { return fallback }
    return "scan"
}()

let PREVIEW_DPI = 100
// 1 pixel do preview (100 dpi) = 3 unidades eSCL (1/300 pol)
let UNITS_PER_PREVIEW_PX = 300.0 / Double(PREVIEW_DPI)

func runScan(_ args: String) -> (String, String?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-c", "\(SCAN) \(args) 2>&1"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return ("", "erro lancando scan: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let out = String(data: data, encoding: .utf8) ?? ""
    var path: String?
    for line in out.split(separator: "\n") {
        let s = String(line)
        if s.contains("salvo:") {
            for w in s.split(separator: " ") where w.hasPrefix("/") { path = String(w) }
        }
    }
    return (out, path)
}

// ---------------- app ----------------
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: ScanView!
    var dpiPop: NSPopUpButton!
    var colorPop: NSPopUpButton!
    var fmtPop: NSPopUpButton!
    var status: NSTextField!
    var regionLabel: NSTextField!
    var busy = false

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Escanear"
        window.center()

        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        view = ScanView(frame: NSRect(x: 16, y: 96, width: 600, height: 604))
        view.autoresizingMask = [.maxXMargin, .height]
        view.wantsLayer = true
        view.onSelection = { [weak self] s in self?.updateRegion(s) }
        content.addSubview(view)

        let panel = NSView(frame: NSRect(x: 632, y: 96, width: 292, height: 604))
        panel.autoresizingMask = [.minXMargin, .height]
        content.addSubview(panel)

        func label(_ s: String, _ y: CGFloat) -> NSTextField {
            let t = NSTextField(labelWithString: s); t.frame = NSRect(x: 0, y: y, width: 292, height: 18); panel.addSubview(t); return t
        }
        func full(_ b: NSButton, _ y: CGFloat, _ h: CGFloat = 30) { b.frame = NSRect(x: 0, y: y, width: 292, height: h); panel.addSubview(b) }

        label("1. Preview (100 dpi, ~9 s)", 576)
        full(NSButton(title: "Fazer preview do vidro", target: self, action: #selector(preview)), 542)

        label("2. Area a escanear", 500)
        regionLabel = label("vidro inteiro", 476)
        full(NSButton(title: "limpar selecao", target: self, action: #selector(clearSel)), 444, 24)

        label("3. Definicao final", 402)
        dpiPop = NSPopUpButton(frame: NSRect(x: 0, y: 370, width: 292, height: 26))
        dpiPop.addItems(withTitles: ["300 dpi  (documentos)", "600 dpi  (alta definicao)", "1200 dpi (maximo)", "200 dpi  (rapido)", "100 dpi  (so leitura)"])
        dpiPop.selectItem(at: 0)
        dpiPop.target = self
        dpiPop.action = #selector(settingsChanged)
        panel.addSubview(dpiPop)

        colorPop = NSPopUpButton(frame: NSRect(x: 0, y: 338, width: 292, height: 26))
        colorPop.addItems(withTitles: ["cinza (documentos)", "cor (fotos)", "preto e branco puro"])
        colorPop.selectItem(at: 0)
        colorPop.target = self
        colorPop.action = #selector(settingsChanged)
        panel.addSubview(colorPop)

        fmtPop = NSPopUpButton(frame: NSRect(x: 0, y: 306, width: 292, height: 26))
        fmtPop.addItems(withTitles: ["PDF", "JPEG"])
        fmtPop.selectItem(at: 0)
        fmtPop.target = self
        fmtPop.action = #selector(settingsChanged)
        panel.addSubview(fmtPop)

        full(NSButton(title: "ESCANEAR area selecionada", target: self, action: #selector(scanArea)), 262, 36)
        full(NSButton(title: "escanear vidro inteiro", target: self, action: #selector(scanFull)), 224, 28)

        status = NSTextField(wrappingLabelWithString: "pronto")
        status.frame = NSRect(x: 0, y: 40, width: 292, height: 150)
        status.textColor = .secondaryLabelColor
        status.font = NSFont.systemFont(ofSize: 11)
        panel.addSubview(status)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preview()
    }

    func selectedDpi() -> Int { [300, 600, 1200, 200, 100][dpiPop.indexOfSelectedItem] }

    func updateRegion(_ s: CGRect?) {
        guard let s = s else { regionLabel.stringValue = "vidro inteiro"; return }
        let uw = Int(s.width * UNITS_PER_PREVIEW_PX)
        let uh = Int(s.height * UNITS_PER_PREVIEW_PX)
        let dpi = selectedDpi()
        regionLabel.stringValue = String(format: "%.2f x %.2f pol  ->  %d x %d px a %d dpi",
                                         Double(uw) / 300.0, Double(uh) / 300.0,
                                         Int(Double(uw) / 300.0 * Double(dpi)),
                                         Int(Double(uh) / 300.0 * Double(dpi)), dpi)
    }

    @objc func settingsChanged() { updateRegion(view.selection) }

    func settings() -> String {
        let dpi = selectedDpi()
        let cor = ["gray", "rgb", "bw"][colorPop.indexOfSelectedItem]
        let fmt = fmtPop.indexOfSelectedItem == 0 ? "pdf" : "jpg"
        return "--dpi \(dpi) --cor \(cor) --fmt \(fmt) --no-open"
    }

    @objc func clearSel() { view.clearSelection() }

    @objc func preview() {
        guard !busy else { return }
        busy = true
        status.stringValue = "fazendo preview..."
        DispatchQueue.global().async {
            let (out, path) = runScan("preview --no-open")
            DispatchQueue.main.async {
                self.busy = false
                if let p = path, let img = NSImage(contentsOfFile: p) {
                    self.view.image = img
                    let px = self.view.pixelSize
                    self.status.stringValue = "preview pronto: \(Int(px.width)) x \(Int(px.height)) px = vidro inteiro a \(PREVIEW_DPI) dpi.\nArraste sobre a imagem para marcar a area."
                } else {
                    self.status.stringValue = out
                }
            }
        }
    }

    @objc func scanArea() {
        guard !busy else { return }
        var args: String
        if let s = view.selection, s.width > 8, s.height > 8 {
            let ux = Int(s.minX * UNITS_PER_PREVIEW_PX)
            let uy = Int(s.minY * UNITS_PER_PREVIEW_PX)
            let uw = max(Int(s.width * UNITS_PER_PREVIEW_PX), 60)
            let uh = max(Int(s.height * UNITS_PER_PREVIEW_PX), 60)
            args = "area \(ux) \(uy) \(uw) \(uh) \(settings())"
        } else {
            args = "doc \(settings())"
        }
        runFinal(args)
    }

    @objc func scanFull() { guard !busy else { return }; runFinal("doc \(settings())") }

    func runFinal(_ args: String) {
        busy = true
        status.stringValue = "escaneando..."
        DispatchQueue.global().async {
            let (out, path) = runScan(args)
            DispatchQueue.main.async {
                self.busy = false
                self.status.stringValue = out
                if let p = path { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
            }
        }
    }
}

// ---------------- modo selftest: valida a matematica da selecao sem clique humano ----------------
// Uso: escanear --selftest <preview.jpg>
func selftest(_ previewPath: String) -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 632, height: 620),
                       styleMask: [.titled], backing: .buffered, defer: false)
    let v = ScanView(frame: NSRect(x: 0, y: 0, width: 600, height: 604))
    win.contentView = v
    guard let img = NSImage(contentsOfFile: previewPath) else {
        print("selftest: nao consegui abrir \(previewPath)"); return 2
    }
    v.image = img
    v.display()
    let px = v.pixelSize
    print("preview px reais: \(Int(px.width)) x \(Int(px.height))  (NSImage.size dirá \(Int(img.size.width)) x \(Int(img.size.height)) pt)")
    v.setDrag(from: .zero, to: .zero)   // força computeFitted
    let f = v.fittedRect
    let sc = v.viewScale
    print("fitted: \(f)  scale: \(sc)")
    guard f.width > 0, sc > 0 else { print("selftest: fitted zerado"); return 1 }

    // ponto em coords da vista a (dxPx, dyPx) do canto sup. esquerdo do preview
    func vp(_ dxPx: CGFloat, _ dyPx: CGFloat) -> CGPoint {
        CGPoint(x: f.minX + dxPx * sc, y: f.maxY - dyPx * sc)
    }

    var falhas = 0
    func caso(_ nome: String, _ a: CGPoint, _ b: CGPoint, _ expW: Int, _ expH: Int) {
        guard let s = v.setDrag(from: a, to: b) else {
            print("FALHA \(nome): selecao nil"); falhas += 1; return
        }
        let ux = Int(s.minX * UNITS_PER_PREVIEW_PX), uy = Int(s.minY * UNITS_PER_PREVIEW_PX)
        let uw = Int(s.width * UNITS_PER_PREVIEW_PX), uh = Int(s.height * UNITS_PER_PREVIEW_PX)
        let ok = abs(uw - expW) <= 6 && abs(uh - expH) <= 6
        if !ok { falhas += 1 }
        print("\(ok ? "ok  " : "RUIM") \(nome): units \(ux),\(uy) \(uw)x\(uh)  esperado ~\(expW)x\(expH)  [\(String(format: "%.2f x %.2f", Double(uw)/300, Double(uh)/300)) pol]")
    }

    caso("vidro inteiro", vp(0, 0), vp(px.width, px.height), 2550, 3510)
    caso("caixa 540x720 px", vp(55, 148), vp(595, 868), 1620, 2160)
    caso("arrasto invertido", vp(595, 868), vp(55, 148), 1620, 2160)
    caso("quadrado 1 pol", vp(375, 535), vp(475, 635), 300, 300)
    caso("clamp fora dos limites", CGPoint(x: -200, y: f.maxY + 200), vp(px.width, px.height), 2550, 3510)

    print(falhas == 0 ? "SELFTEST: 5/5 ok" : "SELFTEST: \(falhas) falha(s)")
    return falhas == 0 ? 0 : 1
}

let cli = CommandLine.arguments
if cli.count >= 3 && cli[1] == "--selftest" {
    exit(selftest(cli[2]))
}

func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
runApp()
