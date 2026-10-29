import SwiftUI
import ConsegVidaCore

enum Palette {
    static let navy = Color(red: 18 / 255, green: 32 / 255, blue: 58 / 255)
    static let cream = Color(red: 243 / 255, green: 239 / 255, blue: 230 / 255)
    static let paper = Color(red: 255 / 255, green: 253 / 255, blue: 248 / 255)
    static let ink = Color(red: 28 / 255, green: 29 / 255, blue: 26 / 255)
    static let muted = Color(red: 92 / 255, green: 100 / 255, blue: 96 / 255)
    static let gold = Color(red: 184 / 255, green: 154 / 255, blue: 91 / 255)
    static func axis(_ id: String) -> Color {
        switch id {
        case "fisico": Color(red: 47 / 255, green: 74 / 255, blue: 60 / 255)
        case "espiritual": Color(red: 107 / 255, green: 90 / 255, blue: 58 / 255)
        default: navy
        }
    }
    static func symbol(_ id: String) -> String {
        switch id {
        case "fisico": "leaf"
        case "espiritual": "sparkle"
        default: "scope"
        }
    }
}

struct PageLayout<Body: View>: View {
    @ViewBuilder let content: Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.cream)
        .foregroundStyle(Palette.ink)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct BrandMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 62
    var body: some View {
        Text("C")
            .font(.system(.largeTitle, design: .serif).italic())
            .foregroundStyle(Palette.cream)
            .frame(width: diameter, height: diameter)
            .background(Palette.navy, in: Circle())
            .overlay(Circle().strokeBorder(Palette.gold, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

struct RecoveryNotice: View {
    @EnvironmentObject private var model: JourneyModel
    var body: some View {
        if let message = model.recoveryMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label("Seu progresso precisa de atenção", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message).font(.subheadline)
                Text("Você pode continuar lendo as missões. Novos registros estão suspensos até a recuperação.")
                    .font(.subheadline)
                Button("Tentar ler novamente") { model.refresh() }
                    .buttonStyle(.borderedProminent)
                Button("Apagar arquivo e recomeçar", role: .destructive) { model.confirmsErase = true }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.gold, lineWidth: 1))
        }
    }
}

struct TodayScreen: View {
    let content: Content
    @EnvironmentObject private var model: JourneyModel

    var body: some View {
        PageLayout {
            HStack(alignment: .top, spacing: 16) {
                BrandMark()
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: content.phase)
                    Text(content.appName).font(.system(.title, design: .serif).weight(.medium))
                    Text(content.tagline).font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(content.introduction)
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .accessibilityAddTraits(.isHeader)
                Text("Escolha uma missão pequena. Faça no seu ritmo. Reconheça o que foi possível hoje.")
                    .font(.body).foregroundStyle(Palette.muted)
            }
            RecoveryNotice()
            if model.isReady, let active = content.missions.first(where: { $0.id == model.state.activeMission }) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Em andamento")
                    NavigationLink { MissionScreen(mission: active, content: content) } label: {
                        HStack {
                            Text(active.title).font(.headline)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                        }
                        .padding(20)
                        .foregroundStyle(Palette.paper)
                        .background(Palette.navy, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Três formas de cuidar")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(content.axes) { axis in
                    if let mission = content.missions.first(where: { $0.axis == axis.id }) {
                        NavigationLink { MissionScreen(mission: mission, content: content) } label: {
                            HStack(alignment: .center, spacing: 16) {
                                Image(systemName: Palette.symbol(axis.id))
                                    .font(.title2).foregroundStyle(Palette.axis(axis.id))
                                    .frame(minWidth: 28).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(axis.label).font(.headline)
                                    Text(axis.protects).font(.subheadline).foregroundStyle(Palette.muted)
                                    Text(model.hasCompleted(mission.id) ? "Concluída hoje" : "\(mission.minutes) min · uma missão")
                                        .font(.caption).foregroundStyle(Palette.axis(axis.id))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: model.hasCompleted(mission.id) ? "checkmark.circle.fill" : "chevron.right")
                                    .foregroundStyle(Palette.axis(axis.id)).accessibilityHidden(true)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("O progresso começa com um gesto possível.")
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(Palette.muted)
                .padding(.vertical, 8)
        }
        .navigationTitle("Hoje")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MissionsScreen: View {
    let content: Content
    var body: some View {
        PageLayout {
            Eyebrow(text: content.phase)
            Text("Uma missão de cada vez.")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Text("Práticas curtas para trazer o manifesto para o seu dia.")
                .foregroundStyle(Palette.muted)
            RecoveryNotice()
            ForEach(content.missions) { mission in
                NavigationLink { MissionScreen(mission: mission, content: content) } label: {
                    MissionCard(mission: mission, content: content)
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Missões")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MissionCard: View {
    let mission: Content.Mission
    let content: Content
    @EnvironmentObject private var model: JourneyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(content.axes.first(where: { $0.id == mission.axis })?.label ?? "Missão", systemImage: Palette.symbol(mission.axis))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.axis(mission.axis))
                Spacer(minLength: 8)
                Text("\(mission.minutes) min").font(.caption).foregroundStyle(Palette.muted)
            }
            Text(mission.title).font(.system(.title2, design: .serif).weight(.medium))
            Text(mission.summary).foregroundStyle(Palette.muted)
            Label(model.hasCompleted(mission.id) ? "Concluída hoje" : "Conhecer a missão", systemImage: model.hasCompleted(mission.id) ? "checkmark.circle" : "arrow.right")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.navy)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MissionScreen: View {
    let mission: Content.Mission
    let content: Content
    @EnvironmentObject private var model: JourneyModel

    var body: some View {
        PageLayout {
            Eyebrow(text: "\(content.axes.first(where: { $0.id == mission.axis })?.label ?? "Missão") · \(mission.minutes) min")
            Text(mission.title)
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Text(mission.summary).foregroundStyle(Palette.muted)
            RecoveryNotice()
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(mission.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(index + 1))
                            .font(.headline).monospacedDigit()
                            .foregroundStyle(Palette.axis(mission.axis))
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(22)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
            if model.hasCompleted(mission.id) {
                Label("Você concluiu esta missão hoje.", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(Palette.axis(mission.axis))
                Text("Seu registro já está em Minha jornada. Você pode voltar amanhã.")
                    .foregroundStyle(Palette.muted)
            } else if model.isReady && model.state.activeMission == mission.id {
                Label("Missão em andamento", systemImage: "circle.dotted")
                    .font(.subheadline.weight(.semibold))
                Button { model.complete(mission.id) } label: {
                    Label("Concluir missão", systemImage: "checkmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Salva uma conclusão para a data de hoje neste aparelho.")
            } else {
                Button { model.start(mission.id) } label: {
                    Text("Começar missão").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.isReady)
                .accessibilityHint("Guarda esta missão como em andamento neste aparelho.")
            }
        }
        .navigationTitle("Sua missão")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct JourneyScreen: View {
    let content: Content
    @EnvironmentObject private var model: JourneyModel
    @State private var visibleRecords = 50

    private var history: [Completion] {
        Array(model.state.completions.sorted {
            $0.completedOn == $1.completedOn ? $0.missionId < $1.missionId : $0.completedOn > $1.completedOn
        }.prefix(visibleRecords))
    }

    var body: some View {
        PageLayout {
            Eyebrow(text: "Minha jornada")
            Text("Pequenos gestos,\nregistros reais.")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            RecoveryNotice()
            if model.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(model.state.completions.count))
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .monospacedDigit()
                    Text(model.state.completions.count == 1 ? "missão concluída" : "missões concluídas")
                        .font(.headline)
                    Text("Cada missão conta uma vez por dia. Este histórico não mede impacto nem compara pessoas.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
                if model.state.completions.isEmpty {
                    ContentUnavailableView("Sua jornada começa hoje", systemImage: "leaf", description: Text("Escolha uma missão e registre um gesto que você realizou."))
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Seu histórico").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        ForEach(history) { completion in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(content.missions.first(where: { $0.id == completion.missionId })?.title ?? "Missão concluída")
                                    .font(.headline)
                                Text(completion.completedOn.displayDate).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                        if visibleRecords < model.state.completions.count {
                            Button("Mostrar mais registros") {
                                visibleRecords = min(visibleRecords + 50, model.state.completions.count)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                Button("Apagar meu progresso", role: .destructive) { model.confirmsErase = true }
                    .buttonStyle(.bordered)
                    .disabled(model.state == .empty)
            }
            Text("O histórico fica somente neste aparelho. Ao apagar o app, trocar de aparelho ou apagar o progresso, esses registros não serão recuperados por uma conta na nuvem.")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
        .navigationTitle("Minha jornada")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.state.completions.count) { _, count in
            if count < visibleRecords { visibleRecords = max(50, count) }
        }
    }
}

struct ManifestoScreen: View {
    let content: Content

    var body: some View {
        PageLayout {
            BrandMark()
            Eyebrow(text: "O que nos move")
            Text(content.tagline)
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Text("Evolução física, mental e espiritual.")
                .font(.title2).foregroundStyle(Palette.navy)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(content.axes) { axis in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(axis.label).font(.headline).foregroundStyle(Palette.axis(axis.id))
                        Text(axis.protects).foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
            Text(content.phase).font(.title2.weight(.semibold))
            Text("O começo é tornar possível um cuidado no lugar onde você está. As missões traduzem essa intenção em práticas simples.")
            Text(content.horizon).font(.subheadline).foregroundStyle(Palette.muted)
            if let url = URL(string: content.manifestoURL) {
                Link(destination: url) {
                    Label("Abrir manifesto no YouTube", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Abre o YouTube fora deste aplicativo.")
                Text("Você sairá do aplicativo. O YouTube tem suas próprias regras de privacidade.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .navigationTitle("Manifesto")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyScreen: View {
    let content: Content

    var body: some View {
        PageLayout {
            Image(systemName: "lock.shield")
                .font(.largeTitle).foregroundStyle(Palette.navy).accessibilityHidden(true)
            Eyebrow(text: "Seus dados")
            Text("Sua jornada\nfica com você.")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Text(content.privacy)
            VStack(alignment: .leading, spacing: 20) {
                Label("Sem cadastro ou conta", systemImage: "person.crop.circle.badge.checkmark")
                Label("Sem anúncios ou rastreadores", systemImage: "hand.raised")
                Label("Progresso guardado neste aparelho", systemImage: "iphone")
                Label("Exclusão disponível em Minha jornada", systemImage: "trash")
            }
            .font(.body)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
            Text("O aplicativo guarda somente o identificador da missão em andamento e as missões concluídas com suas datas. Não há campo de nome, e-mail, saúde ou diário pessoal.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text("Esses registros são excluídos do backup do aplicativo. Não há sincronização entre aparelhos nesta versão.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text("ConsegVida · versão 0.1.0")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
        .navigationTitle("Privacidade")
        .navigationBarTitleDisplayMode(.inline)
    }
}
