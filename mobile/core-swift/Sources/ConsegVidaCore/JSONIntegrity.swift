import Foundation

/// JSONDecoder accepts duplicate object keys. Reject them before decoding state.
enum JSONIntegrity {
    static func validate(_ data: Data, onlyIntegerNumbers: Bool = false) throws {
        var parser = Parser(bytes: Array(data), onlyIntegerNumbers: onlyIntegerNumbers)
        try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw ConsegVidaError.invalidJSON }
    }

    private struct Parser {
        let bytes: [UInt8]
        let onlyIntegerNumbers: Bool
        var index = 0
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func whitespace() {
            while let byte = current, byte == 32 || byte == 9 || byte == 10 || byte == 13 { index += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            whitespace()
            guard current == byte else { throw ConsegVidaError.invalidJSON }
            index += 1
        }

        mutating func value(depth: Int) throws {
            guard depth <= 32 else { throw ConsegVidaError.invalidJSON }
            whitespace()
            guard let first = current else { throw ConsegVidaError.invalidJSON }
            switch first {
            case 123: try object(depth: depth + 1)
            case 91: try array(depth: depth + 1)
            case 34: _ = try string()
            case 116: try literal(Array("true".utf8))
            case 102: try literal(Array("false".utf8))
            case 110: try literal(Array("null".utf8))
            case 45, 48...57: try number()
            default: throw ConsegVidaError.invalidJSON
            }
        }

        mutating func literal(_ expected: [UInt8]) throws {
            guard index + expected.count <= bytes.count,
                  Array(bytes[index..<(index + expected.count)]) == expected else { throw ConsegVidaError.invalidJSON }
            index += expected.count
        }

        mutating func object(depth: Int) throws {
            try expect(123)
            whitespace()
            if current == 125 { index += 1; return }
            var keys = Set<String>()
            while true {
                whitespace()
                let key = try string()
                guard keys.insert(key).inserted else { throw ConsegVidaError.duplicateJSONKey(key) }
                try expect(58)
                try value(depth: depth)
                whitespace()
                if current == 125 { index += 1; return }
                try expect(44)
            }
        }

        mutating func array(depth: Int) throws {
            try expect(91)
            whitespace()
            if current == 93 { index += 1; return }
            while true {
                try value(depth: depth)
                whitespace()
                if current == 93 { index += 1; return }
                try expect(44)
            }
        }

        mutating func string() throws -> String {
            guard current == 34 else { throw ConsegVidaError.invalidJSON }
            let start = index
            index += 1
            while let byte = current {
                index += 1
                if byte == 34 {
                    do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                    catch { throw ConsegVidaError.invalidJSON }
                }
                if byte == 92 {
                    guard current != nil else { throw ConsegVidaError.invalidJSON }
                    index += 1
                }
            }
            throw ConsegVidaError.invalidJSON
        }

        mutating func number() throws {
            let start = index
            if current == 45 { index += 1 }
            guard let byte = current, (48...57).contains(byte) else { throw ConsegVidaError.invalidJSON }
            if byte == 48 { index += 1 }
            else { while let digit = current, (48...57).contains(digit) { index += 1 } }
            if current == 46 {
                guard !onlyIntegerNumbers else { throw ConsegVidaError.invalidJSON }
                index += 1
                let fractionStart = index
                while let digit = current, (48...57).contains(digit) { index += 1 }
                guard index > fractionStart else { throw ConsegVidaError.invalidJSON }
            }
            if current == 101 || current == 69 {
                guard !onlyIntegerNumbers else { throw ConsegVidaError.invalidJSON }
                index += 1
                if current == 43 || current == 45 { index += 1 }
                let exponentStart = index
                while let digit = current, (48...57).contains(digit) { index += 1 }
                guard index > exponentStart else { throw ConsegVidaError.invalidJSON }
            }
            guard index > start else { throw ConsegVidaError.invalidJSON }
        }
    }
}
