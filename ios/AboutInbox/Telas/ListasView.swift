import SwiftUI

// MARK: - Cartão de demanda

struct CartaoDemanda: View {
    let d: Demanda
    var quadro = false
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao

    var corBorda: Color? {
        if d.lembreteVencido { return .vermelho.opacity(0.45) }
        if d.status.ativo && d.prioridade == .alta { return .vermelho.opacity(0.25) }
        return nil
    }

    var body: some View {
        Button { nav.abrir(d.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(d.tituloExibicao)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.texto1)
                    .lineLimit(quadro ? 2 : 1)
                    .multilineTextAlignment(.leading)
                if !d.nome.isEmpty || !d.empresaCliente.isEmpty {
                    Text([d.nome, d.empresaCliente].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Color.texto2).lineLimit(1)
                }
                if !quadro && !d.trecho.isEmpty {
                    Text(d.trecho).font(.system(size: 13)).foregroundStyle(Color.texto2).lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    if !quadro && d.status != .novo { Chip(texto: d.status.nome, cor: corStatus(d.status)) }
                    if d.status.ativo && d.prioridade == .alta { Chip(texto: "Alta", cor: .vermelho) }
                    if !d.unidade.isEmpty { Chip(texto: d.unidade, cor: d.unidade == "SHIELD" ? .roxoClaro : .teal) }
                    if d.status.ativo, let l = d.lembrete { Chip(texto: "⏰ " + Formato.lembrete(l), cor: d.lembreteVencido ? .vermelho : .ambar) }
                    if store.analisando.contains(d.id) { ProgressView().controlSize(.mini) }
                    Spacer(minLength: 0)
                    Text(Formato.relativo(d.criado)).font(.system(size: 11.5)).foregroundStyle(Color.texto3)
                }
                .padding(.top, 4)
            }
            .cartao(destaque: corBorda)
        }
        .buttonStyle(.plain)
    }
}

func corStatus(_ s: StatusDemanda) -> Color {
    switch s {
    case .novo: return .roxoClaro
    case .andamento: return .teal
    case .aguardando: return .ambar
    case .lead: return .verde
    case .arquivado: return .texto2
    }
}

// MARK: - Hoje

struct HojeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao
    @Binding var captura: Bool
    @Binding var gravarNovo: Bool

    var body: some View {
        let todos = store.demandas
        let atrasados = todos.filter(\.lembreteVencido).sorted { ($0.lembrete ?? .distantPast) < ($1.lembrete ?? .distantPast) }
        let hoje = todos.filter(\.lembreteHoje).sorted { ($0.lembrete ?? .distantPast) < ($1.lembrete ?? .distantPast) }
        let parados = todos.filter { $0.parado && !$0.lembreteVencido }
        let novos = todos.filter { $0.status == .novo && $0.lembrete == nil && !$0.parado }
        let fimDeHoje = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let proximos = Array(todos.filter { $0.status.ativo && ($0.lembrete.map { $0 >= fimDeHoje } ?? false) }
            .sorted { ($0.lembrete ?? .distantFuture) < ($1.lembrete ?? .distantFuture) }.prefix(5))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("Logo").resizable().scaledToFit().frame(height: 24).padding(.top, 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(saudacao + ", Felipe").font(.system(size: 26, weight: .bold))
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))))
                        .font(.system(size: 13)).foregroundStyle(Color.texto2)
                }

                HStack(spacing: 8) {
                    Bloco(valor: atrasados.count, rotulo: "Atrasados", cor: .vermelho)
                    Bloco(valor: hoje.count, rotulo: "Para hoje", cor: .ambar)
                    Bloco(valor: todos.filter { $0.status == .novo }.count, rotulo: "Novos", cor: .roxoClaro)
                    Bloco(valor: parados.count, rotulo: "Parados", cor: .texto1)
                }

                HStack(spacing: 8) {
                    BotaoCaptura(icone: "doc.on.clipboard", titulo: "Colar do Whats", sub: "mensagem copiada", cor: .verde) { captura = true }
                    BotaoCaptura(icone: "mic.fill", titulo: "Gravar", sub: "falar a demanda", cor: .vermelho) { gravarNovo = true }
                }

                Secao(titulo: "Atrasados", cor: .vermelho, itens: atrasados)
                Secao(titulo: "Para hoje", cor: .ambar, itens: hoje)
                Secao(titulo: "Parados há 3+ dias", cor: .texto2, itens: parados)
                Secao(titulo: "Novos para triar", cor: .roxoClaro, itens: novos)
                Secao(titulo: "Próximos lembretes", cor: .texto2, itens: proximos)

                if atrasados.isEmpty && hoje.isEmpty && parados.isEmpty && novos.isEmpty && proximos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.system(size: 34)).foregroundStyle(Color.roxoClaro)
                        Text("Tudo em dia").font(.headline)
                        Text("Quando chegar demanda no WhatsApp: segure a mensagem → Encaminhar → Compartilhar → About Inbox.")
                            .font(.system(size: 13)).foregroundStyle(Color.texto2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background(Color.fundo)
    }

    private var saudacao: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Bom dia" : (h < 18 ? "Boa tarde" : "Boa noite")
    }
}

struct Bloco: View {
    let valor: Int
    let rotulo: String
    let cor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(valor)").font(.system(size: 24, weight: .medium, design: .monospaced)).foregroundStyle(cor)
            Text(rotulo).font(.system(size: 11.5)).foregroundStyle(Color.texto2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borda))
    }
}

struct BotaoCaptura: View {
    let icone: String
    let titulo: String
    let sub: String
    let cor: Color
    let acao: () -> Void
    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                Image(systemName: icone).font(.system(size: 17, weight: .semibold)).foregroundStyle(cor)
                    .frame(width: 38, height: 38).background(cor.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.texto1)
                    Text(sub).font(.system(size: 12)).foregroundStyle(Color.texto2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borda))
        }
        .buttonStyle(.plain)
    }
}

struct Secao: View {
    let titulo: String
    let cor: Color
    let itens: [Demanda]
    var body: some View {
        if !itens.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TituloSecao(texto: titulo, cor: cor, contador: itens.count)
                ForEach(itens) { CartaoDemanda(d: $0) }
            }
        }
    }
}

// MARK: - Inbox (lista / quadro)

struct InboxView: View {
    @EnvironmentObject var store: Store
    @AppStorage("inboxQuadro") private var quadro = false
    @AppStorage("inboxFiltro") private var filtro = "ativos"
    @State private var busca = ""

    private let filtros: [(String, String)] = [("ativos", "Ativos"), ("novo", "Novos"), ("andamento", "Em andamento"), ("aguardando", "Aguardando"), ("lead", "Viraram Lead"), ("arquivado", "Arquivados"), ("todos", "Todos")]

    private func passa(_ d: Demanda, _ f: String) -> Bool {
        switch f {
        case "ativos": return d.status.ativo
        case "todos": return true
        default: return d.status.rawValue == f
        }
    }

    private var buscados: [Demanda] {
        let q = busca.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return store.demandas }
        return store.demandas.filter { d in
            ([d.titulo, d.mensagem, d.nome, d.telefone, d.empresaCliente, d.resumo, d.servico] + d.notas.map(\.texto))
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if quadro { quadroView } else { listaView }
            }
            .background(Color.fundo)
            .navigationTitle("Inbox")
            .searchable(text: $busca, prompt: "Buscar nome, telefone, assunto…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Visão", selection: $quadro) {
                        Image(systemName: "list.bullet").tag(false)
                        Image(systemName: "rectangle.split.3x1").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 100)
                }
            }
        }
    }

    private var listaView: some View {
        let lista = buscados.filter { passa($0, filtro) }.sorted { a, b in
            if filtro == "ativos" {
                if a.lembreteVencido != b.lembreteVencido { return a.lembreteVencido }
                if a.prioridade != b.prioridade { return a.prioridade.ordem < b.prioridade.ordem }
            }
            return a.criado > b.criado
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filtros, id: \.0) { f in
                            let n = store.demandas.filter { passa($0, f.0) }.count
                            Button { filtro = f.0 } label: {
                                Text("\(f.1)  \(n)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(filtro == f.0 ? Color.fundo : Color.texto2)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(filtro == f.0 ? Color.texto1 : Color.cartao, in: Capsule())
                                    .overlay(Capsule().stroke(Color.borda))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if lista.isEmpty {
                    Text(busca.isEmpty ? "Nenhuma demanda aqui." : "Nada encontrado.")
                        .foregroundStyle(Color.texto2).frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(lista) { CartaoDemanda(d: $0) }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
    }

    private var quadroView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach([StatusDemanda.novo, .andamento, .aguardando, .lead]) { s in
                    let itens = buscados.filter { $0.status == s }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(corStatus(s)).frame(width: 8, height: 8)
                            Text(s.nome).font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text("\(itens.count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.texto3)
                        }
                        .padding(.horizontal, 4)
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(itens) { d in
                                    VStack(spacing: 6) {
                                        CartaoDemanda(d: d, quadro: true)
                                        BotoesMover(d: d)
                                    }
                                }
                                if itens.isEmpty { Text("Nada aqui").font(.system(size: 12)).foregroundStyle(Color.texto3).padding(8) }
                            }
                        }
                    }
                    .padding(10)
                    .frame(width: 280)
                    .background(Color.cartao.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borda))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
    }
}

struct BotoesMover: View {
    let d: Demanda
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao

    var body: some View {
        let ordem: [StatusDemanda] = [.novo, .andamento, .aguardando]
        if let i = ordem.firstIndex(of: d.status) {
            HStack(spacing: 6) {
                if i > 0 { botao("◀ " + curto(ordem[i - 1])) { mover(ordem[i - 1]) } }
                if i < 2 { botao(curto(ordem[i + 1]) + " ▶") { mover(ordem[i + 1]) } }
                if i == 2 { botao("Enviar p/ CRM ▶") { nav.abrir(d.id) } }
            }
        }
    }

    private func curto(_ s: StatusDemanda) -> String {
        switch s { case .novo: return "Novo"; case .andamento: return "Andamento"; case .aguardando: return "Aguardando"; default: return s.nome }
    }
    private func mover(_ s: StatusDemanda) { var x = d; x.status = s; store.salvar(x) }
    private func botao(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.texto2)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Color.cartao3, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Captura (+)

struct CapturaSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao
    @Environment(\.dismiss) private var fechar
    let gravar: () -> Void
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Copiou a mensagem no WhatsApp? Toque em Colar:").font(.system(size: 14)).foregroundStyle(Color.texto2)
                        PasteButton(payloadType: String.self) { textos in
                            let t = textos.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            DispatchQueue.main.async { salvar(t, origem: "whatsapp") }
                        }
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .tint(.verde)
                    }
                    .cartao()

                    Button(action: gravar) {
                        Label("Gravar áudio", systemImage: "mic.fill")
                    }
                    .buttonStyle(BotaoPrincipal(cor: .vermelho))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ou escreva:").font(.system(size: 14)).foregroundStyle(Color.texto2)
                        TextEditor(text: $texto)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 12))
                        Button("Salvar no Inbox") { salvar(texto, origem: "manual") }
                            .buttonStyle(BotaoPrincipal())
                            .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    }
                }
                .padding(16)
            }
            .background(Color.fundo)
            .navigationTitle("Nova demanda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { fechar() } } }
        }
    }

    private func salvar(_ t: String, origem: String) {
        let d = store.criar(texto: t.trimmingCharacters(in: .whitespacesAndNewlines), origem: origem)
        Avisos.shared.mostrar("Salvo no Inbox ✓")
        fechar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nav.abrir(d.id) }
    }
}
