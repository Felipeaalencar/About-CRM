import SwiftUI
import UserNotifications

@main
struct AboutInboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    @StateObject private var nav = Navegacao.shared
    @StateObject private var avisos = Avisos.shared
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environmentObject(store)
                .environmentObject(nav)
                .environmentObject(avisos)
                .preferredColorScheme(.dark)
                .tint(.roxo)
                .onChange(of: fase) { _, nova in
                    if nova == .active { receberCompartilhados() }
                }
                .onAppear { receberCompartilhados() }
        }
    }

    private func receberCompartilhados() {
        if let d = store.processarFila() {
            Avisos.shared.mostrar("Recebido do WhatsApp ✓")
            nav.abrir(d.id)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["id"] as? String {
            Navegacao.shared.abrir(id)
        }
        completionHandler()
    }
}

struct RaizView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navegacao
    @EnvironmentObject var avisos: Avisos
    @State private var captura = false
    @State private var gravarNovo = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $nav.aba) {
                HojeView(captura: $captura, gravarNovo: $gravarNovo)
                    .tabItem { Label("Hoje", systemImage: "sun.max") }
                    .badge(store.demandas.filter(\.lembreteVencido).count)
                    .tag(0)
                InboxView()
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .badge(store.demandas.filter { $0.status == .novo }.count)
                    .tag(1)
                RelatorioView()
                    .tabItem { Label("Relatório", systemImage: "chart.bar") }
                    .tag(2)
                AjustesView()
                    .tabItem { Label("Ajustes", systemImage: "gearshape") }
                    .tag(3)
            }

            if nav.aba < 2 {
                HStack {
                    Spacer()
                    Button { captura = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(Color.roxo, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .shadow(color: .roxo.opacity(0.5), radius: 14, y: 6)
                    }
                    .accessibilityLabel("Nova demanda")
                    .padding(.trailing, 18)
                    .padding(.bottom, 64)
                }
            }

            if let t = avisos.texto {
                Text(t)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(avisos.erro ? Color.white : Color.fundo)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(avisos.erro ? Color.vermelho : Color.texto1, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 130)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: avisos.texto)
        .sheet(isPresented: $captura) {
            CapturaSheet(gravar: { captura = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { gravarNovo = true } })
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $gravarNovo) {
            GravadorView(demandaId: nil)
        }
        .fullScreenCover(item: $nav.aberta) { item in
            DetalheView(id: item.id)
                .environmentObject(store)
                .environmentObject(avisos)
        }
    }
}
