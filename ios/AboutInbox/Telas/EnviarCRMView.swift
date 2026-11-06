import SwiftUI

struct EnviarCRMView: View {
    let id: String
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var fechar
    @State private var nome = ""
    @State private var telefone = ""
    @State private var email = ""
    @State private var empresa = Cfg.unidade
    @State private var servico = ""
    @State private var vendedor = Cfg.vendedor
    @State private var ticket = String(Cfg.ticket)
    @State private var proximo = ""
    @State private var vendedores = Vendedor.padrao
    @State private var enviando = false
    @State private var erro: String? = nil
    @State private var pronto = false

    var body: some View {
        NavigationStack {
            Group {
                if pronto { sucesso } else { formulario }
            }
            .navigationTitle("Enviar para About CRM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { fechar() } } }
        }
        .task { await preparar() }
    }

    private var formulario: some View {
        Form {
            Section {
                Text("Cria um **Novo lead** com origem **WhatsApp**. O resumo, a mensagem e suas observações vão como anotação.")
                    .font(.system(size: 13)).foregroundStyle(Color.texto2)
            }
            Section("Lead") {
                TextField("Nome do lead", text: $nome)
                TextField("Telefone", text: $telefone).keyboardType(.phonePad)
                TextField("E-mail", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section("Classificação") {
                Picker("Empresa", selection: $empresa) { ForEach(Cfg.unidades, id: \.self) { Text($0).tag($0) } }
                Picker("Serviço", selection: $servico) {
                    Text("Escolha…").tag("")
                    ForEach(Cfg.servicos, id: \.self) { Text($0).tag($0) }
                }
                Picker("Vendedor", selection: $vendedor) { ForEach(vendedores) { Text($0.nome).tag($0.id) } }
                HStack {
                    Text("Ticket mensal (R$)")
                    TextField("1800", text: $ticket).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
            Section("Próximo contato") {
                TextField("Ex.: Ligar na segunda", text: $proximo, axis: .vertical)
            }
            if let erro {
                Section { Text("Não consegui criar o lead: \(erro)").foregroundStyle(Color.vermelho).font(.system(size: 13)) }
            }
            Section {
                Button { Task { await enviar() } } label: {
                    HStack {
                        Spacer()
                        if enviando { ProgressView().tint(.white) } else { Text(erro == nil ? "Criar lead" : "Tentar de novo").bold() }
                        Spacer()
                    }
                }
                .listRowBackground(Color.roxo)
                .foregroundStyle(.white)
                .disabled(enviando)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fundo)
    }

    private var sucesso: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(Color.verde)
            Text("Lead criado no About CRM").font(.title3.bold())
            Text("\(nome) entrou em **Novo lead**. A demanda foi para \"Virou Lead\".")
                .font(.system(size: 14)).foregroundStyle(Color.texto2).multilineTextAlignment(.center)
            Button("Pronto") { fechar() }.buttonStyle(BotaoPrincipal()).padding(.top, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fundo)
    }

    private func preparar() async {
        guard let d = store.demanda(id) else { return }
        await MainActor.run {
            nome = d.nome.isEmpty ? d.empresaCliente : (d.empresaCliente.isEmpty ? d.nome : "\(d.nome) – \(d.empresaCliente)")
            telefone = d.telefone
            email = d.email
            if !d.unidade.isEmpty { empresa = d.unidade }
            servico = d.servico
            proximo = d.proximaAcao.isEmpty ? (d.lembrete.map { "Retornar " + Formato.lembrete($0) } ?? "") : d.proximaAcao
        }
        let v = await ServicoCRM.vendedores()
        await MainActor.run {
            vendedores = v
            if !v.contains(where: { $0.id == vendedor }), let primeiro = v.first { vendedor = primeiro.id }
        }
    }

    private func enviar() async {
        let n = nome.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { await MainActor.run { erro = "informe o nome do lead" }; return }
        guard !servico.isEmpty else { await MainActor.run { erro = "escolha o serviço" }; return }
        guard let d = store.demanda(id) else { return }
        await MainActor.run { enviando = true; erro = nil }
        let lead = ServicoCRM.NovoLead(nome: n, telefone: telefone, email: email, empresa: empresa, servico: servico,
                                       vendedor: vendedor, ticket: Int(Extrator.digitos(ticket)) ?? 1800, proximoContato: proximo)
        do {
            let leadId = try await ServicoCRM.criarLead(lead, demanda: d)
            await MainActor.run {
                UserDefaults.standard.set(vendedor, forKey: "vendedor")
                if var cur = store.demanda(id) {
                    cur.leadId = leadId
                    cur.leadEm = Date()
                    cur.status = .lead
                    if cur.nome.isEmpty { cur.nome = n }
                    if cur.telefone.isEmpty { cur.telefone = telefone }
                    if cur.email.isEmpty { cur.email = email }
                    cur.servico = servico
                    cur.unidade = empresa
                    store.salvar(cur)
                }
                enviando = false
                pronto = true
            }
        } catch {
            await MainActor.run { enviando = false; self.erro = error.localizedDescription }
        }
    }
}
