import UIKit
import Social
import UniformTypeIdentifiers

/// Aparece no menu Compartilhar do iPhone como "About Inbox".
/// Recebe texto, link, áudio, foto, vídeo e PDF, guarda na fila do App Group e fecha.
class ShareViewController: SLComposeServiceViewController {

    private let roxo = UIColor(red: 0.545, green: 0.298, blue: 0.949, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About Inbox"
        placeholder = "Mensagem ou observação"
        navigationController?.navigationBar.tintColor = roxo
        view.tintColor = roxo
    }

    override func isContentValid() -> Bool { true }

    override func configurationItems() -> [Any]! { [] }

    override func didSelectPost() {
        let textoDigitado = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let itens = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let provedores = itens.flatMap { $0.attachments ?? [] }

        Task {
            var partes: [String] = []
            if !textoDigitado.isEmpty { partes.append(textoDigitado) }
            var anexos: [Anexo] = []

            for p in provedores {
                if let arquivo = await Self.copiarArquivo(p) {
                    anexos.append(arquivo)
                } else if let url = await Self.carregarURL(p) {
                    if !partes.joined(separator: "\n").contains(url) { partes.append(url) }
                } else if textoDigitado.isEmpty, let t = await Self.carregarTexto(p), !t.isEmpty {
                    partes.append(t)
                }
            }

            let item = ItemFila(texto: partes.joined(separator: "\n"), anexos: anexos)
            if let dados = try? JSON.encoder.encode(item) {
                try? dados.write(to: AppGroup.fila.appendingPathComponent(item.id + ".json"), options: .atomic)
            }
            await MainActor.run {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    // MARK: - Leitura dos anexos

    nonisolated private static func ehArquivo(_ t: UTType) -> Bool {
        if t.conforms(to: .plainText) || t.conforms(to: .url) || t.conforms(to: .text) { return false }
        return t.conforms(to: .audio) || t.conforms(to: .image) || t.conforms(to: .movie)
            || t.conforms(to: .pdf) || t.conforms(to: .data) || t.conforms(to: .content)
    }

    nonisolated static func copiarArquivo(_ p: NSItemProvider) async -> Anexo? {
        guard let tipo = p.registeredTypeIdentifiers.first(where: { id in
            guard let t = UTType(id) else { return false }
            return ehArquivo(t)
        }) else { return nil }

        return await withCheckedContinuation { (c: CheckedContinuation<Anexo?, Never>) in
            _ = p.loadFileRepresentation(forTypeIdentifier: tipo) { url, _ in
                guard let url else { c.resume(returning: nil); return }
                var ext = url.pathExtension
                if ext.isEmpty, let e = UTType(tipo)?.preferredFilenameExtension { ext = e }
                let nomeArquivo = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
                let destino = AppGroup.midia.appendingPathComponent(nomeArquivo)
                do {
                    try FileManager.default.copyItem(at: url, to: destino)
                    c.resume(returning: Anexo(nome: url.lastPathComponent, tipo: tipo, arquivo: nomeArquivo))
                } catch {
                    c.resume(returning: nil)
                }
            }
        }
    }

    nonisolated static func carregarURL(_ p: NSItemProvider) async -> String? {
        guard p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
              !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let u = item as? URL { c.resume(returning: u.absoluteString) }
                else if let s = item as? String { c.resume(returning: s) }
                else { c.resume(returning: nil) }
            }
        }
    }

    nonisolated static func carregarTexto(_ p: NSItemProvider) async -> String? {
        guard p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let s = item as? String { c.resume(returning: s) }
                else if let d = item as? Data { c.resume(returning: String(data: d, encoding: .utf8)) }
                else { c.resume(returning: nil) }
            }
        }
    }
}
