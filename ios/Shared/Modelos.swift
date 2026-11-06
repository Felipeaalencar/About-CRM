import Foundation

// Código usado pelo app E pela extensão de Compartilhar.
// Os dois enxergam a mesma pasta (App Group), então a extensão só deixa o que recebeu
// na pasta "fila" e o app transforma em demanda quando abre.

enum AppGroup {
    /// group.<prefixo>.inbox — derivado do bundle id, para não precisar configurar em dois lugares.
    static var id: String {
        var b = Bundle.main.bundleIdentifier ?? "app.inbox"
        if b.hasSuffix(".share") { b = String(b.dropLast(".share".count)) }
        return "group." + b
    }

    static var disponivel: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
    }

    static var pasta: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return u }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var midia: URL { subpasta("midia") }
    static var fila: URL { subpasta("fila") }

    private static func subpasta(_ nome: String) -> URL {
        let u = pasta.appendingPathComponent(nome, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

enum StatusDemanda: String, Codable, CaseIterable, Identifiable {
    case novo, andamento, aguardando, lead, arquivado
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .novo: return "Novo"
        case .andamento: return "Em andamento"
        case .aguardando: return "Aguardando cliente"
        case .lead: return "Virou Lead"
        case .arquivado: return "Arquivado"
        }
    }
    static let ativos: [StatusDemanda] = [.novo, .andamento, .aguardando]
    var ativo: Bool { StatusDemanda.ativos.contains(self) }
}

enum Prioridade: String, Codable, CaseIterable, Identifiable {
    case alta, media, baixa
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .alta: return "Alta"
        case .media: return "Média"
        case .baixa: return "Baixa"
        }
    }
    var ordem: Int {
        switch self {
        case .alta: return 0
        case .media: return 1
        case .baixa: return 2
        }
    }
}

enum TipoNota: String, Codable {
    case texto, audio
}

struct Nota: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var criado: Date = Date()
    var tipo: TipoNota = .texto
    var texto: String = ""
    var audio: String? = nil      // nome do arquivo em AppGroup.midia
    var duracao: Double? = nil
}

struct Anexo: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var nome: String
    var tipo: String              // UTType identifier
    var arquivo: String           // nome do arquivo em AppGroup.midia
    var transcricao: String? = nil
}

struct Demanda: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var criado: Date = Date()
    var atualizado: Date = Date()
    var status: StatusDemanda = .novo
    var origem: String = "manual"     // whatsapp | audio | manual
    var mensagem: String = ""
    var titulo: String = ""
    var resumo: String = ""
    var proximaAcao: String = ""
    var resposta: String = ""
    var nome: String = ""
    var telefone: String = ""
    var email: String = ""
    var empresaCliente: String = ""
    var unidade: String = ""
    var servico: String = ""
    var prioridade: Prioridade = .media
    var prioridadeManual: Bool = false
    var lembrete: Date? = nil
    var notas: [Nota] = []
    var anexos: [Anexo] = []
    var iaEm: Date? = nil
    var leadId: String? = nil
    var leadEm: Date? = nil
    var arquivadoEm: Date? = nil
}

/// O que a extensão de Compartilhar deixa na fila.
struct ItemFila: Codable {
    var id: String = UUID().uuidString
    var criado: Date = Date()
    var texto: String
    var anexos: [Anexo]
}

enum JSON {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
