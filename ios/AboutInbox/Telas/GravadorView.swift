import SwiftUI

/// Tela cheia de gravação. Sem demandaId cria uma demanda nova; com demandaId vira observação.
struct GravadorView: View {
    let demandaId: String?
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao
    @Environment(\.dismiss) private var fechar
    @StateObject private var g = Gravador()
    @State private var erro: String? = nil
    @State private var salvando = false

    var body: some View {
        VStack(spacing: 14) {
            Text(rotulo).font(.system(size: 13)).foregroundStyle(Color.texto2).lineLimit(1).padding(.top, 20)
            Text(Formato.duracao(g.tempo)).font(.system(size: 56, weight: .medium, design: .monospaced))
            HStack(spacing: 8) {
                Circle().fill(g.pausado ? Color.ambar : Color.vermelho).frame(width: 8, height: 8)
                Text(g.pausado ? "PAUSADO" : "GRAVANDO").font(.system(size: 12, weight: .bold)).tracking(1)
                    .foregroundStyle(g.pausado ? Color.ambar : Color.vermelho)
            }
            .opacity(g.gravando ? 1 : 0)

            Onda(niveis: g.niveis, cor: g.pausado ? .ambar : .vermelho).frame(height: 90)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TRANSCRIÇÃO AO VIVO").font(.system(size: 11.5, weight: .bold)).tracking(0.8).foregroundStyle(Color.roxoClaro)
                        if let erro {
                            Text(erro).foregroundStyle(Color.vermelho)
                        } else if g.semTranscricao {
                            Text("Transcrição indisponível. O áudio será salvo normalmente.").foregroundStyle(Color.texto2)
                        } else if g.texto.isEmpty && g.parcial.isEmpty {
                            Text("Fale normalmente. O texto aparece aqui enquanto você fala.").foregroundStyle(Color.texto3)
                        } else {
                            (Text(g.texto + (g.texto.isEmpty ? "" : " ")) + Text(g.parcial).foregroundColor(Color.texto3))
                        }
                        Color.clear.frame(height: 1).id("fim")
                    }
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borda))
                .onChange(of: g.parcial) { _, _ in withAnimation { proxy.scrollTo("fim", anchor: .bottom) } }
            }

            HStack(alignment: .top, spacing: 34) {
                controle("xmark", "Cancelar", tamanho: 56) { g.cancelar(); fechar() }
                VStack(spacing: 6) {
                    Button { concluir() } label: {
                        ZStack {
                            Circle().fill(Color.vermelho).frame(width: 80, height: 80)
                                .shadow(color: .vermelho.opacity(0.3), radius: 0, x: 0, y: 0)
                                .overlay(Circle().stroke(Color.vermelho.opacity(0.18), lineWidth: 9).padding(-5))
                            if salvando { ProgressView().tint(.white) }
                            else { RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 26, height: 26) }
                        }
                    }
                    .accessibilityLabel("Concluir gravação")
                    .disabled(!g.gravando || salvando)
                    Text("Concluir").font(.system(size: 12, weight: .semibold))
                }
                controle(g.pausado ? "play.fill" : "pause.fill", g.pausado ? "Continuar" : "Pausar", tamanho: 56) { g.alternarPausa() }
                    .disabled(!g.gravando)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [Color(hex: 0x24154A), .fundo], center: .top, startRadius: 0, endRadius: 520).ignoresSafeArea())
        .task { await comecar() }
        .onDisappear { if g.gravando { g.cancelar() } }
    }

    private var rotulo: String {
        if let id = demandaId, let d = store.demanda(id) { return "Observação para: " + d.tituloExibicao }
        return "Nova demanda por voz"
    }

    private func controle(_ icone: String, _ texto: String, tamanho: CGFloat, acao: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: acao) {
                Image(systemName: icone).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.texto1)
                    .frame(width: tamanho, height: tamanho)
                    .background(Color.cartao2, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12)))
            }
            .accessibilityLabel(texto)
            Text(texto).font(.system(size: 12)).foregroundStyle(Color.texto2)
        }
    }

    private func comecar() async {
        let ok = await Gravador.pedirPermissoes()
        guard ok else {
            erro = "Sem acesso ao microfone. Libere em Ajustes do iPhone → About Inbox."
            return
        }
        do { try g.iniciar() } catch { erro = "Não consegui começar a gravar: \(error.localizedDescription)" }
    }

    private func concluir() {
        salvando = true
        Task {
            let r = await g.concluir()
            await MainActor.run {
                salvando = false
                guard let r else {
                    Avisos.shared.mostrar("Gravação muito curta", erro: true)
                    fechar()
                    return
                }
                let (url, dur, texto) = r
                let nota = Nota(tipo: .audio, texto: texto, audio: url.lastPathComponent, duracao: dur)
                if let id = demandaId, var d = store.demanda(id) {
                    d.notas.append(nota)
                    if d.status == .novo { d.status = .andamento }
                    store.salvar(d)
                    if !texto.isEmpty && Cfg.autoIA { store.analisar(id, silencioso: true) }
                    Avisos.shared.mostrar("Áudio salvo ✓")
                    fechar()
                } else {
                    let d = store.criar(texto: "", origem: "audio", notas: [nota])
                    Avisos.shared.mostrar("Demanda salva ✓")
                    fechar()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nav.abrir(d.id) }
                }
            }
        }
    }
}

struct Onda: View {
    let niveis: [CGFloat]
    let cor: Color
    var body: some View {
        GeometryReader { geo in
            let n = max(1, Int(geo.size.width / 5))
            let vals = Array(niveis.suffix(n))
            HStack(alignment: .center, spacing: 2) {
                Spacer(minLength: 0)
                ForEach(Array(vals.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cor.opacity(0.35 + 0.65 * Double(i) / Double(max(1, vals.count))))
                        .frame(width: 3, height: max(3, v * geo.size.height * 0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
