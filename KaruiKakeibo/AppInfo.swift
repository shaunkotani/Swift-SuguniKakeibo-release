import Foundation

struct AppInfo {
    /// 表示用バージョン (例: "2.0.0")
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    /// ビルド番号 (例: "15")
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}
