import AppKit
import SwiftUI

/// Couleurs et styles communs de l’interface.
enum Theme {
    static let brand = Color(red: 0.07, green: 0.42, blue: 0.87)
    static let brandLight = Color(red: 0.20, green: 0.62, blue: 0.98)
    static let brandDark = Color(red: 0.03, green: 0.24, blue: 0.62)
    static let heroGradient = LinearGradient(
        colors: [brandLight, brand, brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Fond des blocs « Terminal ».
    static let terminal = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let prompt = Color(red: 0.36, green: 0.85, blue: 0.52)
}

extension DiagStep {
    /// Couleur de l’étape, par famille : état, journaux, fichiers, SharePoint, action.
    var tint: Color {
        switch id {
        case 1: return .green
        case 2: return Theme.brand
        case 3: return .indigo
        case 4: return .orange
        case 5: return .red
        case 6: return .pink
        case 7: return .purple
        case 8: return .teal
        case 9: return .brown
        case 10: return .yellow
        case 11: return Color(red: 0.85, green: 0.35, blue: 0.55)
        case 12: return .cyan
        case 13: return .mint
        default: return .gray
        }
    }
}

/// Pictogramme blanc sur pastille de couleur.
struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Ligne de barre latérale avec pastille colorée.
struct SidebarLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            IconBadge(symbol: symbol, tint: tint, size: 22)
        }
    }
}

/// Bloc sombre façon Terminal affichant une commande, avec bouton de copie.
struct CommandBox: View {
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("$").foregroundStyle(Theme.prompt)
            Text(command)
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Clipboard.copy(command)
            } label: {
                Image(systemName: "doc.on.doc").foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help("Copier la commande")
        }
        .font(.system(.callout, design: .monospaced))
        .padding(12)
        .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// État du Mac lu directement, sans lancer de commande.
struct SystemStatus {
    let installs: [OneDriveInstall]
    let isRunning: Bool
    let freeBytes: Int64?
    let totalBytes: Int64?
    let fullDiskAccess: Bool

    static func read() -> SystemStatus {
        let ids = [OneDriveApp.standaloneID, OneDriveApp.storeID]
        let running = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier.map(ids.contains) ?? false
        }
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        return SystemStatus(
            installs: OneDriveApp.installations,
            isRunning: running,
            freeBytes: values?.volumeAvailableCapacity.map(Int64.init),
            totalBytes: values?.volumeTotalCapacity.map(Int64.init),
            fullDiskAccess: FullDiskAccess.isGranted)
    }

    var freeText: String {
        guard let freeBytes else { return "Inconnu" }
        return ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }

    var totalText: String {
        guard let totalBytes else { return "inconnue" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Part du disque encore libre, entre 0 et 1.
    var freeRatio: Double? {
        guard let freeBytes, let totalBytes, totalBytes > 0 else { return nil }
        return Double(freeBytes) / Double(totalBytes)
    }
}

enum FullDiskAccess {
    /// Vrai si macOS laisse SyncDoctor lire un fichier réservé aux apps ayant l’accès complet au disque.
    static var isGranted: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }

    /// Rouvre l’app puis quitte l’instance en cours, pour que macOS applique une autorisation fraîchement donnée.
    static func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Ouvre Réglages Système > Confidentialité et sécurité > Accès complet au disque.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Tuile d’état de la vue d’ensemble.
struct StatTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconBadge(symbol: symbol, tint: tint, size: 30)
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(tint.gradient)
                .frame(height: 4)
        }
    }
}

/// Carte d’une étape dans la grille de la vue d’ensemble.
struct StepCard: View {
    let step: DiagStep
    let state: StepState
    let denied: Bool

    private var summary: String {
        if state.running { return "En cours…" }
        guard state.lastRun != nil else {
            return step.inFullRun ? "Pas encore exécuté" : "À lancer manuellement"
        }
        if denied { return "Accès refusé par macOS" }
        let lines = state.output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let first = lines.first else { return step.emptyHint }
        return lines.count > 1 ? "\(lines.count) lignes — \(first)" : String(first)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: step.symbol, tint: step.tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(step.id). \(step.title)")
                    .font(.headline)
                    .lineLimit(1)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(denied ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if state.running {
                ProgressView().controlSize(.small)
            } else if denied {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
            } else if state.lastRun != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Accès complet au disque

struct FullDiskView: View {
    @State private var granted = FullDiskAccess.isGranted
    @State private var oneDrive = OneDriveApp.url

    private let steps = [
        "Cliquer sur « Ouvrir Accès complet au disque » ci-dessus : Réglages Système s’ouvre sur la bonne page.",
        "Cliquer sur le bouton « + » en bas de la liste, s’authentifier, puis choisir l’application à ajouter. On peut aussi glisser l’application dans la liste depuis le Finder : les boutons « Afficher dans le Finder » ci-dessus la sélectionnent pour vous.",
        "Vérifier que l’interrupteur de l’application est activé.",
        "Quitter puis rouvrir l’application concernée : l’autorisation n’est prise en compte qu’au lancement suivant. Pour SyncDoctor, le bouton « Quitter et rouvrir SyncDoctor » ci-dessus le fait pour vous.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Accès complet au disque").font(.largeTitle.bold())

                Text("macOS protège certains dossiers : une application ne peut les lire qu’avec votre accord, donné dans Réglages Système > Confidentialité et sécurité > Accès complet au disque. Cet accord se donne application par application, et vous seul pouvez le donner.")
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    FullDiskAccess.openSettings()
                } label: {
                    Label("Ouvrir Accès complet au disque", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Callout(
                            symbol: granted ? "checkmark.seal.fill" : "lock.fill",
                            tint: granted ? .green : .orange,
                            text: granted
                                ? "SyncDoctor dispose de l’accès complet au disque."
                                : "SyncDoctor n’a pas l’accès complet au disque.")
                        Text("Utilité : lire le dossier des journaux de OneDrive (étapes 4, 5, 6 et 13). Pour la version Mac App Store, ce dossier se trouve dans le conteneur de OneDrive, que macOS réserve à OneDrive.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Copie en cours d’exécution, à ajouter dans la liste : \(Bundle.main.bundlePath)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                            } label: {
                                Label("Afficher SyncDoctor dans le Finder", systemImage: "folder")
                            }
                            Button {
                                FullDiskAccess.relaunchApp()
                            } label: {
                                Label("Quitter et rouvrir SyncDoctor", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("SyncDoctor", systemImage: "stethoscope").font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Utilité : d’après Microsoft, si les dossiers Bureau et Documents ne sont pas sauvegardés, il faut utiliser la version autonome de OneDrive et lui accorder l’accès complet au disque.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("SyncDoctor ne peut pas savoir si OneDrive dispose déjà de cet accès : vérifiez sa présence dans la liste de Réglages Système.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let oneDrive { NSWorkspace.shared.activateFileViewerSelecting([oneDrive]) }
                        } label: {
                            Label("Afficher OneDrive dans le Finder", systemImage: "folder")
                        }
                        .disabled(oneDrive == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("OneDrive", systemImage: "cloud").font(.headline)
                }

                GroupBox {
                    NumberedList(items: steps)
                } label: {
                    Label("Marche à suivre", systemImage: "list.number").font(.headline)
                }

                SourceList(sources: [Sources.fixSync])
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Accès complet au disque")
        .onAppear {
            granted = FullDiskAccess.isGranted
            oneDrive = OneDriveApp.url
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = FullDiskAccess.isGranted
        }
    }
}
