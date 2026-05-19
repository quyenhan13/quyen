import Foundation

enum TrollStoreRuntime {
    static var privateFloatingServicesAvailable: Bool {
        hasClass("FBSSystemService") || hasClass("FBSceneManager") || hasClass("RBSProcessIdentity")
    }

    static var diagnosticSummary: String {
        let services = [
            "FBSSystemService": hasClass("FBSSystemService"),
            "FBSceneManager": hasClass("FBSceneManager"),
            "LSApplicationWorkspace": hasClass("LSApplicationWorkspace"),
            "RBSProcessIdentity": hasClass("RBSProcessIdentity")
        ]

        return services
            .map { "\($0.key)=\($0.value ? "yes" : "no")" }
            .sorted()
            .joined(separator: ", ")
    }

    private static func hasClass(_ name: String) -> Bool {
        NSClassFromString(name) != nil
    }
}
