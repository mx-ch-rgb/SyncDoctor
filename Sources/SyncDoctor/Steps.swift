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
    /// Dossiers protégés par macOS que la commande doit pouvoir lire.
    var needs: Access = .nothing

    enum Access: Hashable {
        case nothing
        /// Le dossier des journaux de OneDrive.
        case logs
        /// Les dossiers de synchronisation OneDrive de ~/Library/CloudStorage.
        case syncFolders
    }
}

/// Dossier des journaux de OneDrive, qui dépend de la version installée.
enum OneDriveLogs {
    /// Version Mac App Store : chemin utilisé par le script CollectLogs.command fourni dans OneDrive.app.
    static let storeDir = "~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Logs"
    /// Version autonome.
    static let standaloneDir = "~/Library/Logs/OneDrive"

    /// Dossier retenu pour ce Mac, déterminé une fois au lancement.
    static let dir: String = {
        let installs = OneDriveApp.installations
        let hasStore = installs.contains { $0.fromAppStore }
        let hasStandalone = installs.contains { !$0.fromAppStore }
        if hasStore && !hasStandalone { return storeDir }
        if hasStandalone && !hasStore { return standaloneDir }
        let exists = { (path: String) in
            FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
        }
        return exists(standaloneDir) || !exists(storeDir) ? standaloneDir : storeDir
    }()

    static var expandedDir: String { (dir as NSString).expandingTildeInPath }

    static let locationNote = "Emplacement des journaux : ~/Library/Logs/OneDrive pour la version autonome, ~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Logs pour la version Mac App Store. SyncDoctor utilise celui qui correspond à la version installée. Pour la version Mac App Store, ce dossier appartient à une autre app : macOS n’en autorise la lecture qu’avec votre accord."

    static let collectNote = "Pour le support, Microsoft fournit aussi dans OneDrive.app le script Contents/Resources/CollectLogs.command, qui crée sur le Bureau une archive des journaux."
}

enum Steps {
    static let logs = OneDriveLogs.dir
    /// Emplacements de synchronisation de OneDrive uniquement (pas ceux d’autres services de stockage).
    static let roots = "~/OneDrive ~/Library/CloudStorage/OneDrive*"

    static let all: [DiagStep] = [
        DiagStep(
            id: 1,
            title: "OneDrive est-il lancé ?",
            symbol: "bolt.heart",
            explanation: "Liste les processus OneDrive en cours. Si aucune ligne ne s’affiche, OneDrive n’est pas lancé : utilisez le bouton « Lancer OneDrive ».",
            command: #"pgrep -fl "OneDrive""#,
            emptyHint: "Aucun processus OneDrive : OneDrive n’est pas lancé."
        ),
        DiagStep(
            id: 2,
            title: "Version de OneDrive",
            symbol: "number",
            explanation: "Affiche le numéro de version, puis l’identifiant de l’application : com.microsoft.OneDrive désigne la version autonome, com.microsoft.OneDrive-mac la version Mac App Store (commande d’identification donnée par Microsoft). Si OneDrive est installé ailleurs que dans /Applications, remplacez le chemin.",
            command: #"defaults read /Applications/OneDrive.app/Contents/Info.plist CFBundleShortVersionString; /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Applications/OneDrive.app/Contents/Info.plist"#,
            emptyHint: "Version introuvable : OneDrive ne semble pas installé dans /Applications."
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
            explanation: "Liste les 20 éléments les plus récents du dossier des journaux. " + OneDriveLogs.locationNote + " " + OneDriveLogs.collectNote,
            command: "ls -lht \(logs)/ | head -20",
            emptyHint: "Aucun journal trouvé.",
            needs: .logs
        ),
        DiagStep(
            id: 5,
            title: "Erreurs récentes",
            symbol: "exclamationmark.triangle",
            explanation: "Recherche les 50 dernières lignes d’erreur dans les journaux. Ce sont ces lignes qu’il faut copier pour le support. " + OneDriveLogs.locationNote,
            command: #"grep -RniE "error|failed|conflict|blocked|denied|quota|401|403|429|500|503" \#(logs)/ 2>/dev/null | tail -50"#,
            emptyHint: "Aucune erreur trouvée dans les journaux.",
            needs: .logs
        ),
        DiagStep(
            id: 6,
            title: "Erreurs en temps réel",
            symbol: "waveform.path.ecg",
            explanation: "Démarrez le suivi, puis déclenchez une synchronisation ou modifiez un fichier test. Les erreurs s’affichent au fil de l’eau. Arrêtez avec le bouton « Arrêter ». Seuls les fichiers .log placés à la racine du dossier des journaux sont suivis.",
            // --line-buffered : sans lui grep retient ses lignes tant que sa sortie n’est pas un terminal.
            command: #"tail -f \#(logs)/*.log 2>/dev/null | grep --line-buffered -iE "error|failed|conflict|denied|blocked""#,
            emptyHint: "Aucune erreur capturée pendant le suivi.",
            isStream: true,
            inFullRun: false,
            needs: .logs
        ),
        DiagStep(
            id: 7,
            title: "Fichiers en conflit",
            symbol: "arrow.triangle.branch",
            explanation: "Recherche, dans les dossiers OneDrive, les fichiers dont le nom contient « conflict », « -copie » ou « -copy ». À savoir : d’après Microsoft, lors d’un conflit sur un fichier non Office, OneDrive garde les deux versions et ajoute le nom de l’appareil au nom de la copie locale (exemple donné : Report-JOHNS-SURFACE.txt). Ces copies-là ne sont pas détectées par cette recherche : cherchez aussi le nom de votre Mac dans les noms de fichiers.",
            command: #"find \#(roots) -type f \( -iname "*conflict*" -o -iname "*-copie*" -o -iname "*-copy*" \) 2>/dev/null | head -50"#,
            emptyHint: "Aucun fichier en conflit trouvé.",
            needs: .syncFolders
        ),
        DiagStep(
            id: 8,
            title: "Fichiers modifiés depuis 24 h",
            symbol: "clock.arrow.circlepath",
            explanation: "Identifie, dans les dossiers OneDrive, les fichiers récemment modifiés, souvent à l’origine d’un blocage.",
            command: "find \(roots) -type f -mtime -1 2>/dev/null | head -50",
            emptyHint: "Aucun fichier modifié depuis 24 h.",
            needs: .syncFolders
        ),
        DiagStep(
            id: 9,
            title: "Fichiers volumineux (> 500 Mo)",
            symbol: "shippingbox",
            explanation: "Liste, dans les dossiers OneDrive, les fichiers de plus de 500 Mo, plus longs à synchroniser. La limite indiquée par Microsoft est de 250 Go par fichier.",
            command: #"find \#(roots) -type f -size +500M -exec ls -lh {} \; 2>/dev/null | head -30"#,
            emptyHint: "Aucun fichier de plus de 500 Mo.",
            needs: .syncFolders
        ),
        DiagStep(
            id: 10,
            title: "Nombre d’éléments et de dossiers",
            symbol: "folder.badge.gearshape",
            explanation: "Compte, pour chaque emplacement OneDrive, les éléments (fichiers et dossiers), les dossiers et sous-dossiers, et le nombre de niveaux d’imbrication. Microsoft ne fixe pas de nombre maximal de sous-dossiers : la recommandation porte sur le nombre total d’éléments, 300 000 au plus pour l’ensemble des bibliothèques synchronisées, raccourcis compris, même si tout n’est pas synchronisé. Au-delà, les performances de synchronisation se dégradent. Microsoft conseille aussi de limiter la profondeur des dossiers, qui allonge les chemins. Le comptage peut prendre du temps sur une grande bibliothèque.",
            command: #"t=0; for d in ~/Library/CloudStorage/OneDrive*; do [ -d "$d" ] || continue; n=$(($(find "$d" -mindepth 1 2>/dev/null | wc -l))); t=$((t+n)); echo "${d:t} : $n éléments"; find "$d" -mindepth 1 -type d 2>/dev/null | awk -F/ -v r="$d" 'BEGIN{b=split(r,x,"/")} NF-b>m{m=NF-b} END{printf "  dont %d dossiers et sous-dossiers, sur %d niveaux au plus\n", NR, m}'; done; echo "Total : $t éléments (recommandation Microsoft : 300 000 au plus)""#,
            emptyHint: "Aucun emplacement OneDrive à compter.",
            needs: .syncFolders
        ),
        DiagStep(
            id: 11,
            title: "Noms et chemins trop longs",
            symbol: "textformat.size",
            explanation: "Liste, avec leur chemin complet, les fichiers et dossiers qui dépassent une limite indiquée par Microsoft : 255 caractères pour un nom de fichier ou de dossier, 400 caractères pour le chemin complet dans OneDrive ou SharePoint (nom du fichier inclus), 520 caractères pour le chemin local. Chaque ligne indique entre crochets la limite dépassée. Le chemin est mesuré à l’intérieur du dossier OneDrive : côté cloud, les espaces et les caractères accentués sont encodés et comptent davantage, gardez donc une marge. Dans tous les cas, les 10 chemins les plus longs sont listés ensuite, avec leur longueur.",
            command: #"find ~/Library/CloudStorage/OneDrive* -mindepth 1 2>/dev/null | perl -CSD -Mutf8 -MUnicode::Normalize -ne 'chomp; $f=NFC($_); $r=$f; $r=~s{^.*?/Library/CloudStorage/[^/]*/}{}; ($n)=$r=~m{([^/]*)$}; $ln=length $n; $lr=length $r; $lf=length $f; $mn=$ln if $ln>$mn; push @t,[$lr,$_]; @t=(sort {$b->[0]<=>$a->[0]} @t)[0..9] if @t>500; @w=(); push @w,"nom : $ln > 255" if $ln>255; push @w,"chemin : $lr > 400" if $lr>400; push @w,"chemin local : $lf > 520" if $lf>520; if(@w){$c++; print "[",join(", ",@w),"] $_\n" if $c<=200} END{printf "%d élément(s) hors limites. Plus long nom : %d caractères.\n\nLes 10 chemins les plus longs (longueur dans OneDrive, puis chemin) :\n",$c,$mn; @t=sort {$b->[0]<=>$a->[0]} @t; printf "%4d  %s\n",@$_ for grep {defined} @t[0..9]}'"#,
            emptyHint: "Aucun élément analysé.",
            needs: .syncFolders
        ),
        DiagStep(
            id: 12,
            title: "Emplacements OneDrive et SharePoint",
            symbol: "externaldrive.connected.to.line.below",
            explanation: "Liste les emplacements OneDrive présents dans ~/Library/CloudStorage : un par compte, plus les bibliothèques SharePoint synchronisées.",
            command: "ls -ld ~/Library/CloudStorage/OneDrive* 2>/dev/null",
            emptyHint: "Aucun emplacement OneDrive dans ~/Library/CloudStorage."
        ),
        DiagStep(
            id: 13,
            title: "Journaux SharePoint",
            symbol: "building.2",
            explanation: "Recherche les 50 dernières lignes des journaux qui mentionnent SharePoint. " + OneDriveLogs.locationNote,
            command: #"grep -RniE "sharepoint|spo|sites|document.?library" \#(logs)/ 2>/dev/null | tail -50"#,
            emptyHint: "Aucune mention de SharePoint dans les journaux.",
            needs: .logs
        ),
        DiagStep(
            id: 14,
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

/// Pages Microsoft sur lesquelles s’appuient les textes de l’app.
struct Source: Identifiable {
    let title: String
    let url: String
    var id: String { url }
}

enum Sources {
    static let twoVersions = Source(
        title: "Pourquoi ai-je deux versions de OneDrive sur mon Mac ?",
        url: "https://support.microsoft.com/fr-fr/onedrive/why-do-i-have-two-versions-of-onedrive-on-my-mac")
    static let fixSync = Source(
        title: "Résoudre les problèmes de synchronisation OneDrive sur Mac",
        url: "https://support.microsoft.com/fr-fr/onedrive/fix-onedrive-sync-problems-on-mac")
    static let reset = Source(
        title: "Réinitialiser OneDrive",
        url: "https://support.microsoft.com/fr-fr/onedrive/reset-onedrive")
    static let shortcuts = Source(
        title: "Synchroniser des fichiers SharePoint et Teams avec votre ordinateur",
        url: "https://support.microsoft.com/fr-fr/sharepoint/sync/sync-sharepoint-and-teams-files-with-your-computer")
    static let limits = Source(
        title: "Restrictions et limitations dans OneDrive et SharePoint",
        url: "https://support.microsoft.com/fr-fr/office/restrictions-and-limitations-in-onedrive-and-sharepoint-64883a5d-228e-48f5-b3d2-eb39e07630fa")
    static let pathLimits = Source(
        title: "Quelles sont les limites de longueur des chemins d’accès aux fichiers ?",
        url: "https://support.microsoft.com/fr-fr/onedrive/what-are-file-path-length-limits")
    static let spLimits = Source(
        title: "SharePoint limits (Microsoft Learn)",
        url: "https://learn.microsoft.com/en-us/office365/servicedescriptions/sharepoint-online-service-description/sharepoint-online-limits")
    static let conflicts = Source(
        title: "Resolve sync issues in OneDrive for work or school",
        url: "https://learn.microsoft.com/en-us/troubleshoot/sharepoint/sync/troubleshoot-sync-issues")
    static let macEngine = Source(
        title: "Making Mac OneDrive Faster and More Reliable (blog OneDrive, juin 2026)",
        url: "https://techcommunity.microsoft.com/blog/onedriveblog/making-mac-onedrive-faster-and-more-reliable/4516506")
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
        "Ne pas supprimer manuellement ~/Library/CloudStorage/OneDrive*. Seule exception : le dossier laissé par une ancienne version, voir « Deux versions de OneDrive ».",
        "Ne pas supprimer les dossiers ou journaux OneDrive.",
        "Ne pas lancer de réinitialisation tant que le diagnostic et les conseils ne sont pas épuisés, voir « Reset OneDrive ».",
    ]
    static let persist = [
        "Mettre en pause la synchronisation « 2 heures », attendre 5 minutes, puis la relancer.",
        "Dissocier le compte : icône OneDrive > Aide et paramètres > Préférences > onglet Compte > « Dissocier ce Mac ».",
        "Microsoft indique ensuite de supprimer, dans Trousseaux d’accès, les informations d’identification mises en cache par OneDrive (recherchez « OneDrive »).",
        "Rouvrir OneDrive et se reconnecter. Si OneDrive signale qu’un dossier existe déjà, choisir « Utiliser ce dossier ».",
        "Redémarrer le Mac.",
    ]
    static let notes = [
        "Pour accéder aux fichiers SharePoint et Teams, Microsoft recommande les raccourcis OneDrive plutôt que le bouton Synchroniser, lorsqu’ils sont disponibles : le contenu est alors accessible sur tous les appareils, alors que la synchronisation est liée à un appareil précis, et les performances sont meilleures.",
        "Avec le nouveau moteur de synchronisation de OneDrive pour Mac, déployé progressivement depuis juin 2026, chaque bibliothèque synchronisée apparaît comme sa propre racine dans la barre latérale du Finder, au lieu d’être regroupée sous une seule entrée au nom de l’organisation.",
        "Limites indiquées par Microsoft : 300 000 éléments au plus pour l’ensemble des bibliothèques synchronisées ; 255 caractères par nom et 400 caractères pour le chemin complet (voir les étapes 10 et 11) ; 250 Go par fichier ; les caractères \" * : < > ? / \\ | ainsi que les espaces en début ou en fin de nom ne sont pas autorisés dans les noms de fichiers et de dossiers.",
    ]
    static let sources = [Sources.fixSync, Sources.shortcuts, Sources.macEngine, Sources.limits, Sources.pathLimits, Sources.spLimits, Sources.conflicts]

    static let reset = [
        "Cliquer sur l’icône de nuage OneDrive dans la barre des menus, puis choisir Préférences > Suspendre > Quitter OneDrive.",
        "Ouvrir le dossier Applications dans le Finder et repérer OneDrive.",
        "Faire un Contrôle-clic (ou clic droit) sur OneDrive, puis choisir « Afficher le contenu du paquet ».",
        "Ouvrir le dossier Contents, puis le dossier Resources.",
        "Double-cliquer sur ResetOneDriveApp.command, ou sur ResetOneDriveAppStandalone.command pour la version autonome.",
        "Démarrer OneDrive et terminer la configuration : se reconnecter, puis sélectionner l’ancien emplacement de synchronisation.",
    ]
    static let resetNotes = [
        "D’après Microsoft, la réinitialisation ne fait perdre aucun fichier ni aucune donnée : elle déconnecte toutes les connexions de synchronisation, comptes personnel et professionnel ou scolaire compris, et entraîne une nouvelle synchronisation complète.",
        "En sélectionnant l’ancien emplacement de synchronisation, les fichiers qui n’ont pas changé ne sont pas téléchargés à nouveau.",
        "Si seuls certains dossiers étaient synchronisés, il faut les resélectionner une fois la synchronisation terminée.",
        "Certaines anciennes versions de OneDrive n’ont pas de commande de réinitialisation : dans ce cas, mettre l’ancienne app à la corbeille et installer la dernière version.",
    ]
    static let resetSources = [Sources.reset, Sources.fixSync]
}

/// Une commande du guide « Deux versions de OneDrive ».
struct GuideCommand: Identifiable {
    let id: Int
    let title: String
    let note: String
    let command: String
    /// Vérification sans risque, exécutable depuis l’app. Les autres sont à copier dans le Terminal.
    var runnable = false
    /// Commande qui supprime ou force quelque chose.
    var danger = false

    /// Étape équivalente pour le Runner (hors rapport et hors barre latérale).
    var step: DiagStep {
        DiagStep(id: id, title: title, symbol: "", explanation: "", command: command,
                 emptyHint: "Aucun résultat.", inFullRun: false)
    }
}

enum DualInstall {
    static let exampleName = "OneDrive - NomDeSociete"

    static let intro = [
        "macOS connaît deux versions de OneDrive : la version autonome (téléchargée depuis OneDrive.com, installée avec Office ou par une autre source) et la version Mac App Store. D’après Microsoft, une seule version doit être installée et configurée à la fois : installer les deux peut provoquer des problèmes de synchronisation et un message indiquant que deux versions sont connectées. L’exécution côte à côte des deux versions n’est pas prise en charge.",
        "Avoir plusieurs comptes (personnel et professionnel ou scolaire, par exemple) dans la même version est en revanche pris en charge.",
    ]

    /// Commandes d’identification données par Microsoft.
    static let identify: [GuideCommand] = [
        GuideCommand(
            id: 201, title: "Quelle version est installée ?",
            note: "com.microsoft.OneDrive : version autonome. com.microsoft.OneDrive-mac : version Mac App Store.",
            command: "/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Applications/OneDrive.app/Contents/Info.plist",
            runnable: true),
        GuideCommand(
            id: 202, title: "Quelle version est configurée pour la synchronisation ?",
            note: "com.microsoft.OneDrive.FileProvider : version autonome. com.microsoft.OneDrive-mac.FileProvider : version Mac App Store. Si votre dossier OneDrive est ailleurs, remplacez ~/OneDrive par son chemin.",
            command: "xattr -l ~/OneDrive", runnable: true),
        GuideCommand(
            id: 203, title: "Où est installée la version autonome ?",
            note: "Affiche le chemin de l’application si elle est présente.",
            command: #"mdfind kMDItemCFBundleIdentifier = "com.microsoft.OneDrive""#, runnable: true),
        GuideCommand(
            id: 204, title: "Où est installée la version Mac App Store ?",
            note: "Affiche le chemin de l’application si elle est présente.",
            command: #"mdfind kMDItemCFBundleIdentifier = "com.microsoft.OneDrive-mac""#, runnable: true),
    ]

    /// Procédure de correction décrite par Microsoft.
    static let officialFix = [
        "Cliquer sur l’icône de nuage OneDrive dans la barre des menus, puis sur le lien « Afficher dans le Finder » du message. Le Finder affiche le contenu de ~/Library/CloudStorage.",
        "Double-cliquer sur chaque dossier OneDrive affiché et regarder le haut de la fenêtre du Finder.",
        "Si une bannière avec un bouton « Supprimer » apparaît, cliquer sur « Supprimer » : ce dossier appartient à l’ancienne version.",
        "Si aucun dossier ne propose ce bouton : ouvrir les préférences de OneDrive, onglet Compte, cliquer sur « Dissocier ce Mac » et suivre les instructions (vos données ne sont pas perdues). Quitter ensuite OneDrive, glisser l’application du dossier Applications vers la corbeille, puis réinstaller OneDrive depuis le Mac App Store ou OneDrive.com.",
        "Lancer OneDrive pour terminer la configuration.",
    ]

    static let switchNote = "Pour passer d’une version à l’autre, Microsoft indique de supprimer d’abord l’installation en place en lançant son script de réinitialisation (voir « Reset OneDrive »), puis d’installer la dernière version de OneDrive depuis la source voulue."

    static let manualIntro = "Les commandes ci-dessous ne figurent pas dans la documentation Microsoft. Elles servent à retirer à la main une entrée restée dans ~/Library/CloudStorage après la désinstallation d’une version, quand la procédure Microsoft ci-dessus n’a pas suffi. Vérifiez d’abord sur OneDrive Web que vos fichiers y sont bien : un fichier pas encore synchronisé serait perdu. Les vérifications s’exécutent ici ; les commandes qui suppriment ou forcent quelque chose sont à copier dans le Terminal, après avoir adapté le nom du dossier."

    static let manual: [GuideCommand] = [
        GuideCommand(
            id: 101, title: "Vérifier ce qui reste",
            note: "On devrait voir une entrée par compte actif, par exemple « OneDrive-Personal » et « \(exampleName) ». Notez le nom exact de l’entrée obsolète.",
            command: "ls -la ~/Library/CloudStorage/ | grep -i onedrive", runnable: true),
        GuideCommand(
            id: 102, title: "Vérifier les montages actifs",
            note: "Les dossiers de ~/Library/CloudStorage ne sont normalement pas des volumes montés : cette commande ne renvoie alors rien.",
            command: "mount | grep -i onedrive", runnable: true),
        GuideCommand(
            id: 103, title: "Vérifier les processus",
            note: "Liste les processus OneDrive en cours.",
            command: "pgrep -afil OneDrive", runnable: true),
        GuideCommand(
            id: 104, title: "Quitter OneDrive",
            note: "macOS peut demander l’autorisation de contrôler OneDrive.",
            command: #"osascript -e 'quit app "OneDrive"'"#, runnable: true),
        GuideCommand(
            id: 105, title: "Vérifier qu’il ne reste aucun processus",
            note: "La commande ne doit plus rien renvoyer.",
            command: "pgrep -afil OneDrive", runnable: true),
        GuideCommand(
            id: 106, title: "S’il en reste, forcer la fermeture",
            note: "Ferme de force tous les processus dont la ligne de commande contient « OneDrive ».",
            command: "pkill -f OneDrive", danger: true),
        GuideCommand(
            id: 107, title: "Supprimer l’entrée obsolète",
            note: "Remplacez « \(exampleName) » par le nom exact affiché à l’étape 1.",
            command: "rm -rf \"$HOME/Library/CloudStorage/\(exampleName)\"", danger: true),
        GuideCommand(
            id: 108, title: "Si macOS répond « Resource busy », « Operation not permitted » ou « Device busy »",
            note: "Le dossier est encore utilisé. Cette commande ne s’applique que si l’étape 2 a affiché un montage : sur un simple dossier de ~/Library/CloudStorage, diskutil répond qu’il ne trouve pas le disque. Utilisez le même nom qu’à l’étape 7, puis relancez la suppression.",
            command: "diskutil unmount force \"$HOME/Library/CloudStorage/\(exampleName)\"", danger: true),
        GuideCommand(
            id: 109, title: "Vérifier qu’il ne reste qu’une installation",
            note: "On ne doit voir qu’une seule application OneDrive.",
            command: "ls /Applications | grep -i onedrive", runnable: true),
        GuideCommand(
            id: 110, title: "Supprimer l’application obsolète si elle est encore présente",
            note: "Microsoft indique de glisser l’application du dossier Applications vers la corbeille. La commande ci-dessous fait la même chose sans passer par la corbeille et demande votre mot de passe administrateur.",
            command: #"sudo rm -rf "/Applications/OneDrive.app""#, danger: true),
    ]

    static let wildcardWarning = "Si plus aucun compte OneDrive n’est actif sur ce Mac, « rm -rf ~/Library/CloudStorage/OneDrive* » supprime d’un coup toutes les entrées dont le nom commence par OneDrive. N’utilisez jamais ce joker * tant qu’un compte OneDrive est actif et fonctionnel : supprimez uniquement le nom exact."

    static let sources = [Sources.twoVersions, Sources.fixSync]
}
