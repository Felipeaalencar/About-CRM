import SwiftUI
import Charts
import UserNotifications

// MARK: - Relatório

struct RelatorioView: View {
    @EnvironmentObject var store: Store
    @State private var periodo = 7

    private struct Dia: Identifiable {
        let id = UUID()
        let data: Date
        let serie: String
        let valor: Int
    }

    var body: some View {
        let cal = Calendar.current
        let inicio = cal.date(byAdding: .day, value: -(periodo - 1), to: cal.startOfDay(for: Date())) ?? Date()
        let recebidas = store.demandas.filter { $0.criado >= inicio }
        let leads = store.demandas.filter { ($0.leadEm ?? .distantPast) >= inicio }
        let conv = recebidas.isEmpty ? 0 : Int((Double(recebidas.filter { $0.leadId != nil }.count) / Double(recebidas.count) * 100).rounded())
        let tempos = leads.compactMap { d in d.leadEm.map { $0.timeIntervalSince(d.criado) / 3600 } }
        let media = tempos.isEmpty ? 0 : tempos.reduce(0, +) / Double(tempos.count)
        let tempoTxt = tempos.isEmpty ? "—" : (media < 24 ? "\(Int(media.rounded()))h" : String(format: "%.1fd", media / 24).replacingOccurrences(of: ".", with: ","))
        let dias: [Dia] = (0..<periodo).flatMap { i -> [Dia] in
            let d = cal.date(byAdding: .day, value: i, to: inicio) ?? inicio
            return [
                Dia(data: d, serie: "Recebidas", valor: recebidas.filter { cal.isDate($0.criado, inSameDayAs: d) }.count),
                Dia(data: d, serie: "Leads", valor: leads.filter { cal.isDate($0.leadEm ?? .distantPast, inSameDayAs: d) }.count),
            ]
        }
        let porServico = Dictionary(grouping: recebidas, by: { $0.servico.isEmpty ? "Sem definição" : $0.servico })
            .map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        let maxServ = max(1, porServico.first?.1 ?? 1)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Período", selection: $periodo) {
                        Text("7 dias").tag(7)
                        Text("30 dias").tag(30)
                        Text("90 dias").tag(90)
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        Numero(valor: "\(recebidas.count)", rotulo: "Demandas recebidas", cor: .roxoClaro)
                        Numero(valor: "\(leads.count)", rotulo: "Viraram lead", cor: .verde)
                        Numero(valor: "\(conv)%", rotulo: "Conversão", cor: .texto1)
                        Numero(valor: tempoTxt, rotulo: "Tempo médio até lead", cor: .ambar)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TituloSecao(texto: "Por dia")
                        Chart(dias) { d in
                            BarMark(x: .value("Dia", d.data, unit: .day), y: .value("Qtd", d.valor))
                                .foregroundStyle(by: .value("Série", d.serie))
                                .position(by: .value("Série", d.serie))
                        }
                        .chartForegroundStyleScale(["Recebidas": Color.roxo, "Leads": Color.ambar])
                        .frame(height: 160)
                    }
                    .cartao()

                    VStack(alignment: .leading, spacing: 8) {
                        TituloSecao(texto: "Por serviço")
                        if porServico.isEmpty { Text("Sem dados").font(.system(size: 13)).foregroundStyle(Color.texto2) }
                        ForEach(porServico, id: \.0) { item in
                            HStack(spacing: 10) {
                                Text(item.0).font(.system(size: 13)).foregroundStyle(Color.texto2).frame(width: 130, alignment: .leading).lineLimit(1)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.cartao3)
                                        Capsule().fill(Color.roxo).frame(width: g.size.width * CGFloat(item.1) / CGFloat(maxServ))
                                    }
                                }
                                .frame(height: 8)
                                Text("\(item.1)").font(.system(size: 12, design: .monospaced)).frame(width: 26, alignment: .trailing)
                            }
                        }
                    }
                    .cartao()

                    ShareLink(item: textoResumo(recebidas: recebidas, leads: leads)) {
                        Label("Mandar resumo do período", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !leads.isEmpty {
                        TituloSecao(texto: "Leads enviados ao CRM", contador: leads.count).padding(.top, 6)
                        ForEach(leads) { CartaoDemanda(d: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color.fundo)
            .navigationTitle("Relatório")
        }
    }

    private func textoResumo(recebidas: [Demanda], leads: [Demanda]) -> String {
        let abertos = store.demandas.filter { $0.status.ativo }
        var linhas = ["📊 About Inbox: últimos \(periodo) dias",
                      "• \(recebidas.count) demandas recebidas",
                      "• \(leads.count) viraram lead no CRM",
                      "• \(abertos.count) ainda em aberto"]
        if !leads.isEmpty { linhas.append("\nLeads:\n" + leads.map { "– \($0.nome.isEmpty ? $0.tituloExibicao : $0.nome)\($0.servico.isEmpty ? "" : " (\($0.servico))")" }.joined(separator: "\n")) }
        let altas = abertos.filter { $0.prioridade == .alta }
        if !altas.isEmpty { linhas.append("\nPrioridade alta em aberto:\n" + altas.map { "– " + $0.tituloExibicao }.joined(separator: "\n")) }
        return linhas.joined(separator: "\n")
    }
}

struct Numero: View {
    let valor: String
    let rotulo: String
    let cor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).font(.system(size: 28, weight: .medium, design: .monospaced)).foregroundStyle(cor)
            Text(rotulo).font(.system(size: 12)).foregroundStyle(Color.texto2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borda))
    }
}

// MARK: - Ajustes

struct AjustesView: View {
    @EnvironmentObject var store: Store
    @AppStorage("autoIA") private var autoIA = true
    @AppStorage("vendedor") private var vendedor = "f"
    @AppStorage("unidade") private var unidade = "SHIELD"
    @AppStorage("ticket") private var ticket = 1800
    @AppStorage("iaURL") private var iaURL = ""
    @AppStorage("iaKey") private var iaKey = ""
    @AppStorage("crmURL") private var crmURL = ""
    @AppStorage("crmKey") private var crmKey = ""
    @State private var vendedores = Vendedor.padrao
    @State private var testeIA = ""
    @State private var testeCRM = ""
    @State private var notificacoes = "…"

    var body: some View {
        NavigationStack {
            Form {
                Section("Como mandar do WhatsApp") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. No WhatsApp, segure a mensagem (ou o áudio).")
                        Text("2. Toque em **Encaminhar** e depois no ícone de compartilhar (canto inferior direito).")
                        Text("3. Escolha **About Inbox** e toque em Publicar.")
                        Text("Não aparece? Na lista de apps, role até o fim → **Mais** → ative o About Inbox.")
                            .foregroundStyle(Color.texto2)
                    }
                    .font(.system(size: 14))
                }

                Section("Preferências") {
                    Toggle("Resumo automático com IA", isOn: $autoIA)
                    HStack {
                        Text("Notificações de lembrete")
                        Spacer()
                        Button(notificacoes) {
                            Task {
                                _ = await Lembretes.pedirPermissao()
                                await atualizarNotificacoes()
                            }
                        }
                    }
                    Picker("Vendedor padrão", selection: $vendedor) { ForEach(vendedores) { Text($0.nome).tag($0.id) } }
                    Picker("Unidade padrão", selection: $unidade) { ForEach(Cfg.unidades, id: \.self) { Text($0).tag($0) } }
                    Stepper("Ticket padrão: R$ \(ticket)", value: $ticket, in: 0...100000, step: 100)
                }

                Section {
                    TextField("URL da IA", text: $iaURL, prompt: Text(Cfg.iaURLPadrao)).font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Chave da IA (opcional)", text: $iaKey).font(.system(size: 13))
                    HStack {
                        Button("Testar IA") { Task { await testarIA() } }
                        Spacer()
                        Text(testeIA).foregroundStyle(Color.texto2)
                    }
                    TextField("URL do CRM", text: $crmURL, prompt: Text(Cfg.crmURLPadrao)).font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Chave do CRM (opcional)", text: $crmKey).font(.system(size: 13))
                    HStack {
                        Button("Testar CRM") { Task { await testarCRM() } }
                        Spacer()
                        Text(testeCRM).foregroundStyle(Color.texto2)
                    }
                } header: { Text("Conexões") } footer: { Text("Deixe em branco para usar o padrão.") }

                Section {
                    LabeledContent("Demandas guardadas", value: "\(store.demandas.count)")
                    LabeledContent("Pasta compartilhada", value: AppGroup.disponivel ? "OK" : "Sem App Group")
                    ShareLink(item: store.exportarURL()) { Label("Exportar backup (JSON)", systemImage: "square.and.arrow.up") }
                } header: { Text("Seus dados") } footer: {
                    Text(AppGroup.disponivel ? "Tudo fica guardado neste iPhone." : "O App Group não está ativo: o Compartilhar não vai conseguir entregar as mensagens ao app. Veja o LEIA-ME.")
                }

                Section { Text("About Inbox 1.0 · About Group").font(.system(size: 12)).foregroundStyle(Color.texto3) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo)
            .navigationTitle("Ajustes")
            .task {
                await atualizarNotificacoes()
                let v = await ServicoCRM.vendedores()
                await MainActor.run { vendedores = v }
            }
        }
    }

    private func atualizarNotificacoes() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        let t: String
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: t = "Ativadas"
        case .denied: t = "Bloqueadas"
        default: t = "Ativar"
        }
        await MainActor.run { notificacoes = t }
    }

    private func testarIA() async {
        await MainActor.run { testeIA = "testando…" }
        var d = Demanda()
        d.mensagem = "Teste de conexão: Oi, aqui é o João, quero orçamento de câmeras. 48 99999-0000"
        do { _ = try await ServicoIA.analisar(d); await MainActor.run { testeIA = "✓ OK" } }
        catch { await MainActor.run { testeIA = "✗ " + error.localizedDescription } }
    }

    private func testarCRM() async {
        await MainActor.run { testeCRM = "testando…" }
        do { try await ServicoCRM.testar(); await MainActor.run { testeCRM = "✓ OK" } }
        catch { await MainActor.run { testeCRM = "✗ " + error.localizedDescription } }
    }
}
