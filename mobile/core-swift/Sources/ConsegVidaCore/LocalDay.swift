import Foundation

/// A strict Gregorian calendar date, independent of the user's chosen calendar.
public struct LocalDay: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let bytes = Array(rawValue.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(rawValue.prefix(4)), (1...9999).contains(year),
              let month = Int(rawValue.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(rawValue.suffix(2)) else { return nil }
        let leapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { return nil }
        self.rawValue = rawValue
    }

    public init(validating value: String) throws {
        guard let day = Self(rawValue: value) else { throw ConsegVidaError.invalidDay(value) }
        self = day
    }

    public static func containing(_ date: Date = Date(), timeZone: TimeZone = .current) throws -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day else {
            throw ConsegVidaError.invalidDay("")
        }
        return try Self(validating: String(format: "%04d-%02d-%02d", year, month, day))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        try self.init(validating: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayDate: String {
        let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        let month = Int(rawValue.dropFirst(5).prefix(2))!
        let day = Int(rawValue.suffix(2))!
        return "\(day) de \(months[month - 1]) de \(rawValue.prefix(4))"
    }
}
