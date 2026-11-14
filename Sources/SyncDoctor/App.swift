import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct SyncDoctorApp: App {
    @StateObject private var runner = Runner()

    var body: some Scene {
        Window("SyncDoctor", id: "main") {
            ContentView()
                .environmentObject(runner)
                .frame(minWidth: 860, minHeight: 560)
                .tint(Theme.brand)
        }
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("À propos de SyncDoctor") { AboutPanel.show() }
            }
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

enum AboutPanel {
    static let author = "Marc Christiaens"

    static func show() {
        let credits = NSMutableAttributedString(
            string: "Conçu et développé par \(author)\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(
            string: "Diagnostic des synchronisations OneDrive et SharePoint sur Mac.\nApplication indépendante, sans lien avec Microsoft.\n\nOneDrive et SharePoint sont des marques de Microsoft Corporation.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
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

/// Une installation de OneDrive trouvée sur ce Mac.
struct OneDriveInstall: Identifiable {
    let path: String
    let version: String
    let fromAppStore: Bool
    var id: String { path }
}

enum OneDriveApp {
    /// Identifiants indiqués par Microsoft pour distinguer les deux versions.
    static let standaloneID = "com.microsoft.OneDrive"
    static let storeID = "com.microsoft.OneDrive-mac"

    /// Toutes les apps OneDrive de /Applications et ~/Applications, reconnues à leur identifiant de bundle.
    static var installations: [OneDriveInstall] {
        let fm = FileManager.default
        var found: [OneDriveInstall] = []
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for name in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where name.hasSuffix(".app") {
                let path = dir + "/" + name
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier,
                      id == standaloneID || id == storeID else { continue }
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                found.append(OneDriveInstall(path: path, version: version, fromAppStore: id == storeID))
            }
        }
        return found
    }

    /// Première installation de OneDrive trouvée.
    static var url: URL? {
        installations.first.map { URL(fileURLWithPath: $0.path) }
    }

    /// Script de collecte des journaux fourni par Microsoft dans l’app.
    static var collectLogsScript: URL? {
        installations.map { URL(fileURLWithPath: $0.path + "/Contents/Resources/CollectLogs.command") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Scripts de réinitialisation présents dans les apps installées.
    static var resetScripts: [URL] {
        let names = ["ResetOneDriveApp.command", "ResetOneDriveAppStandalone.command"]
        return installations.flatMap { install in
            names.map { URL(fileURLWithPath: install.path + "/Contents/Resources/" + $0) }
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Outil de mise au point : `SD_STEP=6 SD_SNAPSHOT=/chemin.png` ouvre l’étape voulue,
/// enregistre une image de la fenêtre puis quitte ; `SD_RUN=1` exécute l’étape avant la capture,
/// `SD_WAIT=<secondes>` règle le délai avant capture et `SD_REPORT=/chemin.txt` enregistre le rapport.
/// Sans ces variables, ne fait rien.
enum DebugSnapshot {
    private static let env = ProcessInfo.processInfo.environment

    static var initialSelection: SidebarItem? {
        guard let raw = env["SD_STEP"] else { return .overview }
        switch raw {
        case "advice": return .advice
        case "reset": return .reset
        case "dual": return .dualInstall
        case "disk": return .fullDisk
        default: return Int(raw).map { .step($0) } ?? .overview
        }
    }

    static var autoRun: Bool { env["SD_SNAPSHOT"] != nil && env["SD_RUN"] != nil }
    /// `SD_RUN=all` lance le diagnostic complet au lieu de la seule étape affichée.
    static var autoRunAll: Bool { env["SD_SNAPSHOT"] != nil && env["SD_RUN"] == "all" }

    static func captureIfRequested(runner: Runner) {
        guard let path = env["SD_SNAPSHOT"] else { return }
        // La capture ne dessine pas le fond de la fenêtre : en mode sombre le texte serait blanc sur blanc.
        NSApp.appearance = NSAppearance(named: .aqua)
        let wait = Double(env["SD_WAIT"] ?? "") ?? 2
        // SD_SIZE=largeurxhauteur : taille de la fenêtre pour la capture.
        if let size = env["SD_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.windows.first(where: { $0.isVisible })?
                    .setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        // SD_DEMO=1 : remplace les résultats nominatifs par des données d’exemple, pour des captures publiables.
        if env["SD_DEMO"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(wait - 1, 0.5)) {
                for (id, output) in DemoData.outputs {
                    runner.states[id] = StepState(output: output, running: false, lastRun: Date())
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
            if let reportPath = env["SD_REPORT"] {
                var text = runner.report()
                for id in 100..<300 where runner.state(id).lastRun != nil {
                    text += "\n[guide \(id)]\n\(runner.state(id).output)"
                }
                try? text.write(toFile: reportPath, atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }
}

/// Résultats fictifs des étapes qui affichent des noms de compte ou de fichiers (mode SD_DEMO).
enum DemoData {
    private static let root = "/Users/camille/Library/CloudStorage"

    static let outputs: [Int: String] = [
        1: "1432 /Applications/OneDrive.app/Contents/MacOS/OneDrive\n",
        10: """
            OneDrive-Personnel : 1248 éléments
              dont 96 dossiers et sous-dossiers, sur 5 niveaux au plus
            OneDrive-Exemple-SARL : 18432 éléments
              dont 2107 dossiers et sous-dossiers, sur 9 niveaux au plus
            OneDrive-BibliothèquesPartagées-Exemple-SARL : 41876 éléments
              dont 5320 dossiers et sous-dossiers, sur 12 niveaux au plus
            Total : 61556 éléments (recommandation Microsoft : 300 000 au plus)

            """,
        11: """
            [chemin : 428 > 400] \(root)/OneDrive-Exemple-SARL/Clients/2026/Dossiers en cours/Société Dupont et Fils/Contrats et avenants/Version signée/Annexes techniques et financières/Compte rendu de la réunion de lancement du projet de migration.docx
            [chemin : 411 > 400] \(root)/OneDrive-Exemple-SARL/Clients/2026/Dossiers en cours/Société Dupont et Fils/Contrats et avenants/Version signée/Annexes techniques et financières/Planning prévisionnel détaillé.xlsx
            2 élément(s) hors limites. Plus long nom : 74 caractères.

            Les 10 chemins les plus longs (longueur dans OneDrive, puis chemin) :
             428  \(root)/OneDrive-Exemple-SARL/Clients/2026/Dossiers en cours/Société Dupont et Fils/Contrats et avenants/Version signée/Annexes techniques et financières/Compte rendu de la réunion de lancement du projet de migration.docx
             411  \(root)/OneDrive-Exemple-SARL/Clients/2026/Dossiers en cours/Société Dupont et Fils/Contrats et avenants/Version signée/Annexes techniques et financières/Planning prévisionnel détaillé.xlsx
             236  \(root)/OneDrive-Exemple-SARL/Administratif/Ressources humaines/Recrutements/Candidatures reçues.xlsx
             198  \(root)/OneDrive-Exemple-SARL/Projets/Site web/Maquettes/Page d’accueil v3.fig
             174  \(root)/OneDrive-Personnel/Documents/Impôts/2025/Justificatifs.pdf

            """,
        12: """
            drwx------@  9 camille  staff   288 12 nov 08:41 \(root)/OneDrive-BibliothèquesPartagées-Exemple-SARL
            drwx------@ 42 camille  staff  1344 14 nov 17:05 \(root)/OneDrive-Exemple-SARL
            drwx------@ 11 camille  staff   352 10 nov 21:30 \(root)/OneDrive-Personnel

            """,
    ]
}
