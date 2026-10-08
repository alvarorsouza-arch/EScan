// scanview.swift - vista do preview com selecao por arrasto.
// Toda a matematica de coordenadas mora aqui e e testavel via setDrag().
import AppKit

final class ScanView: NSView {
    var image: NSImage? { didSet { refreshPxSize(); needsDisplay = true } }
    var selection: CGRect?            // em pixels do preview (origem no topo esquerdo)
    private var dragStartView: CGPoint?
    private var fitted: CGRect = .zero
    private var scale: CGFloat = 1
    private var pxSize: NSSize = .zero
    var onSelection: ((CGRect?) -> Void)?

    var pixelSize: NSSize { pxSize }
    var fittedRect: CGRect { fitted }
    var viewScale: CGFloat { scale }

    // NSImage.size devolve PONTOS (pixels * 72/dpi). O preview da Epson tem dpi=100,
    // entao 850x1170 px aparecem como 612x842 pt. Toda a conta de selecao precisa
    // dos pixels reais do bitmap, senao a area sai 72/dpi vezes menor.
    private func refreshPxSize() {
        guard let img = image else { pxSize = .zero; return }
        for r in img.representations {
            if let b = r as? NSBitmapImageRep, b.pixelsWide > 0, b.pixelsHigh > 0 {
                pxSize = NSSize(width: b.pixelsWide, height: b.pixelsHigh); return
            }
        }
        pxSize = img.size
    }

    override var isFlipped: Bool { false }

    private func computeFitted() {
        refreshPxSize()
        guard pxSize.width > 0, pxSize.height > 0 else { fitted = .zero; scale = 1; return }
        let b = bounds
        scale = min(b.width / pxSize.width, b.height / pxSize.height)
        let w = pxSize.width * scale, h = pxSize.height * scale
        fitted = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }

    // coords da vista -> pixels do preview (origem no topo esquerdo)
    private func toImagePx(_ p: CGPoint) -> CGPoint {
        guard pxSize.width > 0, scale > 0 else { return .zero }
        let x = (p.x - fitted.minX) / scale
        let y = (fitted.maxY - p.y) / scale
        return CGPoint(x: min(max(x, 0), pxSize.width), y: min(max(y, 0), pxSize.height))
    }

    // pixels do preview -> coords da vista
    private func toView(_ r: CGRect) -> CGRect {
        guard fitted.width > 0 else { return .zero }
        return CGRect(x: fitted.minX + r.minX * scale,
                      y: fitted.maxY - r.maxY * scale,
                      width: r.width * scale, height: r.height * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        computeFitted()
        guard let img = image else {
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            let a = NSAttributedString(string: "sem preview\nclique em Preview",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                             .font: NSFont.systemFont(ofSize: 14), .paragraphStyle: ps])
            a.draw(in: CGRect(x: 0, y: bounds.midY - 30, width: bounds.width, height: 60))
            return
        }
        img.draw(in: fitted)
        NSColor.gridColor.setStroke()
        NSBezierPath(rect: fitted).stroke()

        guard let sel = selection else { return }
        let v = toView(sel)
        NSColor.black.withAlphaComponent(0.35).setFill()
        let full = NSBezierPath(rect: fitted)
        full.appendRect(v)
        full.windingRule = .evenOdd
        full.fill()
        NSColor.systemRed.setStroke()
        let border = NSBezierPath(rect: v); border.lineWidth = 2; border.stroke()
    }

    // nucleo da selecao: dois pontos em coords da vista -> retangulo em px do preview.
    // mouseUp e os testes passam por aqui, entao o que o teste valida e o que o clique faz.
    @discardableResult
    func setDrag(from a: CGPoint, to b: CGPoint) -> CGRect? {
        computeFitted()
        let p1 = toImagePx(a), p2 = toImagePx(b)
        let r = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                       width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
        selection = (r.width < 8 || r.height < 8) ? nil : r
        needsDisplay = true
        onSelection?(selection)
        return selection
    }

    override func mouseDown(with e: NSEvent) {
        computeFitted()
        dragStartView = convert(e.locationInWindow, from: nil)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = dragStartView else { return }
        _ = setDrag(from: s, to: convert(e.locationInWindow, from: nil))
    }

    override func mouseUp(with e: NSEvent) {
        guard let s = dragStartView else { return }
        _ = setDrag(from: s, to: convert(e.locationInWindow, from: nil))
        dragStartView = nil
    }

    func clearSelection() { selection = nil; needsDisplay = true; onSelection?(nil) }
}
