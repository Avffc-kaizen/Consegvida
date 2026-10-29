import Foundation

public enum ConsegVidaError: Error, Equatable, Sendable, LocalizedError {
    case invalidJSON
    case duplicateJSONKey(String)
    case unsupportedVersion(Int)
    case invalidContent
    case invalidDay(String)
    case unknownMission(String)
    case invalidState
    case futureCompletion
    case completionLimit
    case fileTooLarge
    case missionNotActive
    case alreadyCompleted
    case readFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidJSON, .duplicateJSONKey, .invalidState:
            "O progresso salvo não pôde ser lido com segurança. O arquivo foi preservado."
        case .unsupportedVersion:
            "Este progresso pertence a uma versão que o aplicativo ainda não reconhece. O arquivo foi preservado."
        case .invalidContent:
            "O conteúdo do aplicativo não está disponível. Reinstale uma versão verificada."
        case .invalidDay:
            "A data informada é inválida. Confira a data do aparelho."
        case .unknownMission:
            "Esta missão não pertence ao conteúdo desta versão."
        case .futureCompletion:
            "Não é possível registrar uma conclusão no futuro. Confira a data do aparelho."
        case .completionLimit:
            "O limite de registros desta versão foi atingido. Seu progresso foi preservado."
        case .fileTooLarge:
            "O arquivo de progresso excede o tamanho aceito. O arquivo foi preservado."
        case .missionNotActive:
            "Comece esta missão antes de marcá-la como concluída."
        case .alreadyCompleted:
            "Você já concluiu esta missão hoje."
        case .readFailed:
            "Não foi possível ler o progresso neste aparelho. Tente novamente."
        case .writeFailed:
            "Não foi possível salvar a alteração. Seu progresso anterior continua sendo mostrado."
        }
    }
}

public struct Content: Codable, Sendable {
    public let schemaVersion: Int
    public let appName: String
    public let phase: String
    public let tagline: String
    public let introduction: String
    public let manifestoURL: String
    public let horizon: String
    public let privacy: String
    public let colors: [String: String]
    public let axes: [Axis]
    public let missions: [Mission]

    public struct Axis: Codable, Identifiable, Sendable {
        public let id: String
        public let label: String
        public let protects: String
        public let color: String
    }

    public struct Mission: Codable, Identifiable, Sendable {
        public let id: String
        public let axis: String
        public let title: String
        public let minutes: Int
        public let summary: String
        public let steps: [String]
        public let source: String
    }

    public var missionIDs: Set<String> { Set(missions.map(\.id)) }

    public static func decode(_ data: Data) throws -> Content {
        guard data.count <= ProgressCodec.maximumBytes else { throw ConsegVidaError.fileTooLarge }
        try JSONIntegrity.validate(data)
        let content: Content
        do { content = try JSONDecoder().decode(Content.self, from: data) }
        catch { throw ConsegVidaError.invalidContent }
        guard content.schemaVersion == 1 else {
            throw ConsegVidaError.unsupportedVersion(content.schemaVersion)
        }
        let axisIDs = Set(content.axes.map(\.id))
        let requiredMissionIDs: Set<String> = ["fisico-entorno", "mental-foco", "espiritual-presenca"]
        guard content.appName == "ConsegVida",
              axisIDs == Set(["fisico", "mental", "espiritual"]),
              content.axes.count == axisIDs.count,
              content.missionIDs == requiredMissionIDs,
              content.missions.count == requiredMissionIDs.count,
              content.missions.allSatisfy({ axisIDs.contains($0.axis) && !$0.title.isEmpty &&
                  $0.minutes > 0 && !$0.steps.isEmpty && $0.steps.allSatisfy({ !$0.isEmpty }) }),
              let url = URL(string: content.manifestoURL),
              url.scheme == "https", url.host == "www.youtube.com" else {
            throw ConsegVidaError.invalidContent
        }
        return content
    }
}
