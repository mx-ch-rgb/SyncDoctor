import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct DoctorOneDriveApp: App {
    @StateObject private var runner = Runner()

    var body: some Scene {
        Window("DoctorOneDrive", id: "main") {
            ContentView()
                .environmentObject(runner)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Diagnostic") {
                Button("Lancer le diagnostic complet") { runner.runAll() }
                    .keyboardShortcut("r")
                    .disabled(runner.fullRunActive)
                Button("Copier le rapport") { Clipboard.copy(runner.report()) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!runner.hasResults)
                Button("Enregistrer le rapport…") { ReportSaver.save(runner.report()) }
                    .keyboardShortcut("s")
                    .disabled(!runner.hasResults)
            }
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum ReportSaver {
    static func save(_ text: String) {
        let panel = NSSavePanel()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "Diagnostic-OneDrive-\(df.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

enum OneDriveApp {
    /// Emplacement de OneDrive.app : version autonome, puis Mac App Store.
    static var url: URL? {
        let candidates = [
            "/Applications/OneDrive.app",
            NSHomeDirectory() + "/Applications/OneDrive.app",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}

/// Outil de mise au point : `DOD_STEP=6 DOD_SNAPSHOT=/chemin.png` ouvre l’étape voulue,
/// enregistre une image de la fenêtre puis quitte ; `DOD_RUN=1` exécute l’étape avant la capture.
/// Sans ces variables, ne fait rien.
enum DebugSnapshot {
    private static let env = ProcessInfo.processInfo.environment

    static var initialSelection: SidebarItem? {
        guard let raw = env["DOD_STEP"] else { return .overview }
        switch raw {
        case "advice": return .advice
        case "reset": return .reset
        default: return Int(raw).map { .step($0) } ?? .overview
        }
    }

    static var autoRun: Bool { env["DOD_SNAPSHOT"] != nil && env["DOD_RUN"] != nil }

    static func captureIfRequested() {
        guard let path = env["DOD_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
