# DoctorOneDrive

Diagnostic des synchronisations OneDrive et SharePoint sur Mac, en un clic.

DoctorOneDrive réunit dans une app macOS les commandes Terminal utiles pour comprendre pourquoi OneDrive ou une bibliothèque SharePoint ne synchronise plus. Chaque écran affiche la commande exacte qui est exécutée, et le résultat peut être copié ou enregistré dans un rapport à transmettre au support.

Tout le diagnostic est en lecture seule : l'app ne supprime rien et ne réinitialise rien.

## Téléchargement

[Télécharger DoctorOneDrive (.dmg)](https://github.com/mx-ch-rgb/DoctorOneDrive/releases/latest/download/DoctorOneDrive-1.0.dmg)

- macOS 27.2 ou ultérieur, Mac Apple Silicon.
- App signée et notarisée par Apple.
- Ouvrez le .dmg, puis glissez DoctorOneDrive dans Applications.

Au premier diagnostic, macOS demande l'autorisation d'accéder aux dossiers OneDrive ; au premier redémarrage de OneDrive, celle de le contrôler.

## Les 12 vérifications

| N° | Vérification | Commande |
|---|---|---|
| 1 | OneDrive est-il lancé ? | `pgrep -fl "OneDrive"` |
| 2 | Version de OneDrive | `defaults read /Applications/OneDrive.app/Contents/Info.plist CFBundleShortVersionString` |
| 3 | Espace disque disponible | `df -h /` |
| 4 | Journaux récents | `ls -lht ~/Library/Logs/OneDrive/ \| head -20` |
| 5 | Erreurs récentes | `grep -RniE "error\|failed\|conflict\|blocked\|denied\|quota\|401\|403\|429\|500\|503" ~/Library/Logs/OneDrive/ \| tail -50` |
| 6 | Erreurs en temps réel | `tail -f ~/Library/Logs/OneDrive/*.log \| grep -iE "error\|failed\|conflict\|denied\|blocked"` |
| 7 | Fichiers en conflit | `find ~/OneDrive ~/Library/CloudStorage -type f \( -iname "*conflict*" -o -iname "*-copie*" -o -iname "*-copy*" \)` |
| 8 | Fichiers modifiés depuis 24 h | `find ~/OneDrive ~/Library/CloudStorage -type f -mtime -1` |
| 9 | Fichiers de plus de 500 Mo | `find ~/OneDrive ~/Library/CloudStorage -type f -size +500M -exec ls -lh {} \;` |
| 10 | Bibliothèques SharePoint montées | `ls -ld ~/Library/CloudStorage/*` |
| 11 | Journaux SharePoint | `grep -RniE "sharepoint\|spo\|sites\|document.?library" ~/Library/Logs/OneDrive/ \| tail -50` |
| 12 | Redémarrer OneDrive | `osascript -e 'quit app "OneDrive"'; sleep 5 && open -a OneDrive` |

Le « diagnostic complet » enchaîne les étapes 1 à 5 et 7 à 11. Le suivi en temps réel (6) et le redémarrage (12) se lancent à la main ; le redémarrage demande une confirmation.

## Bonnes pratiques rappelées dans l'app

À faire :

- Vérifier que le fichier est accessible depuis OneDrive Web ou SharePoint Web.
- Vérifier que le fichier n'est pas ouvert dans une application.
- Éviter les noms très longs, les caractères spéciaux et les fichiers très volumineux.
- Noter le message exact affiché par l'icône OneDrive.

À ne pas faire :

- Supprimer manuellement `~/Library/CloudStorage/OneDrive*`.
- Supprimer les dossiers ou journaux OneDrive.
- Lancer une réinitialisation avant d'avoir épuisé le diagnostic.

À savoir :

- Microsoft recommande de passer par les raccourcis SharePoint intégrés à OneDrive, plus fiables sur macOS que la synchronisation directe des bibliothèques.
- Les dossiers synchronisés apparaissent désormais à la racine du Finder, avec un lien par dossier.

La procédure de réinitialisation de OneDrive est décrite dans l'app comme dernier recours ; l'app ne la lance pas elle-même.

## Compiler depuis les sources

Xcode 27 ou ultérieur est requis.

```bash
./build.sh
```

Le script compile l'app pour arm64, l'assemble dans `build/DoctorOneDrive.app` et la signe avec le certificat « Developer ID Application » du trousseau. Sans certificat, utilisez une signature locale :

```bash
SIGN_ID=- ./build.sh
```

`./make_dmg.sh` crée le .dmg et `./notarize.sh` le fait notariser par Apple (un profil `notarytool` est nécessaire, voir l'en-tête du script).
