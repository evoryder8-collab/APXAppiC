import Foundation

enum APEXConfiguration {
    static var supabaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value)
        else { return nil }
        return url
    }

    static var supabaseKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !value.isEmpty,
              !value.contains("$(")
        else { return nil }
        return value
    }
}
