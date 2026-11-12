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
        // Sans fichier .log, tail -f s’arrête aussitôt : on l’explique au lieu de laisser un écran vide.
        if step.isStream, let problem = Self.streamProblem() {
            states[id] = StepState(output: problem, running: false, lastRun: Date())
            completion?()
            return
        }
        states[id] = StepState(output: "", running: true, lastRun: Date())
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
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                DispatchQueue.main.async { self?.finish(id) }
            } else {
                let text = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { self?.append(id, text) }
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

    /// Raison pour laquelle le suivi temps réel ne peut pas démarrer, ou nil si tout est prêt.
    private static func streamProblem() -> String? {
        let dir = NSHomeDirectory() + "/Library/Logs/OneDrive"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return """
                Suivi impossible : le dossier ~/Library/Logs/OneDrive n’existe pas.

                OneDrive n’a encore écrit aucun journal sur ce Mac. Lancez OneDrive, connectez-vous \
                à votre compte, laissez une synchronisation se faire, puis redémarrez le suivi.

                """
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard files.contains(where: { $0.lowercased().hasSuffix(".log") }) else {
            return """
                Suivi impossible : aucun fichier .log dans ~/Library/Logs/OneDrive.

                La commande suit uniquement les fichiers *.log placés à la racine de ce dossier. \
                Le dossier contient \(files.count) élément(s), mais aucun dans ce format.

                """
        }
        return nil
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

    var hasResults: Bool { states.values.contains { $0.lastRun != nil } }

    func report() -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .medium
        df.locale = Locale(identifier: "fr_FR")
        var out = "DoctorOneDrive — rapport de diagnostic\n"
        out += "Date : \(df.string(from: Date()))\n"
        out += "macOS : \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
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
