import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    static let fundo = Color(hex: 0x0A0614)
    static let cartao = Color(hex: 0x141020)
    static let cartao2 = Color(hex: 0x1B1629)
    static let cartao3 = Color(hex: 0x251E36)
    static let roxo = Color(hex: 0x8B4CF2)
    static let roxoClaro = Color(hex: 0xB18CFF)
    static let texto1 = Color(hex: 0xDDE3EE)
    static let texto2 = Color(hex: 0x8B97A8)
    static let texto3 = Color(hex: 0x5A6577)
    static let verde = Color(hex: 0x22C55E)
    static let ambar = Color(hex: 0xF59E0B)
    static let vermelho = Color(hex: 0xEF4444)
    static let teal = Color(hex: 0x14B8A6)
    static let borda = Color.white.opacity(0.07)
}

struct Chip: View {
    let texto: String
    var cor: Color = .texto2
    var body: some View {
        Text(texto)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(cor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(cor.opacity(0.15), in: Capsule())
    }
}

struct Cartao: ViewModifier {
    var destaque: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(destaque ?? .borda, lineWidth: 1))
    }
}

extension View {
    func cartao(destaque: Color? = nil) -> some View { modifier(Cartao(destaque: destaque)) }
}

struct TituloSecao: View {
    let texto: String
    var cor: Color = .texto2
    var contador: Int? = nil
    var body: some View {
        HStack {
            Text(texto.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(cor)
            Spacer()
            if let contador { Text("\(contador)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.texto3) }
        }
    }
}

struct BotaoPrincipal: ButtonStyle {
    var cor: Color = .roxo
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(cor.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum Formato {
    static func lembrete(_ d: Date) -> String {
        let cal = Calendar.current
        let fh = DateFormatter()
        fh.dateFormat = "HH:mm"
        let h = fh.string(from: d)
        if cal.isDateInToday(d) { return "Hoje \(h)" }
        if cal.isDateInTomorrow(d) { return "Amanhã \(h)" }
        if cal.isDateInYesterday(d) { return "Ontem \(h)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE dd/MM HH:mm"
        return f.string(from: d)
    }

    static func relativo(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        if Calendar.current.isDateInToday(d) { return "há \(Int(s / 3600))h" }
        if Calendar.current.isDateInYesterday(d) { return "ontem" }
        let dias = Int(s / 86400)
        if dias < 7 { return "há \(dias) dias" }
        return data(d)
    }

    static func data(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }

    static func duracao(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
