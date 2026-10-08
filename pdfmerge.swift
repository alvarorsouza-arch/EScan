// pdfmerge.swift - junta PDFs em ordem. Uso: pdfmerge saida.pdf a.pdf b.pdf ...
import Foundation
import PDFKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    FileHandle.standardError.write("uso: pdfmerge saida.pdf in1.pdf in2.pdf ...\n".data(using: .utf8)!)
    exit(2)
}
let out = args[0]
let base = PDFDocument()
var n = 0
for path in args.dropFirst() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
        FileHandle.standardError.write("falha abrindo \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    for i in 0..<doc.pageCount {
        if let p = doc.page(at: i) { base.insert(p, at: n); n += 1 }
    }
}
guard n > 0, base.write(to: URL(fileURLWithPath: out)) else {
    FileHandle.standardError.write("falha escrevendo \(out)\n".data(using: .utf8)!)
    exit(1)
}
print("ok \(n) paginas")
