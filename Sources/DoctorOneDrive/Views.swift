import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case step(Int)
    case advice
    case reset
}

struct ContentView: View {
    @EnvironmentObject var runner: Runner
    @State private var selection: SidebarItem? = DebugSnapshot.initialSelection

    var body: some View {
        splitView.onAppear { DebugSnapshot.captureIfRequested() }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Vue d’ensemble", systemImage: "stethoscope")
                    .tag(SidebarItem.overview)
                Section("Diagnostic") {
                    ForEach(Steps.all) { step in
                        HStack {
                            Label("\(step.id). \(step.title)", systemImage: step.symbol)
                            Spacer()
                            StatusDot(state: runner.state(step.id))
                        }
                        .tag(SidebarItem.step(step.id))
                    }
                }
                Section("Aide") {
                    Label("Conseils", systemImage: "checklist")
                        .tag(SidebarItem.advice)
                    Label("Reset OneDrive", systemImage: "exclamationmark.arrow.circlepath")
                        .tag(SidebarItem.reset)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(selection: $selection)
            case .step(let id):
                if let step = Steps.all.first(where: { $0.id == id }) {
                    StepView(step: step).id(id)
                }
            case .advice:
                AdviceView()
            case .reset:
                ResetView()
            }
        }
    }
}

struct StatusDot: View {
    let state: StepState

    var body: some View {
        if state.running {
            ProgressView().controlSize(.small)
        } else if state.lastRun != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

// MARK: - Vue d’ensemble

struct OverviewView: View {
    @EnvironmentObject var runner: Runner
    @Binding var selection: SidebarItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostic OneDrive / SharePoint")
                        .font(.largeTitle.bold())
                    Text("Affinez le diagnostic des synchronisations OneDrive et SharePoint sur ce Mac. Le diagnostic complet enchaîne les vérifications en lecture seule : rien n’est modifié ni supprimé.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        runner.runAll()
                    } label: {
                        Label(
                            runner.fullRunActive ? "Diagnostic en cours…" : "Lancer le diagnostic complet",
                            systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(runner.fullRunActive)

                    Button {
                        Clipboard.copy(runner.report())
                    } label: {
                        Label("Copier le rapport", systemImage: "doc.on.doc")
                    }
                    .controlSize(.large)
                    .disabled(!runner.hasResults)

                    Button {
                        ReportSaver.save(runner.report())
                    } label: {
                        Label("Enregistrer…", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.large)
                    .disabled(!runner.hasResults)
                }

                if OneDriveApp.url == nil {
                    Callout(
                        symbol: "questionmark.app", tint: .orange,
                        text: "OneDrive.app est introuvable dans /Applications et ~/Applications. Les résultats seront vides tant que OneDrive n’est pas installé.")
                }

                VStack(spacing: 0) {
                    ForEach(Steps.all) { step in
                        Button {
                            selection = .step(step.id)
                        } label: {
                            OverviewRow(step: step, state: runner.state(step.id))
                        }
                        .buttonStyle(.plain)
                        if step.id != Steps.all.last?.id { Divider() }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Vue d’ensemble")
    }
}

struct OverviewRow: View {
    let step: DiagStep
    let state: StepState

    private var summary: String {
        if state.running { return "En cours…" }
        guard state.lastRun != nil else {
            return step.inFullRun ? "Pas encore exécuté" : "À lancer manuellement"
        }
        let lines = state.output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let first = lines.first else { return step.emptyHint }
        return lines.count > 1 ? "\(lines.count) lignes — \(first)" : String(first)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.id). \(step.title)").fontWeight(.medium)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            StatusDot(state: state)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Étape

struct StepView: View {
    @EnvironmentObject var runner: Runner
    let step: DiagStep
    @State private var confirming = false

    private var state: StepState { runner.state(step.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(step.id). \(step.title)", systemImage: step.symbol)
                    .font(.title.bold())
                // Pas de fixedSize ici : hors d’un ScrollView, il fait mesurer la colonne à une
                // hauteur démesurée et pousse tout l’écran hors de la fenêtre.
                Text(step.explanation)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top) {
                Text(step.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Clipboard.copy(step.command)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier la commande")
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                if state.running && step.isStream {
                    Button(role: .destructive) {
                        runner.stop(step.id)
                    } label: {
                        Label("Arrêter", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        if step.needsConfirm { confirming = true } else { runner.run(step) }
                    } label: {
                        Label(runLabel, systemImage: step.isStream ? "record.circle" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.running)
                }

                if step.id == 1 {
                    Button {
                        launchOneDrive()
                    } label: {
                        Label("Lancer OneDrive", systemImage: "arrow.up.forward.app")
                    }
                }
                if step.id == 4 {
                    Button {
                        let path = NSHomeDirectory() + "/Library/Logs/OneDrive"
                        if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) { NSSound.beep() }
                    } label: {
                        Label("Ouvrir le dossier des journaux", systemImage: "folder")
                    }
                }

                if state.running {
                    ProgressView().controlSize(.small)
                    Text(step.isStream ? "Suivi en cours…" : "Exécution…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Clipboard.copy(state.output)
                } label: {
                    Label("Copier le résultat", systemImage: "doc.on.clipboard")
                }
                .disabled(state.output.isEmpty)
            }

            OutputView(step: step, state: state)
        }
        .padding(24)
        .navigationTitle(step.title)
        .onAppear { if DebugSnapshot.autoRun { runner.run(step) } }
        .confirmationDialog("Redémarrer OneDrive ?", isPresented: $confirming) {
            Button("Redémarrer OneDrive") { runner.run(step) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("OneDrive sera quitté puis relancé après 5 secondes. Les synchronisations en cours reprendront au redémarrage.")
        }
    }

    private var runLabel: String {
        if step.isStream { return "Démarrer le suivi" }
        return state.lastRun == nil ? "Exécuter" : "Relancer"
    }

    private func launchOneDrive() {
        guard let url = OneDriveApp.url else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { runner.run(step) }
        }
    }
}

struct OutputView: View {
    let step: DiagStep
    let state: StepState

    /// Message central affiché tant qu’il n’y a aucune sortie.
    private var placeholder: (symbol: String, title: String, detail: String) {
        if state.running {
            return step.isStream
                ? ("waveform.path.ecg", "Suivi en cours — aucune erreur pour l’instant",
                   "Déclenchez une synchronisation ou modifiez un fichier test. Les erreurs apparaîtront ici.")
                : ("hourglass", "Exécution en cours…", "")
        }
        if state.lastRun == nil {
            return step.isStream
                ? ("record.circle", "Suivi arrêté", "Cliquez sur « Démarrer le suivi » pour afficher les erreurs en direct.")
                : ("play.circle", "Pas encore exécuté", "Cliquez sur « Exécuter » pour afficher le résultat.")
        }
        return ("checkmark.circle", step.emptyHint, "La commande n’a renvoyé aucune ligne.")
    }

    var body: some View {
        Group {
            if state.output.isEmpty {
                Color.clear.overlay { VStack(spacing: 10) {
                    Image(systemName: placeholder.symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(placeholder.title)
                        .font(.title3.weight(.semibold))
                    if !placeholder.detail.isEmpty {
                        Text(placeholder.detail)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.output)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                    .onChange(of: state.output) {
                        if step.isStream { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Conseils

struct AdviceView: View {
    @State private var done: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Conseils").font(.largeTitle.bold())

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(Advice.todo.enumerated()), id: \.offset) { index, item in
                            Toggle(isOn: Binding(
                                get: { done.contains(index) },
                                set: { if $0 { done.insert(index) } else { done.remove(index) } }
                            )) {
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("À faire", systemImage: "checkmark.circle").font(.headline)
                }

                GroupBox {
                    BulletList(items: Advice.dont, symbol: "xmark.circle.fill", tint: .red)
                } label: {
                    Label("À ne pas faire", systemImage: "hand.raised").font(.headline)
                }

                GroupBox {
                    NumberedList(items: Advice.persist)
                } label: {
                    Label("Si le problème persiste", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                }

                GroupBox {
                    BulletList(items: Advice.notes, symbol: "info.circle.fill", tint: .blue)
                } label: {
                    Label("Bon à savoir", systemImage: "lightbulb").font(.headline)
                }
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Conseils")
    }
}

// MARK: - Reset

struct ResetView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset OneDrive").font(.largeTitle.bold())

                Callout(
                    symbol: "exclamationmark.triangle.fill", tint: .orange,
                    text: "Dernier recours. La réinitialisation n’est à envisager qu’après avoir épuisé le diagnostic et les conseils. DoctorOneDrive ne la lance pas à votre place : suivez les étapes ci-dessous.")

                GroupBox {
                    NumberedList(items: Advice.reset)
                } label: {
                    Label("Procédure", systemImage: "list.number").font(.headline)
                }

                Button {
                    revealResources()
                } label: {
                    Label("Afficher Contents/Resources dans le Finder", systemImage: "folder")
                }
                .disabled(OneDriveApp.url == nil)

                if OneDriveApp.url == nil {
                    Text("OneDrive.app est introuvable sur ce Mac.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Reset OneDrive")
    }

    private func revealResources() {
        guard let app = OneDriveApp.url else { return }
        let resources = app.appendingPathComponent("Contents/Resources")
        let names = ["ResetOneDriveApp.command", "ResetOneDriveAppStandalone.command"]
        let script = names.map { resources.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.selectFile(script?.path, inFileViewerRootedAtPath: resources.path)
    }
}

// MARK: - Composants

struct Callout: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BulletList: View {
    let items: [String]
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }
}

struct NumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }
}
