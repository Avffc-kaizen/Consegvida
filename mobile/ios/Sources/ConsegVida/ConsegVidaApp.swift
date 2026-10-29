import SwiftUI
import ConsegVidaCore

@main
@MainActor
struct ConsegVidaApp: App {
    @StateObject private var model = JourneyModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let content = model.content {
                    ConsegVidaTabs(content: content)
                        .environmentObject(model)
                } else {
                    ContentUnavailableView(
                        "Conteúdo indisponível",
                        systemImage: "exclamationmark.triangle",
                        description: Text(model.contentError ?? "Não foi possível carregar esta versão.")
                    )
                }
            }
            .tint(Palette.navy)
            .preferredColorScheme(.light)
            .task { model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in model.refresh() }
            .alert("Alteração não salva", isPresented: Binding(
                get: { model.actionError != nil },
                set: { if !$0 { model.actionError = nil } }
            )) {
                Button("Entendi", role: .cancel) { model.actionError = nil }
            } message: { Text(model.actionError ?? "Tente novamente.") }
            .confirmationDialog(
                "Apagar todo o progresso deste aparelho?",
                isPresented: $model.confirmsErase,
                titleVisibility: .visible
            ) {
                Button("Apagar progresso", role: .destructive) { model.eraseConfirmed() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("A missão em andamento e todo o histórico serão apagados. Esta ação não pode ser desfeita.")
            }
        }
    }
}

@MainActor
private struct ConsegVidaTabs: View {
    let content: Content

    var body: some View {
        TabView {
            NavigationStack { TodayScreen(content: content) }
                .tabItem { Label("Hoje", systemImage: "sun.max") }
            NavigationStack { MissionsScreen(content: content) }
                .tabItem { Label("Missões", systemImage: "leaf") }
            NavigationStack { JourneyScreen(content: content) }
                .tabItem { Label("Jornada", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            NavigationStack { ManifestoScreen(content: content) }
                .tabItem { Label("Manifesto", systemImage: "book.closed") }
            NavigationStack { PrivacyScreen(content: content) }
                .tabItem { Label("Privacidade", systemImage: "lock.shield") }
        }
    }
}
