import Foundation

/// Une étape de diagnostic = une commande Terminal.
struct DiagStep: Identifiable, Hashable {
    let id: Int
    let title: String
    let symbol: String
    let explanation: String
    let command: String
    /// Message affiché quand la commande ne renvoie rien.
    let emptyHint: String
    /// Commande continue (tail -f) à arrêter manuellement.
    var isStream = false
    /// Demande une confirmation avant exécution.
    var needsConfirm = false
    /// Incluse dans le « diagnostic complet ».
    var inFullRun = true
}

enum Steps {
    static let logs = "~/Library/Logs/OneDrive/"
    static let roots = "~/OneDrive ~/Library/CloudStorage"

    static let all: [DiagStep] = [
        DiagStep(
            id: 1,
            title: "OneDrive est-il lancé ?",
            symbol: "bolt.heart",
            explanation: "Liste les processus OneDrive en cours. Si aucune ligne ne s’affiche, OneDrive n’est pas lancé : utilisez le bouton « Lancer OneDrive ».",
            // DoctorOneDrive est exclu, sinon l’app se détecterait elle-même.
            command: #"pgrep -fl "OneDrive" | grep -v "DoctorOneDrive""#,
            emptyHint: "Aucun processus OneDrive : OneDrive n’est pas lancé."
        ),
        DiagStep(
            id: 2,
            title: "Version de OneDrive",
            symbol: "number",
            explanation: "Lit la version dans /Applications (version autonome), puis dans ~/Applications (Mac App Store) si la première est absente.",
            command: #"defaults read /Applications/OneDrive.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || defaults read "$HOME/Applications/OneDrive.app/Contents/Info.plist" CFBundleShortVersionString"#,
            emptyHint: "Version introuvable : OneDrive ne semble pas installé."
        ),
        DiagStep(
            id: 3,
            title: "Espace disque disponible",
            symbol: "internaldrive",
            explanation: "Un disque presque plein peut bloquer la synchronisation.",
            command: "df -h /",
            emptyHint: "Aucune information renvoyée."
        ),
        DiagStep(
            id: 4,
            title: "Journaux récents",
            symbol: "doc.text",
            explanation: "Liste les 20 journaux OneDrive les plus récents.",
            command: "ls -lht \(logs) | head -20",
            emptyHint: "Aucun journal trouvé."
        ),
        DiagStep(
            id: 5,
            title: "Erreurs récentes",
            symbol: "exclamationmark.triangle",
            explanation: "Recherche les 50 dernières lignes d’erreur dans les journaux. Ce sont ces lignes qu’il faut copier pour le support.",
            command: #"grep -RniE "error|failed|conflict|blocked|denied|quota|401|403|429|500|503" \#(logs) 2>/dev/null | tail -50"#,
            emptyHint: "Aucune erreur trouvée dans les journaux."
        ),
        DiagStep(
            id: 6,
            title: "Erreurs en temps réel",
            symbol: "waveform.path.ecg",
            explanation: "Démarrez le suivi, puis déclenchez une synchronisation ou modifiez un fichier test. Les erreurs s’affichent au fil de l’eau. Arrêtez avec le bouton « Arrêter ».",
            // --line-buffered : sans lui grep retient ses lignes tant que sa sortie n’est pas un terminal.
            command: #"tail -f \#(logs)*.log 2>/dev/null | grep --line-buffered -iE "error|failed|conflict|denied|blocked""#,
            emptyHint: "Aucune erreur capturée pendant le suivi.",
            isStream: true,
            inFullRun: false
        ),
        DiagStep(
            id: 7,
            title: "Fichiers en conflit",
            symbol: "arrow.triangle.branch",
            explanation: "Recherche les fichiers dont le nom contient « conflict », « -copie » ou « -copy ».",
            command: #"find \#(roots) -type f \( -iname "*conflict*" -o -iname "*-copie*" -o -iname "*-copy*" \) 2>/dev/null | head -50"#,
            emptyHint: "Aucun fichier en conflit trouvé."
        ),
        DiagStep(
            id: 8,
            title: "Fichiers modifiés depuis 24 h",
            symbol: "clock.arrow.circlepath",
            explanation: "Identifie les fichiers récemment modifiés, souvent à l’origine d’un blocage.",
            command: "find \(roots) -type f -mtime -1 2>/dev/null | head -50",
            emptyHint: "Aucun fichier modifié depuis 24 h."
        ),
        DiagStep(
            id: 9,
            title: "Fichiers volumineux (> 500 Mo)",
            symbol: "shippingbox",
            explanation: "Les fichiers très volumineux ralentissent ou bloquent la synchronisation.",
            command: #"find \#(roots) -type f -size +500M -exec ls -lh {} \; 2>/dev/null | head -30"#,
            emptyHint: "Aucun fichier de plus de 500 Mo."
        ),
        DiagStep(
            id: 10,
            title: "Bibliothèques SharePoint montées",
            symbol: "externaldrive.connected.to.line.below",
            explanation: "Liste les emplacements présents dans ~/Library/CloudStorage (OneDrive et bibliothèques SharePoint).",
            command: "ls -ld ~/Library/CloudStorage/* 2>/dev/null",
            emptyHint: "Aucun emplacement monté dans ~/Library/CloudStorage."
        ),
        DiagStep(
            id: 11,
            title: "Journaux SharePoint",
            symbol: "building.2",
            explanation: "Recherche les 50 dernières lignes des journaux qui mentionnent SharePoint.",
            command: #"grep -RniE "sharepoint|spo|sites|document.?library" \#(logs) 2>/dev/null | tail -50"#,
            emptyHint: "Aucune mention de SharePoint dans les journaux."
        ),
        DiagStep(
            id: 12,
            title: "Redémarrer OneDrive",
            symbol: "arrow.clockwise.circle",
            explanation: "Quitte proprement OneDrive, attend 5 secondes, puis le relance. macOS peut demander l’autorisation de contrôler OneDrive.",
            command: #"osascript -e 'quit app "OneDrive"'; sleep 5 && open -a OneDrive"#,
            emptyHint: "OneDrive a été relancé.",
            needsConfirm: true,
            inFullRun: false
        ),
    ]

    static let fullRun = all.filter(\.inFullRun)
}

enum Advice {
    static let todo = [
        "Vérifier que le fichier est accessible depuis OneDrive Web ou SharePoint Web.",
        "Vérifier que le fichier n’est pas ouvert dans une application.",
        "Vérifier la taille et le nom du fichier : éviter les noms très longs, les caractères spéciaux ou les fichiers très volumineux.",
        "Noter le message exact affiché par l’icône OneDrive.",
        "Copier les dernières lignes obtenues par la commande « Erreurs récentes ».",
    ]
    static let dont = [
        "Ne pas supprimer manuellement ~/Library/CloudStorage/OneDrive*.",
        "Ne pas supprimer les dossiers ou journaux OneDrive.",
        "Ne pas utiliser de commande de réinitialisation.",
    ]
    static let persist = [
        "Mettre en pause la synchronisation « 2 heures », attendre 5 minutes, puis la relancer.",
        "Délier puis relier le compte OneDrive depuis Aide et paramètres > Préférences > Compte.",
        "Redémarrer le Mac.",
    ]
    static let notes = [
        "Microsoft recommande désormais de passer par les raccourcis SharePoint intégrés à OneDrive, afin de simplifier l’accès aux fichiers et de fiabiliser leur synchronisation, particulièrement sur macOS.",
        "Depuis peu, les dossiers synchronisés ne sont plus regroupés dans un dossier mais placés à la racine du Finder : chaque dossier synchronisé ajoute un lien dans l’arborescence.",
    ]
    static let reset = [
        "Cliquer sur le nuage OneDrive.",
        "Choisir Préférences > Suspendre > Quitter OneDrive.",
        "Ouvrir Applications dans le Finder.",
        "Faire un clic droit sur OneDrive, puis choisir Afficher le contenu du paquet.",
        "Ouvrir Contents/Resources.",
        "Lancer ResetOneDriveApp.command (ou ResetOneDriveAppStandalone.command pour la version autonome).",
        "Relancer OneDrive.",
        "Se reconnecter.",
        "Sélectionner l’ancien emplacement OneDrive.",
    ]
}
