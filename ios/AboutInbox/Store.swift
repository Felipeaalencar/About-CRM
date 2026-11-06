import Foundation
import SwiftUI
import UserNotifications

// MARK: - Configurações (Ajustes)

enum Cfg {
    // IA: função "inbox-ia" (Supabase). Pode trocar em Ajustes.
    static let iaURLPadrao = "https://fvjdgpvfrfkwmzdmimkr.supabase.co/functions/v1/inbox-ia"
    static let iaKeyPadrao = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ2amRncHZmcmZrd216ZG1pbWtyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM0OTcxNzUsImV4cCI6MjEwOTA3MzE3NX0._q0CqOsKuPstrMqyNV972qh3nnxPRNRB_2Mf5alYVfk"
    // About CRM: mesmo banco e mesma chave pública que o CRM web usa.
    static let crmURLPadrao = "https://avkmrjvfhzzfdxcljjgk.supabase.co"
    static let crmKeyPadrao = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF2a21yanZmaHp6ZmR4Y2xqamdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ0MDg2NTIsImV4cCI6MjA4OTk4NDY1Mn0.iTMcRZwfCtqJc29XSiT_grMMwmOAElzGJcVGuoSYjCg"

    static let servicos = ["Portaria Virtual", "Portaria Autônoma", "Seg. Armada", "Seg. Eletrônica", "Drone", "Controle Acesso", "Pacote de Tecnologia"]
    static let unidades = ["SHIELD", "Connection"]

    private static var d: UserDefaults { .standard }
    static var iaURL: String { valor("iaURL", iaURLPadrao) }
    static var iaKey: String { valor("iaKey", iaKeyPadrao) }
    static var crmURL: String { valor("crmURL", crmURLPadrao) }
    static var crmKey: String { valor("crmKey", crmKeyPadrao) }
    static var vendedor: String { valor("vendedor", "f") }
    static var unidade: String { valor("unidade", "SHIELD") }
    static var ticket: Int { d.object(forKey: "ticket") == nil ? 1800 : d.integer(forKey: "ticket") }
    static var autoIA: Bool { d.object(forKey: "autoIA") == nil ? true : d.bool(forKey: "autoIA") }

    private static func valor(_ k: String, _ padrao: String) -> String {
        let v = (d.string(forKey: k) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? padrao : v
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var demandas: [Demanda] = []
    @Published var analisando: Set<String> = []

    private var arquivo: URL { AppGroup.pasta.appendingPathComponent("demandas.json") }

    init() { carregar() }

    func carregar() {
        guard let dados = try? Data(contentsOf: arquivo),
              let lista = try? JSON.decoder.decode([Demanda].self, from: dados) else { return }
        demandas = lista.sorted { $0.criado > $1.criado }
    }

    private func gravarDisco() {
        if let dados = try? JSON.encoder.encode(demandas) {
            try? dados.write(to: arquivo, options: .atomic)
        }
    }

    func demanda(_ id: String) -> Demanda? { demandas.first { $0.id == id } }

    func salvar(_ d: Demanda, tocar: Bool = true) {
        var d = d
        if tocar { d.atualizado = Date() }
        if let i = demandas.firstIndex(where: { $0.id == d.id }) { demandas[i] = d } else { demandas.insert(d, at: 0) }
        gravarDisco()
        Lembretes.agendar(d)
    }

    func binding(_ id: String) -> Binding<Demanda> {
        Binding(
            get: { self.demanda(id) ?? Demanda(id: id) },
            set: { self.salvar($0) }
        )
    }

    func excluir(_ id: String) {
        guard let d = demanda(id) else { return }
        for n in d.notas { if let a = n.audio { apagarMidia(a) } }
        for a in d.anexos { apagarMidia(a.arquivo) }
        demandas.removeAll { $0.id == id }
        gravarDisco()
        Lembretes.cancelar(id)
    }

    func apagarMidia(_ nome: String) {
        try? FileManager.default.removeItem(at: AppGroup.midia.appendingPathComponent(nome))
    }

    @discardableResult
    func criar(texto: String, origem: String, anexos: [Anexo] = [], notas: [Nota] = []) -> Demanda {
        var d = Demanda(origem: origem, mensagem: texto, notas: notas, anexos: anexos)
        Extrator.basico(&d)
        salvar(d)
        if Cfg.autoIA && (!texto.isEmpty || notas.contains { !$0.texto.isEmpty }) {
            analisar(d.id, silencioso: true)
        }
        return d
    }

    /// Lê o que a extensão de Compartilhar deixou na fila. Devolve a última criada.
    @discardableResult
    func processarFila() -> Demanda? {
        let fm = FileManager.default
        guard let arquivos = try? fm.contentsOfDirectory(at: AppGroup.fila, includingPropertiesForKeys: nil) else { return nil }
        var ultima: Demanda?
        let itens = arquivos.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, ItemFila)? in
            guard let dados = try? Data(contentsOf: url), let item = try? JSON.decoder.decode(ItemFila.self, from: dados) else { return nil }
            return (url, item)
        }.sorted { $0.1.criado < $1.1.criado }
        for (url, item) in itens {
            var d = Demanda(criado: item.criado, origem: "whatsapp", mensagem: item.texto, anexos: item.anexos)
            Extrator.basico(&d)
            salvar(d)
            try? fm.removeItem(at: url)
            ultima = d
            if Cfg.autoIA && !item.texto.isEmpty { analisar(d.id, silencioso: true) }
        }
        return ultima
    }

    // MARK: IA

    var ultimoErro: String? = nil

    func analisar(_ id: String, silencioso: Bool = false) {
        guard let d = demanda(id), !analisando.contains(id) else { return }
        analisando.insert(id)
        Task {
            do {
                let a = try await ServicoIA.analisar(d)
                await MainActor.run {
                    self.analisando.remove(id)
                    guard var cur = self.demanda(id) else { return }
                    cur.aplicar(a)
                    self.salvar(cur, tocar: false)
                }
            } catch {
                await MainActor.run {
                    self.analisando.remove(id)
                    if !silencioso { Avisos.shared.mostrar("IA indisponível: \(error.localizedDescription)", erro: true) }
                }
            }
        }
    }

    func exportarURL() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("about-inbox-backup.json")
        if let dados = try? JSON.encoder.encode(demandas) { try? dados.write(to: u) }
        return u
    }
}

extension Demanda {
    var tituloExibicao: String {
        if !titulo.isEmpty { return titulo }
        let base = (mensagem.isEmpty ? (notas.first { !$0.texto.isEmpty }?.texto ?? "") : mensagem)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return notas.isEmpty ? "Demanda sem título" : "Áudio gravado" }
        return base.count > 70 ? String(base.prefix(70)) + "…" : base
    }
    var trecho: String {
        if !resumo.isEmpty { return resumo }
        return String(mensagem.prefix(160))
    }
    var lembreteVencido: Bool { status.ativo && (lembrete.map { $0 <= Date() } ?? false) }
    var lembreteHoje: Bool {
        guard status.ativo, let l = lembrete, l > Date() else { return false }
        return Calendar.current.isDateInToday(l)
    }
    var parado: Bool {
        status.ativo && Date().timeIntervalSince(atualizado) > 3 * 86400 && !(lembrete.map { $0 > Date() } ?? false)
    }

    mutating func aplicar(_ a: AnaliseIA) {
        if let v = a.titulo, !v.isEmpty { titulo = v }
        resumo = a.resumo ?? resumo
        proximaAcao = a.proxima_acao ?? proximaAcao
        if let v = a.resposta, !v.isEmpty { resposta = v }
        if nome.isEmpty, let v = a.nome { nome = v }
        if telefone.isEmpty, let v = a.telefone { telefone = v }
        if email.isEmpty, let v = a.email { email = v }
        if empresaCliente.isEmpty, let v = a.empresa_cliente { empresaCliente = v }
        if unidade.isEmpty, let v = a.unidade, Cfg.unidades.contains(v) { unidade = v }
        if servico.isEmpty, let v = a.servico, Cfg.servicos.contains(v) { servico = v }
        if !prioridadeManual, let v = a.prioridade, let p = Prioridade(rawValue: v) { prioridade = p }
        if lembrete == nil, let v = a.lembrete, let data = Extrator.dataLocal(v), data > Date() { lembrete = data }
        iaEm = Date()
    }
}

// MARK: - Extração simples (sem IA)

enum Extrator {
    static func basico(_ d: inout Demanda) {
        let t = d.mensagem
        if d.telefone.isEmpty, let r = t.range(of: #"(\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}"#, options: .regularExpression) {
            d.telefone = String(t[r]).trimmingCharacters(in: .whitespaces)
        }
        if d.email.isEmpty, let r = t.range(of: #"[\w.+-]+@[\w-]+\.[\w.]+"#, options: .regularExpression) {
            d.email = String(t[r])
        }
        // Cópia do WhatsApp: "[06/11 10:32] Nome: texto"
        if d.nome.isEmpty, let r = t.range(of: #"^\[[^\]]+\]\s*[^:\n]{2,40}:"#, options: .regularExpression) {
            var s = String(t[r])
            if let fim = s.firstIndex(of: "]") { s = String(s[s.index(after: fim)...]) }
            s = s.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            if let primeiro = s.first, !primeiro.isNumber, primeiro != "+" { d.nome = s }
        }
    }

    /// "2026-11-09T09:00" (hora local) -> Date
    static func dataLocal(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let candidatos = [(s, "yyyy-MM-dd'T'HH:mm:ss"), (String(s.prefix(16)), "yyyy-MM-dd'T'HH:mm"), (String(s.prefix(10)), "yyyy-MM-dd")]
        for (texto, formato) in candidatos {
            f.dateFormat = formato
            if let d = f.date(from: texto) {
                return formato == "yyyy-MM-dd" ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) : d
            }
        }
        return nil
    }

    static func digitos(_ s: String) -> String { s.filter(\.isNumber) }

    static func whatsapp(_ tel: String) -> String {
        var d = digitos(tel)
        if d.isEmpty { return "" }
        if d.count <= 11 { d = "55" + d }
        return d
    }
}

// MARK: - Lembretes (notificação do sistema, funciona com o app fechado)

enum Lembretes {
    static func pedirPermissao() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func agendar(_ d: Demanda) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [d.id])
        guard d.status.ativo, let quando = d.lembrete, quando > Date() else { return }
        let conteudo = UNMutableNotificationContent()
        conteudo.title = d.tituloExibicao
        conteudo.body = d.proximaAcao.isEmpty ? (d.resumo.isEmpty ? d.mensagem : d.resumo) : d.proximaAcao
        conteudo.sound = .default
        conteudo.userInfo = ["id": d.id]
        let comp = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
        let gatilho = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
        c.add(UNNotificationRequest(identifier: d.id, content: conteudo, trigger: gatilho))
    }

    static func cancelar(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: - Avisos (toast)

final class Avisos: ObservableObject {
    static let shared = Avisos()
    @Published var texto: String? = nil
    @Published var erro = false
    private var item: DispatchWorkItem?

    func mostrar(_ t: String, erro: Bool = false) {
        DispatchQueue.main.async {
            self.texto = t
            self.erro = erro
            self.item?.cancel()
            let w = DispatchWorkItem { self.texto = nil }
            self.item = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (erro ? 4 : 2.2), execute: w)
        }
    }
}

// MARK: - Navegação

final class Navegacao: ObservableObject {
    static let shared = Navegacao()
    @Published var aberta: DemandaID? = nil
    @Published var aba: Int = 0
    func abrir(_ id: String) { DispatchQueue.main.async { self.aberta = DemandaID(id: id) } }
}

struct DemandaID: Identifiable, Hashable { let id: String }
