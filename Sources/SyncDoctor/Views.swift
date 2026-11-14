import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case step(Int)
    case advice
    case fullDisk
    case dualInstall
    case reset
}

struct ContentView: View {
    @EnvironmentObject var runner: Runner
    @State private var selection: SidebarItem? = DebugSnapshot.initialSelection

    var body: some View {
        splitView.onAppear {
            DebugSnapshot.captureIfRequested(runner: runner)
            if DebugSnapshot.autoRunAll { runner.runAll() }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SidebarLabel(title: "Vue d’ensemble", symbol: "stethoscope", tint: Theme.brand)
                    .tag(SidebarItem.overview)
                Section("Diagnostic") {
                    ForEach(Steps.all) { step in
                        HStack {
                            SidebarLabel(title: "\(step.id). \(step.title)", symbol: step.symbol, tint: step.tint)
                            Spacer()
                            StatusDot(state: runner.state(step.id))
                        }
                        .tag(SidebarItem.step(step.id))
                    }
                }
                Section("Aide") {
                    SidebarLabel(title: "Conseils", symbol: "checklist", tint: .blue)
                        .tag(SidebarItem.advice)
                    SidebarLabel(title: "Accès complet au disque", symbol: "lock.shield", tint: .green)
                        .tag(SidebarItem.fullDisk)
                    SidebarLabel(title: "Deux versions de OneDrive", symbol: "square.on.square.dashed", tint: .orange)
                        .tag(SidebarItem.dualInstall)
                    SidebarLabel(title: "Reset OneDrive", symbol: "exclamationmark.arrow.circlepath", tint: .red)
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
            case .fullDisk:
                FullDiskView()
            case .dualInstall:
                DualInstallView()
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
    @State private var status = SystemStatus.read()

    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let cardColumns = [GridItem(.adaptive(minimum: 280), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if status.installs.count > 1 {
                    Button {
                        selection = .dualInstall
                    } label: {
                        Callout(
                            symbol: "square.on.square.dashed", tint: .red,
                            text: "\(status.installs.count) installations de OneDrive détectées sur ce Mac. D’après Microsoft, une seule doit être installée à la fois, sous peine de problèmes de synchronisation : voir « Deux versions de OneDrive ».")
                    }
                    .buttonStyle(.plain)
                }

                if status.installs.isEmpty {
                    Callout(
                        symbol: "questionmark.app", tint: .orange,
                        text: "OneDrive est introuvable dans /Applications et ~/Applications. Les résultats seront vides tant que OneDrive n’est pas installé.")
                }

                sectionTitle("État du Mac", symbol: "gauge.with.dots.needle.50percent")
                LazyVGrid(columns: tileColumns, spacing: 12) {
                    StatTile(
                        symbol: status.isRunning ? "bolt.heart.fill" : "bolt.slash.fill",
                        tint: status.isRunning ? .green : .red,
                        title: "OneDrive",
                        value: status.isRunning ? "Lancé" : "Arrêté",
                        detail: status.isRunning ? "Processus en cours." : "OneDrive n’est pas lancé.")
                    StatTile(
                        symbol: "number", tint: Theme.brand,
                        title: "Version",
                        value: status.installs.first?.version ?? "Absent",
                        detail: versionDetail)
                    StatTile(
                        symbol: "internaldrive.fill", tint: diskTint,
                        title: "Espace libre",
                        value: status.freeText,
                        detail: diskDetail)
                    Button {
                        selection = .fullDisk
                    } label: {
                        StatTile(
                            symbol: status.fullDiskAccess ? "lock.open.fill" : "lock.fill",
                            tint: status.fullDiskAccess ? .green : .orange,
                            title: "Accès au disque",
                            value: status.fullDiskAccess ? "Accordé" : "Non accordé",
                            detail: status.fullDiskAccess
                                ? "Journaux lisibles."
                                : "Requis pour les journaux.")
                    }
                    .buttonStyle(.plain)
                }

                sectionTitle("Les \(Steps.all.count) vérifications", symbol: "checklist")
                LazyVGrid(columns: cardColumns, spacing: 12) {
                    ForEach(Steps.all) { step in
                        Button {
                            selection = .step(step.id)
                        } label: {
                            StepCard(
                                step: step, state: runner.state(step.id),
                                denied: runner.denied.contains(step.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Vue d’ensemble")
        .onAppear { status = SystemStatus.read() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SystemStatus.read()
        }
        .onChange(of: runner.fullRunActive) { status = SystemStatus.read() }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(.white)
                Image(systemName: "stethoscope")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .offset(y: 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostic OneDrive / SharePoint")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("Le diagnostic complet enchaîne les vérifications en lecture seule : rien n’est modifié ni supprimé.")
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        runner.runAll()
                    } label: {
                        Label(
                            runner.fullRunActive ? "Diagnostic en cours…" : "Lancer le diagnostic complet",
                            systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.brandDark)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .disabled(runner.fullRunActive)

                    Button {
                        Clipboard.copy(runner.report())
                    } label: {
                        Label("Copier le rapport", systemImage: "doc.on.doc").foregroundStyle(.white)
                    }
                    .disabled(!runner.hasResults)

                    Button {
                        ReportSaver.save(runner.report())
                    } label: {
                        Label("Enregistrer…", systemImage: "square.and.arrow.down").foregroundStyle(.white)
                    }
                    .disabled(!runner.hasResults)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)

                if runner.fullRunActive || runner.hasResults {
                    ProgressView(value: Double(doneCount), total: Double(Steps.fullRun.count)) {
                        Text("\(doneCount) vérifications sur \(Steps.fullRun.count) effectuées")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .tint(.white)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
    }

    /// Étapes du diagnostic complet terminées.
    private var doneCount: Int {
        Steps.fullRun.filter { runner.state($0.id).lastRun != nil && !runner.state($0.id).running }.count
    }

    private var versionDetail: String {
        guard let install = status.installs.first else { return "OneDrive n’est pas installé." }
        return install.fromAppStore ? "Version Mac App Store" : "Version autonome"
    }

    private var diskTint: Color {
        guard let ratio = status.freeRatio else { return .gray }
        return ratio < 0.05 ? .red : ratio < 0.15 ? .orange : .indigo
    }

    private var diskDetail: String {
        "Sur \(status.totalText) au total."
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
                HStack(spacing: 12) {
                    IconBadge(symbol: step.symbol, tint: step.tint, size: 40)
                    Text("\(step.id). \(step.title)").font(.title.bold())
                }
                // Pas de fixedSize ici : hors d’un ScrollView, il fait mesurer la colonne à une
                // hauteur démesurée et pousse tout l’écran hors de la fenêtre.
                Text(step.explanation)
                    .foregroundStyle(.secondary)
            }

            CommandBox(command: step.command)

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
                    .tint(step.tint)
                    .disabled(state.running)
                }

                if state.running {
                    ProgressView().controlSize(.small)
                    Text(step.isStream ? "Suivi en cours…" : "Exécution…")
                        .foregroundStyle(.secondary)
                } else if let lastRun = state.lastRun {
                    // L’heure change à chaque clic : on voit que l’étape a bien été relancée, même si le résultat est identique.
                    Text("Exécuté à \(lastRun.formatted(date: .omitted, time: .standard))")
                        .font(.callout)
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

            // Actions annexes sur leur propre rangée, pour ne pas tronquer les libellés.
            HStack {
                if step.id == 1 {
                    Button {
                        launchOneDrive()
                    } label: {
                        Label("Lancer OneDrive", systemImage: "arrow.up.forward.app")
                    }
                }
                if step.id == 4 {
                    Button {
                        if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: OneDriveLogs.expandedDir) {
                            NSSound.beep()
                        }
                    } label: {
                        Label("Ouvrir le dossier des journaux", systemImage: "folder")
                    }
                }

                if step.id == 4, let script = OneDriveApp.collectLogsScript {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([script])
                    } label: {
                        Label("Afficher CollectLogs.command", systemImage: "shippingbox")
                    }
                }
                if runner.denied.contains(step.id) {
                    Button {
                        FullDiskAccess.openSettings()
                    } label: {
                        Label("Réglages de confidentialité", systemImage: "lock.shield")
                    }
                    Button {
                        FullDiskAccess.relaunchApp()
                    } label: {
                        Label("Quitter et rouvrir", systemImage: "arrow.clockwise")
                    }
                }

            }

            OutputView(step: step, state: state)
        }
        .padding(24)
        .navigationTitle(step.title)
        .onAppear { if DebugSnapshot.autoRun && !DebugSnapshot.autoRunAll { runner.run(step) } }
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
                        .foregroundStyle(step.tint)
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
                                .foregroundStyle(.white.opacity(0.92))
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
        .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
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

                SourceList(sources: Advice.sources)
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Conseils")
    }
}

// MARK: - Deux versions de OneDrive

struct DualInstallView: View {
    @State private var installs = OneDriveApp.installations

    private var detection: (symbol: String, tint: Color, text: String) {
        switch installs.count {
        case 0:
            return ("questionmark.app", .orange, "Aucune installation de OneDrive détectée dans /Applications ni ~/Applications.")
        case 1:
            return ("checkmark.seal.fill", .green, "Une seule installation de OneDrive détectée dans /Applications et ~/Applications.")
        default:
            return ("exclamationmark.triangle.fill", .red, "\(installs.count) installations de OneDrive détectées : n’en gardez qu’une.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deux versions de OneDrive").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DualInstall.intro, id: \.self) { paragraph in
                        Text(paragraph).fixedSize(horizontal: false, vertical: true)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Callout(symbol: detection.symbol, tint: detection.tint, text: detection.text)
                        ForEach(installs) { install in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "app")
                                Text(install.path).font(.system(.callout, design: .monospaced))
                                Text("version \(install.version) — \(install.fromAppStore ? "Mac App Store" : "version autonome")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("Sur ce Mac", systemImage: "desktopcomputer").font(.headline)
                }

                Text("Identifier les versions").font(.title2.bold())
                Text("Commandes d’identification données par Microsoft. Elles ne modifient rien.")
                    .foregroundStyle(.secondary)
                ForEach(Array(DualInstall.identify.enumerated()), id: \.element.id) { index, command in
                    GuideCommandCard(number: index + 1, command: command)
                }

                Text("Corriger : la procédure Microsoft").font(.title2.bold())
                GroupBox {
                    NumberedList(items: DualInstall.officialFix)
                }
                Callout(symbol: "arrow.left.arrow.right", tint: .blue, text: DualInstall.switchNote)

                SourceList(sources: DualInstall.sources)

                Divider()

                Text("Nettoyage manuel dans le Terminal").font(.title2.bold())
                Callout(symbol: "exclamationmark.triangle.fill", tint: .orange, text: DualInstall.manualIntro)

                ForEach(Array(DualInstall.manual.enumerated()), id: \.element.id) { index, command in
                    GuideCommandCard(number: index + 1, command: command)
                    if command.id == 107 {
                        Callout(symbol: "exclamationmark.triangle.fill", tint: .red, text: DualInstall.wildcardWarning)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Deux versions de OneDrive")
        .onAppear { installs = OneDriveApp.installations }
    }
}

struct GuideCommandCard: View {
    @EnvironmentObject var runner: Runner
    let number: Int
    let command: GuideCommand

    private var state: StepState { runner.state(command.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(command.title)").font(.headline)
            Text(command.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CommandBox(command: command.command)

            if command.runnable {
                HStack {
                    Button {
                        runner.run(command.step)
                    } label: {
                        Label(state.lastRun == nil ? "Exécuter" : "Relancer", systemImage: "play.fill")
                    }
                    .disabled(state.running)
                    if state.running { ProgressView().controlSize(.small) }
                }
                if state.lastRun != nil, !state.running {
                    let output = state.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(output.isEmpty ? "Aucun résultat." : output)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.white.opacity(output.isEmpty ? 0.6 : 0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Label(
                    command.danger ? "À copier dans le Terminal — non exécutée par l’app" : "À copier dans le Terminal",
                    systemImage: command.danger ? "exclamationmark.triangle" : "terminal")
                    .font(.callout)
                    .foregroundStyle(command.danger ? .orange : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reset

struct ResetView: View {
    @State private var scripts = OneDriveApp.resetScripts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset OneDrive").font(.largeTitle.bold())

                Callout(
                    symbol: "exclamationmark.triangle.fill", tint: .orange,
                    text: "Dernier recours. La réinitialisation n’est à envisager qu’après avoir épuisé le diagnostic et les conseils. SyncDoctor ne la lance pas à votre place : suivez les étapes ci-dessous, qui sont celles de Microsoft.")

                GroupBox {
                    NumberedList(items: Advice.reset)
                } label: {
                    Label("Procédure", systemImage: "list.number").font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if scripts.isEmpty {
                            Text("Aucun script de réinitialisation trouvé dans une app OneDrive de /Applications ou ~/Applications.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(scripts, id: \.path) { script in
                            HStack(alignment: .firstTextBaseline) {
                                Text(script.path)
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([script])
                                } label: {
                                    Label("Afficher dans le Finder", systemImage: "folder")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    Label("Sur ce Mac", systemImage: "desktopcomputer").font(.headline)
                }

                GroupBox {
                    BulletList(items: Advice.resetNotes, symbol: "info.circle.fill", tint: .blue)
                } label: {
                    Label("À savoir", systemImage: "lightbulb").font(.headline)
                }

                SourceList(sources: Advice.resetSources)
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .navigationTitle("Reset OneDrive")
        .onAppear { scripts = OneDriveApp.resetScripts }
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

/// Liens vers les pages Microsoft dont un écran reprend le contenu.
struct SourceList: View {
    let sources: [Source]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources Microsoft").font(.callout.weight(.semibold))
            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(source.title, destination: url).font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
