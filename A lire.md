# SyncDoctor pour OneDrive et SharePoint — À lire

SyncDoctor aide à comprendre pourquoi OneDrive ou une bibliothèque SharePoint ne synchronise plus sur un Mac. Ce document explique comment l'installer et s'en servir.

## Ce qu'il faut

- Un Mac Apple Silicon sous macOS 27.2 ou ultérieur.
- OneDrive installé, en version Mac App Store ou en version autonome.

## Installation

1. Téléchargez [SyncDoctor-1.2.1.dmg](https://github.com/mx-ch-rgb/SyncDoctor/releases/latest/download/SyncDoctor-1.2.1.dmg).
2. Ouvrez le fichier, puis glissez SyncDoctor dans le dossier Applications.
3. Lancez l'app depuis Applications. macOS indique qu'elle a été téléchargée depuis Internet : cliquez sur Ouvrir. L'app est signée et notarisée par Apple.

## Premier diagnostic

1. Sur la vue d'ensemble, cliquez sur « Lancer le diagnostic complet ».
2. macOS demande l'autorisation d'accéder aux dossiers OneDrive : acceptez.
3. Chaque carte affiche son résultat. Cliquez sur une carte pour voir la commande exécutée et le résultat complet.
4. « Copier le rapport » ou « Enregistrer… » produit un texte à transmettre au support.

Le diagnostic complet ne fait que lire : il ne modifie et ne supprime rien.

## Lire les journaux de OneDrive

Les étapes 4, 5, 6 et 13 lisent les journaux de OneDrive. Avec la version Mac App Store, ces journaux sont rangés dans un dossier que macOS réserve à OneDrive. Tant que l'accès n'est pas accordé, ces étapes affichent « Accès refusé par macOS » : ce n'est pas un résultat « sans erreur ».

Pour l'accorder :

1. Dans la barre latérale, ouvrez « Accès complet au disque ».
2. Cliquez sur « Ouvrir Accès complet au disque » : Réglages Système s'ouvre sur la bonne page.
3. Ajoutez SyncDoctor à la liste avec le bouton « + » et activez son interrupteur.
4. Quittez puis rouvrez SyncDoctor.

## Les 14 vérifications

| N° | Vérification | Ce qu'elle montre |
|---|---|---|
| 1 | OneDrive est-il lancé ? | Les processus OneDrive en cours. |
| 2 | Version de OneDrive | Le numéro de version et le type : autonome ou Mac App Store. |
| 3 | Espace disque disponible | Un disque presque plein peut bloquer la synchronisation. |
| 4 | Journaux récents | Les 20 éléments les plus récents du dossier des journaux. |
| 5 | Erreurs récentes | Les 50 dernières lignes d'erreur des journaux. |
| 6 | Erreurs en temps réel | Les erreurs au fil de l'eau, à lancer puis arrêter à la main. |
| 7 | Fichiers en conflit | Les fichiers nommés « conflict », « -copie » ou « -copy ». |
| 8 | Fichiers modifiés depuis 24 h | Les fichiers récemment modifiés, souvent en cause. |
| 9 | Fichiers volumineux | Les fichiers de plus de 500 Mo. |
| 10 | Nombre d'éléments et de dossiers | Le total par emplacement, comparé à la recommandation de 300 000 éléments. |
| 11 | Noms et chemins trop longs | La liste, avec leur chemin, des éléments qui dépassent 255, 400 ou 520 caractères. |
| 12 | Emplacements OneDrive et SharePoint | Les comptes et bibliothèques synchronisés. |
| 13 | Journaux SharePoint | Les lignes des journaux qui mentionnent SharePoint. |
| 14 | Redémarrer OneDrive | Quitte puis relance OneDrive, après confirmation. |

Les étapes 6 et 14 ne font pas partie du diagnostic complet : elles se lancent à la main.

## Les écrans d'aide

- **Conseils** : ce qu'il faut faire, ce qu'il ne faut pas faire, que faire si le problème persiste.
- **Accès complet au disque** : le lien vers le réglage macOS et la marche à suivre.
- **Deux versions de OneDrive** : comment repérer une double installation et la corriger selon la procédure de Microsoft.
- **Reset OneDrive** : la réinitialisation décrite par Microsoft, en dernier recours. L'app ne la lance pas elle-même.

Les textes d'aide reprennent les pages d'assistance de Microsoft, citées en bas de chaque écran.

## Limites connues

- SyncDoctor lit et affiche : il ne répare pas à votre place. Les commandes qui suppriment quelque chose sont seulement affichées, à copier dans le Terminal.
- Le comptage des éléments (étape 10) peut être long sur une grande bibliothèque.
- L'app est indépendante et n'a aucun lien avec Microsoft. OneDrive et SharePoint sont des marques de Microsoft Corporation.

## Licence et auteur

SyncDoctor est un logiciel libre sous licence MIT, conçu et développé par Marc Christiaens. Le code source est sur [GitHub](https://github.com/mx-ch-rgb/SyncDoctor).
