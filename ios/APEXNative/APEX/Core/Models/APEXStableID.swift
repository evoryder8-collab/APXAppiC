import Foundation

/// Deterministic, user-scoped identifiers shared with the browser client.
/// Keeping this byte-for-byte compatible prevents the native and web clients
/// from creating duplicate daily integration records for the same run.
enum APEXStableID {
    static func scopedUUID(namespace: String, date: String, userID: UUID) -> UUID {
        let input = "\(namespace):\(userID.uuidString.lowercased()):\(date)"
        let seeds: [UInt32] = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
        let raw = seeds.map { hash32(input, seed: $0) }
            .map { String(format: "%08x", $0) }
            .joined()
        return uuid(from: raw)
    }

    static func orbitUUID(userID: UUID, key: String) -> UUID {
        let input = "apex-orbit:\(userID.uuidString.lowercased()):\(key)"
        let seeds: [UInt32] = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
        let raw = seeds.map { hash32(input, seed: $0) }
            .map { String(format: "%08x", $0) }
            .joined()
        return uuid(from: raw)
    }

    private static func hash32(_ value: String, seed: UInt32) -> UInt32 {
        var hash = seed
        for codeUnit in value.utf16 {
            hash ^= UInt32(codeUnit)
            hash = hash &* 16_777_619
        }
        hash ^= hash >> 16
        hash = hash &* 0x7feb352d
        hash ^= hash >> 15
        return hash
    }

    private static func uuid(from raw: String) -> UUID {
        var characters = Array(raw)
        guard characters.count == 32 else { return UUID() }
        characters[12] = "4"
        let variant = ((Int(String(characters[16]), radix: 16) ?? 0) & 0x3) | 0x8
        characters[16] = Character(String(variant, radix: 16))
        let value = String(characters)
        let formatted = "\(value.prefix(8))-\(value.dropFirst(8).prefix(4))-\(value.dropFirst(12).prefix(4))-\(value.dropFirst(16).prefix(4))-\(value.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }
}
