import Foundation
import AVFoundation
import Speech

/// Grava em .m4a e transcreve ao vivo em português (reconhecimento de voz da Apple).
final class Gravador: ObservableObject {
    @Published var gravando = false
    @Published var pausado = false
    @Published var tempo: TimeInterval = 0
    @Published var texto = ""          // já consolidado
    @Published var parcial = ""        // ainda sendo reconhecido
    @Published var niveis: [CGFloat] = []
    @Published var semTranscricao = false

    private let engine = AVAudioEngine()
    private var arquivo: AVAudioFile?
    private(set) var url: URL?
    private let reconhecedor = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var inicio = Date()
    private var acumulado: TimeInterval = 0
    private var encerrando = false
    private var pausadoAudio = false
    private var ultimoReinicio = Date.distantPast

    var textoCompleto: String {
        [texto, parcial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func pedirPermissoes() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        return mic
    }

    func iniciar() throws {
        let sessao = AVAudioSession.sharedInstance()
        try sessao.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try sessao.setActive(true, options: .notifyOthersOnDeactivation)

        let entrada = engine.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        let nome = UUID().uuidString + ".m4a"
        let destino = AppGroup.midia.appendingPathComponent(nome)
        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: formato.sampleRate,
            AVNumberOfChannelsKey: formato.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        arquivo = try AVAudioFile(forWriting: destino, settings: ajustes, commonFormat: formato.commonFormat, interleaved: formato.isInterleaved)
        url = destino

        texto = ""; parcial = ""; niveis = []; tempo = 0; acumulado = 0
        encerrando = false; pausadoAudio = false
        iniciarReconhecimento()

        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
            guard let self, !self.pausadoAudio else { return }
            try? self.arquivo?.write(from: buffer)
            self.pedido?.append(buffer)
            let nivel = Gravador.nivel(buffer)
            DispatchQueue.main.async {
                self.niveis.append(nivel)
                if self.niveis.count > 70 { self.niveis.removeFirst(self.niveis.count - 70) }
            }
        }
        engine.prepare()
        try engine.start()

        gravando = true
        pausado = false
        inicio = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, !self.pausado else { return }
            self.tempo = self.acumulado + Date().timeIntervalSince(self.inicio)
        }
    }

    func alternarPausa() {
        if pausado {
            pausado = false
            pausadoAudio = false
            inicio = Date()
            if tarefa == nil { iniciarReconhecimento() }
        } else {
            pausado = true
            pausadoAudio = true
            acumulado += Date().timeIntervalSince(inicio)
            tempo = acumulado
            consolidar()
            encerrarReconhecimento()
        }
    }

    /// Para tudo e devolve (arquivo, duração, texto).
    func concluir() async -> (URL, TimeInterval, String)? {
        let dur = pausado ? acumulado : acumulado + Date().timeIntervalSince(inicio)
        encerrando = true
        pedido?.endAudio()
        try? await Task.sleep(nanoseconds: 800_000_000) // dá tempo da última frase chegar
        await MainActor.run { self.consolidar() }
        parar()
        guard let url, dur >= 0.8 else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return (url, dur, texto)
    }

    func cancelar() {
        encerrando = true
        parar()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }

    private func parar() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tarefa?.cancel()
        tarefa = nil
        pedido = nil
        arquivo = nil // fecha o arquivo
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.gravando = false; self.pausado = false }
    }

    // MARK: Reconhecimento

    private func iniciarReconhecimento() {
        guard let r = reconhecedor, r.isAvailable, SFSpeechRecognizer.authorizationStatus() == .authorized else {
            semTranscricao = true
            return
        }
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        p.addsPunctuation = true
        if r.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
        pedido = p
        tarefa = r.recognitionTask(with: p) { [weak self] resultado, erro in
            guard let self else { return }
            DispatchQueue.main.async {
                if let resultado {
                    self.parcial = resultado.bestTranscription.formattedString
                }
                let acabou = erro != nil || (resultado?.isFinal ?? false)
                if acabou {
                    self.consolidar()
                    // o reconhecimento encerra sozinho depois de um tempo: reinicia enquanto grava
                    if self.gravando && !self.pausado && !self.encerrando && Date().timeIntervalSince(self.ultimoReinicio) > 1 {
                        self.ultimoReinicio = Date()
                        self.encerrarReconhecimento()
                        self.iniciarReconhecimento()
                    }
                }
            }
        }
    }

    private func encerrarReconhecimento() {
        pedido?.endAudio()
        tarefa?.cancel()
        tarefa = nil
        pedido = nil
    }

    private func consolidar() {
        let p = parcial.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { texto = texto.isEmpty ? p : texto + " " + p }
        parcial = ""
    }

    private static func nivel(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let canal = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        if n == 0 { return 0 }
        var soma: Float = 0
        for i in 0..<n { soma += canal[i] * canal[i] }
        let rms = sqrt(soma / Float(n))
        return CGFloat(min(1, rms * 6))
    }

    // MARK: Transcrever arquivo (ex.: áudio encaminhado do WhatsApp)

    static func transcrever(_ url: URL) async throws -> String {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR")), r.isAvailable else {
            throw ErroServico(mensagem: "Reconhecimento de voz indisponível")
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized { _ = await pedirPermissoes() }
        let p = SFSpeechURLRecognitionRequest(url: url)
        p.shouldReportPartialResults = false
        p.addsPunctuation = true
        if r.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
        final class Marca: @unchecked Sendable { var respondeu = false }
        let marca = Marca()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            r.recognitionTask(with: p) { resultado, erro in
                if marca.respondeu { return }
                if let erro {
                    marca.respondeu = true
                    c.resume(throwing: ErroServico(mensagem: "Não consegui transcrever este áudio (\(erro.localizedDescription))"))
                } else if let resultado, resultado.isFinal {
                    marca.respondeu = true
                    c.resume(returning: resultado.bestTranscription.formattedString)
                }
            }
        }
    }
}

/// Toca os áudios das observações.
final class Tocador: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Tocador()
    @Published var tocando: String? = nil
    private var player: AVAudioPlayer?

    func alternar(_ arquivo: String) {
        if tocando == arquivo { parar(); return }
        parar()
        let url = AppGroup.midia.appendingPathComponent(arquivo)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            tocando = arquivo
        } catch {
            Avisos.shared.mostrar("Não consegui tocar este áudio", erro: true)
        }
    }

    func parar() {
        player?.stop()
        player = nil
        tocando = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.tocando = nil }
    }
}
