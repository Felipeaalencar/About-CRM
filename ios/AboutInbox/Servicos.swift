import Foundation

struct AnaliseIA: Decodable {
    var titulo: String?
    var resumo: String?
    var nome: String?
    var telefone: String?
    var email: String?
    var empresa_cliente: String?
    var unidade: String?
    var servico: String?
    var prioridade: String?
    var proxima_acao: String?
    var lembrete: String?
    var resposta: String?
}

struct ErroServico: LocalizedError {
    let mensagem: String
    var errorDescription: String? { mensagem }
}

enum ServicoIA {
    private struct Resposta: Decodable {
        var analise: AnaliseIA?
        var erro: String?
        var detalhe: String?
    }

    static func analisar(_ d: Demanda) async throws -> AnaliseIA {
        guard let url = URL(string: Cfg.iaURL) else { throw ErroServico(mensagem: "URL da IA inválida") }
        let obs = d.notas.map { ($0.tipo == .audio ? "[áudio] " : "") + $0.texto }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "[áudio] " }
            + d.anexos.compactMap { $0.transcricao.map { "[áudio encaminhado] " + $0 } }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm (EEEE)"
        let corpo: [String: Any] = ["hoje": f.string(from: Date()), "mensagem": d.mensagem, "observacoes": obs]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Cfg.iaKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + Cfg.iaKey, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (dados, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let r = try? JSONDecoder().decode(Resposta.self, from: dados)
        if let a = r?.analise, (200..<300).contains(status) { return a }
        throw ErroServico(mensagem: r?.detalhe ?? r?.erro ?? "HTTP \(status)")
    }
}

struct Vendedor: Identifiable, Hashable {
    let id: String
    let nome: String
    static let padrao = [Vendedor(id: "f", nome: "Felipe"), Vendedor(id: "m", nome: "Matheus"), Vendedor(id: "p", nome: "Paulo"), Vendedor(id: "l", nome: "Laercio")]
}

enum ServicoCRM {
    private static func pedido(_ caminho: String, metodo: String = "GET", corpo: Any? = nil) async throws -> Any? {
        guard let url = URL(string: Cfg.crmURL + "/rest/v1/" + caminho) else { throw ErroServico(mensagem: "URL do CRM inválida") }
        var req = URLRequest(url: url)
        req.httpMethod = metodo
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Cfg.crmKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + Cfg.crmKey, forHTTPHeaderField: "Authorization")
        if metodo == "POST" { req.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        if let corpo { req.httpBody = try JSONSerialization.data(withJSONObject: corpo) }
        let (dados, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ErroServico(mensagem: String(data: dados, encoding: .utf8).map { String($0.prefix(300)) } ?? "HTTP \(status)")
        }
        if dados.isEmpty { return nil }
        return try JSONSerialization.jsonObject(with: dados)
    }

    static func vendedores() async -> [Vendedor] {
        guard let lista = try? await pedido("vendors?select=id,name&order=name") as? [[String: Any]] else { return Vendedor.padrao }
        let v = lista.compactMap { item -> Vendedor? in
            guard let id = item["id"], let nome = item["name"] as? String else { return nil }
            return Vendedor(id: "\(id)", nome: nome)
        }
        return v.isEmpty ? Vendedor.padrao : v
    }

    static func testar() async throws {
        _ = try await pedido("leads?select=id&limit=1")
    }

    struct NovoLead {
        var nome: String
        var telefone: String
        var email: String
        var empresa: String
        var servico: String
        var vendedor: String
        var ticket: Int
        var proximoContato: String
    }

    /// Cria o lead (etapa "Novo lead", origem "WhatsApp") e uma anotação com tudo da demanda.
    /// Devolve o id do lead.
    static func criarLead(_ l: NovoLead, demanda d: Demanda) async throws -> String {
        var lead: [String: Any] = [
            "name": l.nome, "service": l.servico, "empresa": l.empresa, "origin": "WhatsApp",
            "ticket": l.ticket, "vendor_id": l.vendedor, "stage": "Novo lead", "days": 0, "next_contact": l.proximoContato,
        ]
        if !l.telefone.isEmpty { lead["telefone"] = l.telefone }
        if !l.email.isEmpty { lead["email"] = l.email }

        let r = try await pedido("leads", metodo: "POST", corpo: lead)
        guard let primeiro = (r as? [[String: Any]])?.first, let leadId = primeiro["id"] else {
            throw ErroServico(mensagem: "O CRM não devolveu o id do lead")
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM HH:mm"
        var partes = ["📥 Veio do WhatsApp (About Inbox) em \(fmt.string(from: d.criado))"]
        if !d.resumo.isEmpty { partes.append("Resumo: " + d.resumo) }
        if !d.proximaAcao.isEmpty { partes.append("Próximo passo: " + d.proximaAcao) }
        if !d.empresaCliente.isEmpty { partes.append("Empresa/condomínio: " + d.empresaCliente) }
        if !d.mensagem.isEmpty { partes.append("Mensagem original:\n" + d.mensagem) }
        let obs = d.notas.filter { !$0.texto.isEmpty }.map { "• \(fmt.string(from: $0.criado))\($0.tipo == .audio ? " (áudio)" : ""): \($0.texto)" }
            + d.anexos.compactMap { a in a.transcricao.map { "• Áudio encaminhado: " + $0 } }
        if !obs.isEmpty { partes.append("Observações:\n" + obs.joined(separator: "\n")) }

        let nota: [String: Any] = ["lead_id": leadId, "type": "Anotação", "text": String(partes.joined(separator: "\n\n").prefix(20000))]
        do { _ = try await pedido("lead_notes", metodo: "POST", corpo: nota) }
        catch { Avisos.shared.mostrar("Lead criado, mas a anotação falhou", erro: true) }
        return "\(leadId)"
    }
}
