import AppKit
import Foundation

struct StepState {
    var output = ""
    var running = false
    var lastRun: Date?
}

/// Exécute les commandes dans /bin/zsh et publie leur sortie. Toujours utilisé depuis le thread principal.
final class Runner: ObservableObject {
    @Published var states: [Int: StepState] = [:]
    @Published var fullRunActive = false
    /// Étapes dont le dernier lancement a buté sur un refus d’accès de macOS.
    @Published var denied: Set<Int> = []

    private var procs: [Int: Process] = [:]
    private var completions: [Int: () -> Void] = [:]
    private static let maxOutput = 400_000

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stopAll() }
    }

    func state(_ id: Int) -> StepState { states[id] ?? StepState() }

    func run(_ step: DiagStep, completion: (() -> Void)? = nil) {
        guard procs[step.id] == nil else { return }
        let id = step.id
        // Dossier protégé illisible : on le dit, au lieu de laisser la commande conclure « rien trouvé ».
        var preface = ""
        switch step.needs {
        case .nothing:
            break
        case .logs:
            if let problem = Self.logsProblem(needsLogFiles: step.isStream) {
                if problem.denied { denied.insert(id) } else { denied.remove(id) }
                states[id] = StepState(output: problem.text, running: false, lastRun: Date())
                completion?()
                return
            }
            denied.remove(id)
        case .syncFolders:
            let blocked = Self.unreadableSyncFolders()
            if blocked.isEmpty {
                denied.remove(id)
            } else {
                denied.insert(id)
                preface = "Attention : macOS refuse l’accès à " + blocked.joined(separator: ", ")
                    + ". Le résultat ci-dessous est donc incomplet. Autorisez SyncDoctor dans Réglages Système > "
                    + "Confidentialité et sécurité (Fichiers et dossiers, ou Accès complet au disque), puis relancez.\n\n"
            }
        }
        states[id] = StepState(output: preface, running: true, lastRun: Date())
        completions[id] = completion

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // nonomatch : un motif sans correspondance (*.log) n’interrompt pas la commande.
        p.arguments = ["-o", "nonomatch", "-c", step.command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        // La fin est signalée par l’EOF du tube, donc après la dernière ligne de sortie.
        let decoder = UTF8Chunker()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                let rest = decoder.flush()
                DispatchQueue.main.async {
                    if !rest.isEmpty { self?.append(id, rest) }
                    self?.finish(id)
                }
            } else {
                let text = decoder.feed(data)
                if !text.isEmpty { DispatchQueue.main.async { self?.append(id, text) } }
            }
        }

        do {
            try p.run()
            procs[id] = p
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            append(id, "Impossible de lancer la commande : \(error.localizedDescription)\n")
            finish(id)
        }
    }

    /// Raison pour laquelle les journaux sont illisibles, ou nil si tout est prêt.
    private static func logsProblem(needsLogFiles: Bool) -> (text: String, denied: Bool)? {
        let shown = OneDriveLogs.dir
        let dir = OneDriveLogs.expandedDir
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return ("""
                Le dossier des journaux \(shown) n’existe pas.

                OneDrive n’a encore écrit aucun journal à cet emplacement. Lancez OneDrive, connectez-vous \
                à votre compte, laissez une synchronisation se faire, puis relancez.

                """, false)
        }
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: dir)
        } catch {
            return ("""
                macOS refuse à SyncDoctor l’accès au dossier des journaux \(shown).

                Ce dossier appartient à OneDrive. Pour le lire, ajoutez SyncDoctor dans Réglages Système > \
                Confidentialité et sécurité > Accès complet au disque, puis relancez cette étape. \
                Sans cet accord, cette étape ne peut rien conclure : ce n’est pas un résultat « sans erreur ».

                \(OneDriveLogs.collectNote)

                Détail : \(error.localizedDescription)

                """, true)
        }
        if needsLogFiles, !files.contains(where: { $0.lowercased().hasSuffix(".log") }) {
            return ("""
                Suivi impossible : aucun fichier .log à la racine de \(shown).

                La commande suit uniquement les fichiers *.log placés à la racine de ce dossier. \
                Il contient \(files.count) élément(s), mais aucun dans ce format.

                """, false)
        }
        return nil
    }

    /// Dossiers OneDrive de ~/Library/CloudStorage que macOS ne laisse pas lire.
    private static func unreadableSyncFolders() -> [String] {
        let fm = FileManager.default
        let base = NSHomeDirectory() + "/Library/CloudStorage"
        let names = ((try? fm.contentsOfDirectory(atPath: base)) ?? []).filter { $0.hasPrefix("OneDrive") }
        return names.sorted().filter { (try? fm.contentsOfDirectory(atPath: base + "/" + $0)) == nil }
    }

    func stop(_ id: Int) {
        guard let p = procs[id], p.isRunning else { return }
        // Tue d’abord les enfants du shell (tail), sinon ils survivraient au pipeline.
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-P", String(p.processIdentifier)]
        try? killer.run()
        killer.waitUntilExit()
        p.terminate()
    }

    func stopAll() {
        for id in procs.keys { stop(id) }
    }

    /// Enchaîne toutes les étapes en lecture seule (sans le suivi temps réel ni le redémarrage).
    func runAll() {
        guard !fullRunActive else { return }
        fullRunActive = true
        runNext(Steps.fullRun[...])
    }

    private func runNext(_ remaining: ArraySlice<DiagStep>) {
        guard let step = remaining.first else {
            fullRunActive = false
            return
        }
        if procs[step.id] != nil {
            runNext(remaining.dropFirst())
        } else {
            run(step) { [weak self] in self?.runNext(remaining.dropFirst()) }
        }
    }

    private func append(_ id: Int, _ text: String) {
        var s = state(id)
        s.output += text
        if s.output.count > Self.maxOutput {
            s.output = "… (début tronqué)\n" + String(s.output.suffix(Self.maxOutput / 2))
        }
        states[id] = s
    }

    private func finish(_ id: Int) {
        procs[id] = nil
        var s = state(id)
        s.running = false
        states[id] = s
        completions.removeValue(forKey: id)?()
    }

    // MARK: - Rapport

    /// Vrai dès qu’une étape du diagnostic (et non du guide « Deux versions ») a été exécutée.
    var hasResults: Bool { Steps.all.contains { state($0.id).lastRun != nil } }

    func report() -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .medium
        df.locale = Locale(identifier: "fr_FR")
        var out = "SyncDoctor — rapport de diagnostic\n"
        out += "Date : \(df.string(from: Date()))\n"
        out += "macOS : \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "Dossier des journaux : \(OneDriveLogs.dir)\n"
        for step in Steps.all {
            let s = state(step.id)
            guard s.lastRun != nil else { continue }
            out += "\n──────── \(step.id). \(step.title) ────────\n"
            out += "$ \(step.command)\n"
            let body = s.output.trimmingCharacters(in: .whitespacesAndNewlines)
            out += (body.isEmpty ? "(\(step.emptyHint))" : body) + "\n"
        }
        return out
    }
}

/// Reconstitue du texte UTF-8 à partir de blocs d’octets, sans couper un caractère à cheval sur deux blocs.
final class UTF8Chunker {
    private var pending = Data()

    func feed(_ data: Data) -> String {
        pending.append(data)
        // Un caractère UTF-8 fait au plus 4 octets : on retient jusqu’à 3 octets de fin incomplets.
        for cut in 0...min(3, pending.count) {
            let head = pending.prefix(pending.count - cut)
            if let text = String(data: head, encoding: .utf8) {
                pending = Data(pending.suffix(cut))
                return text
            }
        }
        return flush()
    }

    /// Décode ce qui reste, en remplaçant les octets invalides (sortie binaire).
    func flush() -> String {
        defer { pending = Data() }
        return String(decoding: pending, as: UTF8.self)
    }
}
