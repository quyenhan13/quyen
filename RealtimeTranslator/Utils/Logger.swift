import Foundation

struct Logger {
    enum Level: String {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARNING"
        case error = "🚨 ERROR"
    }

    static func log(_ message: String, level: Level = .info, file: String = #file, line: Int = #line) {
        #if DEBUG
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("\(level.rawValue) [\(filename):\(line)] - \(message)")
        #endif
    }
}
