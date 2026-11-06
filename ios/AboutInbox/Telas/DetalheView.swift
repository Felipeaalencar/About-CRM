import SwiftUI
import UIKit

struct DetalheView: View {
    let id: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var avisos: Avisos
    @Environment(\.dismiss) private var fechar
    @StateObject private var tocador = Tocador.shared
    @State private var novaNota = ""
    @State private var gravar = false
    @State private var enviar = false
    @State private var confirmarExcluir = false
    @State private var transcrevendo: String? = nil

    var body: some View {
        let d = store.binding(id)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cabecalho(d)
                    if d.wrappedValue.leadId != nil {
                        Label("Virou Lead no About CRM em \(d.wrappedValue.leadEm.map(Formato.data) ?? "")", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.verde)
                            .cartao(destaque: .verde.opacity(0.35))
                    }
                    duplicados(d.wrappedValue)
                    cartaoIA(d)
                    if !d.wrappedValue.mensagem.isEmpty { mensagem(d.wrappedValue) }
                    observacoes(d)
                    if !d.wrappedValue.anexos.isEmpty { anexos(d) }
                    lembrete(d)
                    contato(d)
                    classificacao(d)
                    if !d.wrappedValue.resposta.isEmpty { resposta(d) }
                    HStack {
                        if d.wrappedValue.status != .arquivado {
                            Button("Arquivar") { d.wrappedValue.status = .arquivado; d.wrappedValue.arquivadoEm = Date(); fechar() }
                        } else {
                            Button("Desarquivar") { d.wrappedValue.status = .novo }
                        }
                        Spacer()
                        Button("Excluir", role: .destructive) { confirmarExcluir = true }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.fundo)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { tocador.parar(); fechar() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Fechar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Status", selection: d.status) {
                        ForEach(StatusDemanda.allCases) { Text($0.nome).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .safeAreaInset(edge: .bottom) { barraInferior(d.wrappedValue) }
            .overlay(alignment: .bottom) {
                if let t = avisos.texto {
                    Text(t).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(avisos.erro ? Color.white : Color.fundo)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(avisos.erro ? Color.vermelho : Color.texto1, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 90).padding(.horizontal, 20)
                }
            }
        }
        .fullScreenCover(isPresented: $gravar) { GravadorView(demandaId: id) }
        .sheet(isPresented: $enviar) { EnviarCRMView(id: id).presentationDetents([.large]) }
        .confirmationDialog("Excluir esta demanda de vez?", isPresented: $confirmarExcluir, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) { tocador.parar(); store.excluir(id); fechar() }
        } message: { Text("Arquivar mantém o histórico.") }
    }

    // MARK: Partes

    private func cabecalho(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título", text: Binding(get: { d.wrappedValue.tituloExibicao }, set: { d.wrappedValue.titulo = $0 }), axis: .vertical)
                .font(.system(size: 22, weight: .bold))
            HStack(spacing: 6) {
                Chip(texto: d.wrappedValue.status.nome, cor: corStatus(d.wrappedValue.status))
                Chip(texto: "Prioridade " + d.wrappedValue.prioridade.nome.lowercased(), cor: d.wrappedValue.prioridade == .alta ? .vermelho : (d.wrappedValue.prioridade == .media ? .ambar : .texto2))
                Text("Recebido " + Formato.data(d.wrappedValue.criado)).font(.system(size: 12)).foregroundStyle(Color.texto2)
            }
        }
    }

    @ViewBuilder
    private func duplicados(_ d: Demanda) -> some View {
        let tel = String(Extrator.digitos(d.telefone).suffix(8))
        let nome = d.nome.trimmingCharacters(in: .whitespaces).lowercased()
        let iguais = store.demandas.filter { o in
            o.id != d.id && ((tel.count >= 8 && String(Extrator.digitos(o.telefone).suffix(8)) == tel) || (nome.count >= 4 && o.nome.trimmingCharacters(in: .whitespaces).lowercased() == nome))
        }
        if !iguais.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Esse contato já apareceu antes", systemImage: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .semibold))
                ForEach(iguais.prefix(3)) { o in
                    Text("• \(o.tituloExibicao) (\(Formato.relativo(o.criado))\(o.leadId != nil ? ", já é Lead" : ""))").font(.system(size: 13))
                }
            }
            .foregroundStyle(Color(hex: 0xFCD34D))
            .cartao(destaque: .ambar.opacity(0.35))
        }
    }

    private func cartaoIA(_ d: Binding<Demanda>) -> some View {
        let analisando = store.analisando.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Resumo da IA", systemImage: "sparkles").font(.system(size: 12, weight: .bold)).tracking(0.6).foregroundStyle(Color.roxoClaro)
                Spacer()
                if analisando { ProgressView().controlSize(.small) }
                else {
                    Button(d.wrappedValue.iaEm == nil ? "Analisar" : "Reanalisar") { store.analisar(id) }
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            if !d.wrappedValue.resumo.isEmpty {
                Text(d.wrappedValue.resumo).font(.system(size: 15))
            } else {
                Text(analisando ? "Lendo a mensagem e as observações…" : "Toque em Analisar: a IA resume, acha o contato, sugere unidade, serviço, prioridade, lembrete e uma resposta.")
                    .font(.system(size: 13.5)).foregroundStyle(Color.texto2)
            }
            if !d.wrappedValue.proximaAcao.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                (Text("Próximo passo: ").bold() + Text(d.wrappedValue.proximaAcao)).font(.system(size: 14))
            }
        }
        .padding(14)
        .background(Color(hex: 0x17102A), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.roxoClaro.opacity(0.3)))
    }

    private func mensagem(_ d: Demanda) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloSecao(texto: "Mensagem do WhatsApp")
                Button { UIPasteboard.general.string = d.mensagem; avisos.mostrar("Copiado ✓") } label: { Label("Copiar", systemImage: "doc.on.doc").font(.system(size: 13)) }
            }
            Text(d.mensagem).font(.system(size: 14)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func observacoes(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloSecao(texto: "Observações", contador: d.wrappedValue.notas.count)
            if d.wrappedValue.notas.isEmpty {
                Text("Nada ainda. Escreva ou grave um áudio para não esquecer.").font(.system(size: 13)).foregroundStyle(Color.texto2)
            }
            ForEach(d.wrappedValue.notas) { n in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text((n.tipo == .audio ? "Áudio " + Formato.duracao(n.duracao ?? 0) : "Nota") + " · " + Formato.data(n.criado))
                            .font(.system(size: 11.5)).foregroundStyle(Color.texto3)
                        Spacer()
                        Button { apagarNota(d, n) } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                            .foregroundStyle(Color.texto3).accessibilityLabel("Apagar observação")
                    }
                    if !n.texto.isEmpty { Text(n.texto).font(.system(size: 14)).textSelection(.enabled) }
                    else if n.tipo == .audio { Text("(sem transcrição)").font(.system(size: 13)).foregroundStyle(Color.texto2) }
                    if let a = n.audio { botaoTocar(a) }
                }
                .cartao()
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Escrever observação…", text: $novaNota, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(12)
                    .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 12))
                if novaNota.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { gravar = true } label: {
                        Image(systemName: "mic.fill").foregroundStyle(.white).frame(width: 46, height: 46)
                            .background(Color.vermelho, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel("Gravar áudio")
                } else {
                    Button {
                        d.wrappedValue.notas.append(Nota(tipo: .texto, texto: novaNota.trimmingCharacters(in: .whitespacesAndNewlines)))
                        if d.wrappedValue.status == .novo { d.wrappedValue.status = .andamento }
                        novaNota = ""
                        avisos.mostrar("Observação salva")
                    } label: {
                        Image(systemName: "paperplane.fill").foregroundStyle(.white).frame(width: 46, height: 46)
                            .background(Color.roxo, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel("Salvar observação")
                }
            }
        }
    }

    private func botaoTocar(_ arquivo: String) -> some View {
        Button { tocador.alternar(arquivo) } label: {
            Label(tocador.tocando == arquivo ? "Parar" : "Ouvir", systemImage: tocador.tocando == arquivo ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.cartao3, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func apagarNota(_ d: Binding<Demanda>, _ n: Nota) {
        if let a = n.audio { if tocador.tocando == a { tocador.parar() }; store.apagarMidia(a) }
        d.wrappedValue.notas.removeAll { $0.id == n.id }
    }

    private func anexos(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloSecao(texto: "Anexos", contador: d.wrappedValue.anexos.count)
            ForEach(d.wrappedValue.anexos) { a in
                let audio = UTTypeAudio(a)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: audio ? "waveform" : (a.tipo.contains("image") ? "photo" : "doc"))
                        Text(a.nome).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                    }
                    if let t = a.transcricao { Text(t).font(.system(size: 14)).textSelection(.enabled) }
                    HStack(spacing: 8) {
                        if audio {
                            botaoTocar(a.arquivo)
                            if a.transcricao == nil {
                                Button {
                                    transcrever(d, a)
                                } label: {
                                    HStack(spacing: 6) {
                                        if transcrevendo == a.id { ProgressView().controlSize(.mini) }
                                        Text("Transcrever")
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.roxo.opacity(0.2), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(transcrevendo != nil)
                            }
                        } else {
                            ShareLink(item: AppGroup.midia.appendingPathComponent(a.arquivo)) { Label("Abrir", systemImage: "square.and.arrow.up").font(.system(size: 13)) }
                        }
                    }
                }
                .cartao()
            }
        }
    }

    private func UTTypeAudio(_ a: Anexo) -> Bool {
        let ext = (a.arquivo as NSString).pathExtension.lowercased()
        return a.tipo.contains("audio") || ["opus", "ogg", "m4a", "mp3", "aac", "wav", "caf"].contains(ext)
    }

    private func transcrever(_ d: Binding<Demanda>, _ a: Anexo) {
        transcrevendo = a.id
        Task {
            do {
                let t = try await Gravador.transcrever(AppGroup.midia.appendingPathComponent(a.arquivo))
                await MainActor.run {
                    transcrevendo = nil
                    if var cur = store.demanda(id), let i = cur.anexos.firstIndex(where: { $0.id == a.id }) {
                        cur.anexos[i].transcricao = t
                        store.salvar(cur)
                        store.analisar(id, silencioso: true)
                    }
                }
            } catch {
                await MainActor.run {
                    transcrevendo = nil
                    avisos.mostrar(error.localizedDescription, erro: true)
                }
            }
        }
    }

    private func lembrete(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TituloSecao(texto: "Lembrete")
                if d.wrappedValue.lembrete != nil { Button("Remover") { d.wrappedValue.lembrete = nil }.font(.system(size: 13)) }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let l = d.wrappedValue.lembrete {
                    DatePicker("Quando", selection: Binding(get: { l }, set: { d.wrappedValue.lembrete = $0 }), displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                    Text(d.wrappedValue.lembreteVencido ? "Venceu: \(Formato.lembrete(l))" : "Vou te avisar: \(Formato.lembrete(l))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(d.wrappedValue.lembreteVencido ? Color.vermelho : Color.ambar)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["Daqui 1h", "Hoje 18h", "Amanhã 9h", "Segunda 9h", "+1 semana"], id: \.self) { p in
                            Button(p) { definir(d, preset: p) }
                                .font(.system(size: 12.5)).foregroundStyle(Color.texto2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            .cartao()
        }
    }

    private func definir(_ d: Binding<Demanda>, preset: String) {
        let cal = Calendar.current
        let agora = Date()
        var alvo: Date
        switch preset {
        case "Daqui 1h": alvo = agora.addingTimeInterval(3600)
        case "Hoje 18h":
            alvo = cal.date(bySettingHour: 18, minute: 0, second: 0, of: agora) ?? agora
            if alvo < agora { alvo = cal.date(byAdding: .day, value: 1, to: alvo) ?? alvo }
        case "Amanhã 9h": alvo = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: agora) ?? agora) ?? agora
        case "Segunda 9h":
            let proxima = cal.nextDate(after: agora, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime) ?? agora
            alvo = proxima
        default: alvo = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 7, to: agora) ?? agora) ?? agora
        }
        d.wrappedValue.lembrete = alvo
        Task {
            let ok = await Lembretes.pedirPermissao()
            if ok { Lembretes.agendar(store.demanda(id) ?? d.wrappedValue) }
            avisos.mostrar(ok ? "Lembrete: \(Formato.lembrete(alvo))" : "Ative as notificações em Ajustes do iPhone", erro: !ok)
        }
    }

    private func contato(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloSecao(texto: "Contato")
            HStack(spacing: 8) {
                campo("Nome", d.nome)
                campo("Telefone", d.telefone, teclado: .phonePad)
            }
            HStack(spacing: 8) {
                campo("E-mail", d.email, teclado: .emailAddress)
                campo("Empresa / condomínio", d.empresaCliente)
            }
            let wa = Extrator.whatsapp(d.wrappedValue.telefone)
            if !wa.isEmpty, let url = URL(string: "https://wa.me/\(wa)") {
                Link(destination: url) { Label("Abrir conversa no WhatsApp", systemImage: "bubble.left.and.bubble.right").font(.system(size: 13, weight: .semibold)) }
            }
        }
    }

    private func campo(_ rotulo: String, _ valor: Binding<String>, teclado: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rotulo).font(.system(size: 12)).foregroundStyle(Color.texto2)
            TextField(rotulo, text: valor)
                .keyboardType(teclado)
                .textInputAutocapitalization(teclado == .emailAddress ? .never : .words)
                .padding(10)
                .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func classificacao(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloSecao(texto: "Classificação")
            VStack(spacing: 0) {
                Picker("Unidade", selection: d.unidade) {
                    Text("—").tag("")
                    ForEach(Cfg.unidades, id: \.self) { Text($0).tag($0) }
                }
                Divider().overlay(Color.borda)
                Picker("Serviço", selection: d.servico) {
                    Text("—").tag("")
                    ForEach(Cfg.servicos, id: \.self) { Text($0).tag($0) }
                }
                Divider().overlay(Color.borda)
                Picker("Prioridade", selection: Binding(get: { d.wrappedValue.prioridade }, set: { d.wrappedValue.prioridade = $0; d.wrappedValue.prioridadeManual = true })) {
                    ForEach(Prioridade.allCases) { Text($0.nome).tag($0) }
                }
            }
            .pickerStyle(.navigationLink)
            .cartao()
        }
    }

    private func resposta(_ d: Binding<Demanda>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TituloSecao(texto: "Resposta sugerida")
            VStack(alignment: .leading, spacing: 10) {
                TextField("Resposta", text: d.resposta, axis: .vertical).font(.system(size: 14))
                HStack(spacing: 8) {
                    Button { UIPasteboard.general.string = d.wrappedValue.resposta; avisos.mostrar("Copiado ✓") } label: {
                        Label("Copiar", systemImage: "doc.on.doc").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Color.cartao3, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    let wa = Extrator.whatsapp(d.wrappedValue.telefone)
                    if !wa.isEmpty, let texto = d.wrappedValue.resposta.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: "https://wa.me/\(wa)?text=\(texto)") {
                        Link(destination: url) {
                            Text("Responder no Whats").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x052E14))
                                .padding(.horizontal, 12).padding(.vertical, 8).background(Color.verde, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .cartao()
        }
    }

    private func barraInferior(_ d: Demanda) -> some View {
        HStack(spacing: 8) {
            Button { gravar = true } label: {
                Image(systemName: "mic.fill").frame(width: 52, height: 50)
                    .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Gravar áudio")
            if d.leadId == nil {
                Button("Enviar para About CRM →") { enviar = true }.buttonStyle(BotaoPrincipal())
            } else {
                Button("Já está no CRM ✓") {}.buttonStyle(BotaoPrincipal(cor: .verde)).disabled(true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}
