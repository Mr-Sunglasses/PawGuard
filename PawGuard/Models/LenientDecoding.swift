import Foundation

/// Decodes persisted values written by an older build.
///
/// Synthesized `Decodable` ignores property defaults: a key the stored JSON
/// lacks is an error, not a default. Every field added to a persisted struct
/// therefore used to make the whole stored value unreadable, and the store
/// silently fell back to a fresh instance — so an upgrade quietly threw away
/// the user's settings, onboarding state included.
///
/// This fills whatever the stored JSON lacks from `fallback` before decoding,
/// so new fields take their defaults and everything already saved survives.
enum LenientDecoding {
    static func decode<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T? {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(T.self, from: data) { return value }

        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fallbackData = try? JSONEncoder().encode(fallback),
            var merged = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any]
        else {
            return nil
        }
        merged.merge(stored) { _, storedValue in storedValue }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? decoder.decode(T.self, from: mergedData)
    }
}
