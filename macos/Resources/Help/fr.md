# Aide de Band·je
Band·je enregistre les conversations sur votre Mac et les transforme en texte. Il se trouve dans la barre des menus : la petite cassette en haut à droite. Tout se passe sur votre Mac.

## Enregistrer une conversation {#record}
Appuyez sur ⌃⌥⌘R pour démarrer, et à nouveau sur ⌃⌥⌘R pour arrêter.

Band·je enregistre deux choses à la fois : votre microphone et tout le son que joue votre Mac. Il fonctionne avec n’importe quelle app d’appel, comme FaceTime, Zoom, Teams, Meet ou un appel téléphonique passé depuis votre Mac. Band·je n’enregistre pas votre écran.

- Pendant l’enregistrement, la cassette dans la barre des menus devient rouge, ses bobines tournent et la durée défile à côté, en rouge.
- Votre Mac ne se met pas en veille pendant que Band·je enregistre.
- La première fois, macOS vous demande l’autorisation d’enregistrer le son de votre Mac. Acceptez, sinon Band·je n’entend que votre microphone.
- Si votre microphone reste silencieux pendant six secondes, ou si l’écran est fermé alors que le microphone intégré est utilisé, Band·je vous prévient et propose de passer à un autre microphone.

Prévenez les autres personnes que vous enregistrez. Dans certains pays, et dans un cadre professionnel, la loi l’exige, et il faut parfois aussi leur accord. Vous êtes responsable du respect de la loi qui s’applique à vous. Band·je vous le rappelle une fois, avant votre premier enregistrement.

### Où vont vos enregistrements
Chaque enregistrement a son propre dossier dans `~/Music/Bandje` (ou dans le dossier choisi dans [Réglages](#settings), ou dans iCloud Drive › Band·je si vous [synchronisez avec iCloud](#settings)), nommé d’après le jour et l’heure, par exemple `Enregistrement 6 nov 14.32`. Votre iPhone nomme ses enregistrements de la même façon. Le dossier contient :

- l’audio (`.m4a`) : vous sur le canal gauche, les autres sur le canal droit
- la transcription (`.md`), lisible dans n’importe quelle app de texte ou de Markdown
- les données brutes (`.json`) avec l’heure de chaque mot
- les résumés, sous forme de fichiers `.md`

Ouvrez un enregistrement dans la [fenêtre Band·je](#player). Choisissez **Ouvrir le dossier d’enregistrements** dans le menu pour voir les fichiers. Si Band·je ou votre Mac s’arrête de façon inattendue pendant un enregistrement, Band·je propose de le récupérer au prochain démarrage.

## Transcriptions {#transcripts}
Une fois l’enregistrement arrêté, Band·je écrit ce qui a été dit, et par qui.

Le menu affiche la progression. Vous pouvez démarrer un nouvel enregistrement pendant que Band·je transcrit. Quand la transcription est prête, une petite coche verte apparaît sur la cassette dans la barre des menus, et le menu indique **Transcription prête** : cliquez dessus pour ouvrir l’enregistrement dans la fenêtre Band·je. La coche disparaît une fois que vous avez ouvert le menu.

- Ce que vous dites est étiqueté **Moi**. Ce que disent les autres est étiqueté **Interlocuteur**.
- Quand plusieurs personnes parlent de l’autre côté, Band·je les distingue : **Locuteur 1**, **Locuteur 2**, etc. Donnez-leur un nom avec [Nommer les locuteurs](#speakers).
- Il en va de même pour plusieurs personnes autour de votre Mac, lors d’une réunion autour d’une table : au lieu de **Moi**, elles deviennent **Locuteur 1**, **Locuteur 2**, etc.
- Band·je comprend 25 langues, dont l’anglais, le néerlandais, l’allemand, le français, l’espagnol, l’italien, le portugais, le polonais, le russe et l’ukrainien. Vous n’avez pas besoin de choisir la langue.

Pour un meilleur résultat, portez un casque pendant un appel. Sans casque, votre microphone capte aussi votre interlocuteur via vos haut-parleurs. Band·je en filtre la plus grande partie, mais pas tout.

### Transcrire un autre fichier
Choisissez **Transcrire un fichier…** pour transcrire n’importe quel fichier audio, comme un mémo vocal de votre iPhone. Band·je copie l’audio dans son propre dossier dans votre dossier d’enregistrements et place la transcription à côté. L’original reste où il était.

## Nommer les locuteurs {#speakers}
Donnez leur vrai nom aux locuteurs d’une transcription.

Ouvrez l’enregistrement dans la [fenêtre Band·je](#player) et choisissez **Nommer les locuteurs…** sous **Plus**, ou choisissez **Nommer les locuteurs…** dans le menu : l’enregistrement en cours s’ouvre. Pour travailler sur un enregistrement plus ancien depuis le menu, choisissez d’abord **Enregistrements récents**.

Pour chaque locuteur, vous voyez sa plus longue citation. Cliquez sur le bouton de lecture pour écouter ce passage, tapez un nom et cliquez sur **Enregistrer**. Band·je met à jour la transcription et tout résumé ultérieur. Laissez un champ vide pour garder l’étiquette.

Sur une ligne téléphonique avec un menu ou une musique d’attente, Band·je entend parfois plus de locuteurs qu’il n’y en avait. Donnez le même nom à deux étiquettes, ou laissez l’étiquette en trop telle quelle.

## La fenêtre Band·je {#player}
Tous vos enregistrements dans une seule fenêtre : écouter, lire en même temps, rechercher, nommer les locuteurs, résumer et partager.

Choisissez **Ouvrir Band·je** dans le menu (⌘O). La fenêtre s’ouvre aussi quand vous lancez Band·je vous-même, par exemple depuis Launchpad ou Spotlight. **Ouvrir dans Band·je** ouvre l’enregistrement en cours. Tant que la fenêtre est ouverte, Band·je est dans le Dock et dans ⌘Tab ; fermez-la et Band·je ne se trouve plus que dans la barre des menus. Activez **Toujours dans le Dock** dans [Réglages](#settings) pour garder l’icône. La première fois, la fenêtre s’ouvre toujours, avec les autorisations, chacune avec son bouton. Fermez la fenêtre et Band·je reste dans la barre des menus ; quittez Band·je depuis ce menu.

- À gauche : vos enregistrements par jour, avec l’heure, la durée et les premiers mots de la transcription. La recherche trouve les titres et les mots des transcriptions. En bas se trouve **Démarrer l’enregistrement** ; pendant l’enregistrement, le nouvel enregistrement apparaît en haut avec un point rouge, et la fenêtre l’ouvre quand vous arrêtez.
- À droite : l’enregistrement avec la cassette, la barre de position et le bouton de lecture (Espace). Cliquez sur une phrase pour écouter à partir de là ; pendant la lecture, la phrase en cours s’illumine et la transcription suit. **Rechercher dans la transcription** (⌘F) trouve des mots.
- À côté de **Transcription** se trouve l’onglet **Résumé**. Sans résumé, il contient **Résumer** : choisissez un modèle, voir [Résumés](#summaries). Chaque résumé a son propre onglet ; **Autre résumé** en crée un autre.
- Pas encore de transcription (un enregistrement de votre iPhone, par exemple) ? Cliquez sur **Transcrire**.
- **Partager** : **Audio…**, **Transcription (.md)…**, **Transcription en PDF…** ou **Page web avec audio…** : un seul fichier avec le lecteur, la transcription, les résumés et l’audio, qui fonctionne dans tout navigateur, même hors ligne. **Page web avec audio, compacte (pour e-mail)…** réduit l’audio. La page contient un lien vers band.je, et rien d’autre.
- Sur papier : **Imprimer…** (⌘P, ou dans **Partager**) imprime la transcription, comme le PDF.
- **Plus** : **Nom et couleur…** (ou cliquez sur le titre sur la cassette) : le nom et la couleur de la cassette, **Nommer les locuteurs…**, **Afficher dans le Finder**, **Supprimer…** (vers la Corbeille).
- Vous pouvez aussi supprimer un enregistrement depuis la liste : cliquez dessus avec le bouton droit et choisissez **Supprimer…**, ou sélectionnez-le et appuyez sur ⌫. Band·je demande d’abord confirmation.

## Dictée {#dictation}
Appuyez sur ⌃⌥⌘D, parlez, et le texte apparaît là où se trouve votre curseur : dans une messagerie, un e-mail, un éditeur ou Terminal.

Il y a deux façons d’utiliser le raccourci :

- **Appuyez brièvement** sur ⌃⌥⌘D : Band·je écoute jusqu’à ce que vous appuyiez sur Return, ou à nouveau sur ⌃⌥⌘D. La touche Return elle-même n’est pas envoyée à l’app.
- **Maintenez** ⌃⌥⌘D : Band·je écoute tant que vous maintenez les touches et colle le texte quand vous les relâchez.

Appuyez sur Esc pour annuler. L’icône de la barre des menus devient orange pendant que Band·je écoute, avec la durée à côté. Une dictée peut durer jusqu’à cinq minutes ; pendant les 30 dernières secondes, la durée clignote.

### Coller
Le texte est toujours dans le presse-papiers. Pour le coller à votre place, Band·je a besoin de l’autorisation d’envoyer une frappe (⌘V) : choisissez **Activer le collage automatique…** dans le menu, ou allez dans Réglages Système > Confidentialité et sécurité > Accessibilité et activez Band·je. Sans cela, vous collez vous-même avec ⌘V.

macOS ne signale cette autorisation à Band·je qu’après un redémarrage. Vous venez de l’activer ? Choisissez **Redémarrer Band·je pour le collage automatique** dans le menu, ou **Redémarrer Band·je** dans [Réglages](#settings).

Si vous entendez un bref son au lieu d’un collage, un champ de mot de passe ou une autre app a activé la saisie sécurisée (l’Entrée clavier sécurisée de Terminal, un gestionnaire de mots de passe). macOS bloque alors le collage ; le texte est dans le presse-papiers, appuyez donc vous-même sur ⌘V.

Rien de ce que vous dictez n’est conservé.

## Résumés {#summaries}
Band·je peut résumer une conversation sous la forme de votre choix, avec Apple Intelligence sur votre Mac.

Les résumés nécessitent macOS 26 ou ultérieur avec Apple Intelligence activé. Sans cela, le menu **Résumer** n’apparaît pas et Band·je fonctionne comme d’habitude.

1. Choisissez **Résumer** dans le menu.
2. Sous **Choisir un modèle**, choisissez-en un. Band·je résume l’enregistrement en cours. Pour en résumer un autre, choisissez-le d’abord sous **Enregistrements récents**.
3. Pendant que Band·je travaille, des étincelles violettes apparaissent dans la barre des menus. Placez le pointeur dessus pour voir la progression.
4. Une fois terminé, une petite coche verte apparaît sur la cassette et le menu indique **Résumé prêt**. Si la fenêtre Band·je est ouverte, elle affiche l’enregistrement.

Vous pouvez aussi partir de la [fenêtre Band·je](#player) : choisissez **Résumer** à côté des onglets et choisissez un modèle.

Le résumé est enregistré à côté de la transcription sous le nom `<nom> résumé <modèle>.md`. Un résumé prend de quelques secondes à environ une minute. Les longues conversations sont résumées par parties.

Le résumé est rédigé dans la langue de la conversation. Apple Intelligence résume en anglais, néerlandais, allemand, français, espagnol, italien, portugais et quelques autres langues, mais pas encore en polonais, russe ou ukrainien.

Le modèle sur votre Mac est petit. Il s’en tient à ce qui a été dit, mais il peut manquer des détails. Vérifiez les faits importants dans la transcription.

Band·je est fourni avec quatre modèles : une réunion, un entretien d’embauche, un entretien client et un résumé général. Pour créer le vôtre, voir [Créer un modèle](#templates).

## Créer un modèle {#templates}
Créez votre propre modèle de résumé : un fichier texte avec les titres que vous voulez.

Un modèle est un simple fichier texte (`.md` ou `.txt`) dans `~/Music/Bandje/Templates`. Le nom du fichier devient le nom affiché dans le menu **Résumer**.

Le plus rapide : fenêtre Band·je ouverte, choisissez **Résumer** > **Nouveau modèle** dans la barre des menus. Band·je crée un nouveau modèle avec deux titres et l’ouvre ; modifiez-le, enregistrez-le et donnez-lui un nom dans le Finder.

### Partir d’une copie
Le plus simple est de copier un exemple et de le modifier :

1. Choisissez **Résumer** > **Ouvrir le dossier des modèles**.
2. Sélectionnez l’exemple le plus proche de ce que vous voulez, par exemple `Meeting.md`.
3. Choisissez Fichier > Dupliquer (⌘D) dans le Finder, et renommez la copie, par exemple `Weekly standup.md`.
4. Ouvrez la copie dans TextEdit ou une autre app de texte, modifiez les titres et enregistrez.

Le nouveau modèle apparaît aussitôt dans le menu **Résumer**. Vous pouvez aussi modifier les exemples eux-mêmes, ou les supprimer : Band·je ne les remet que si vous supprimez tout le dossier Templates.

### Ce que contient un modèle
Une liste de titres, chacun avec une ligne qui décrit ce qui va dessous :

- `## Décisions` avec la ligne « Chaque décision sous forme de puce. Indiquez qui a décidé. »
- `## Actions` avec la ligne « Qui, quoi et quand. »

Conseils :

- Soyez précis. « Prétentions salariales avec les montants exacts » fonctionne mieux que « Salaire ».
- Limitez-vous à environ cinq titres. Le modèle sur votre Mac est petit : moins de titres donnent de meilleures réponses.
- Écrivez « si cela a été dit » quand un sujet risque de ne pas être abordé, pour que Band·je ne l’invente pas.
- Les titres restent tels que vous les écrivez. Le texte suit la langue de la conversation.

## Microphone et son {#devices}
Choisissez le microphone utilisé et la sortie du son de votre Mac, directement depuis le menu.

### Microphone
Le menu **Microphone** liste tous les microphones. Celui qui est utilisé est coché et son nom s’affiche sous l’élément de menu. En choisir un change le microphone de tout votre Mac, si bien que votre app d’appel utilise le même. Écran fermé, le microphone intégré est désactivé ; Band·je l’indique.

### Sortie audio
Le menu **Sortie audio** liste tous les appareils capables de jouer du son et règle la sortie audio de votre Mac. Band·je ne la modifie jamais de lui-même.

Certains microphones USB ont une prise casque et comptent aussi comme haut-parleurs. Quand vos AirPods se déconnectent, macOS peut y envoyer le son. Choisissez vos haut-parleurs dans Sortie audio pour corriger cela.

## Réglages {#settings}
Raccourcis, dossier des enregistrements, autorisations, ouverture à la connexion et langue de Band·je.

Choisissez **Réglages…** dans le menu.

### Général
Activez **Ouvrir Band·je à la connexion** et Band·je apparaît tout seul dans la barre des menus après votre connexion. **Toujours dans le Dock** garde Band·je dans le Dock, même sans la fenêtre. Vous pouvez aussi le choisir dans la fenêtre de bienvenue la première fois que vous ouvrez Band·je. C’est désactivé tant que vous ne l’activez pas. Si vous le désactivez dans Réglages Système > Général > Ouverture et extensions, Band·je l’indique ici. Désactivez **Afficher la fenêtre Band·je au démarrage** et Band·je reste dans la barre des menus au démarrage.

Band·je suit la langue de macOS. Pour utiliser une autre langue pour Band·je uniquement, choisissez-la ici et cliquez sur **Redémarrer Band·je**. Les menus, les fenêtres, les nouvelles transcriptions et l’aide changent de langue. **Comme macOS** revient à la langue du système.

### Raccourcis clavier
Cliquez sur un champ et tapez la nouvelle combinaison. Elle doit contenir ⌘, ⌃ ou ⌥, ou être une touche de fonction. Esc annule, **Valeurs par défaut** rétablit ⌃⌥⌘R et ⌃⌥⌘D.

Si une autre app utilise déjà la combinaison, Band·je vous le signale et garde l’ancienne.

### Son
Choisissez le **Microphone** et la **Sortie audio**, comme dans le menu de Band·je. Cela vaut pour toutes les apps, y compris pour les appels.

### Transcription
**Transcrire automatiquement** transcrit chaque enregistrement dès que vous arrêtez. **Reconnaître les locuteurs** distingue plusieurs voix (Locuteur 1, Locuteur 2…) ; désactivé, vous n’obtenez que Moi et Interlocuteur. Band·je reconnaît la langue tout seul.

### Stockage
Activez **Synchroniser avec iCloud** et vos enregistrements, transcriptions, résumés et modèles se trouvent dans iCloud Drive › Band·je, sur votre iPhone et vos autres Mac avec le même compte Apple. Un enregistrement est d’abord créé sur votre Mac, puis passe dans iCloud quand vous l’arrêtez. Band·je vous demande s’il faut déplacer aussi vos enregistrements existants. Désactivez l’option et votre propre dossier redevient le dossier des enregistrements ; rien n’est supprimé d’iCloud, et Band·je propose de recopier les enregistrements. Apple chiffre iCloud Drive de bout en bout si la protection avancée des données est activée.

Cliquez sur **Modifier…** et choisissez un dossier, n’importe où sur votre Mac ou sur un disque externe. Les nouveaux enregistrements et les fichiers transcrits y sont placés. Les enregistrements existants restent où ils sont, tout comme vos modèles et les modèles vocaux. **Utiliser ~/Music/Bandje** revient au dossier standard.

Si le dossier se trouve dans iCloud Drive, Dropbox ou un autre service cloud (y compris Bureau et Documents lorsqu’ils sont dans iCloud), Band·je vous prévient : vos enregistrements quittent alors votre Mac via ce service.

### Accès
Si Band·je peut utiliser le micro, coller pour vous et enregistrer le son de votre Mac, avec un bouton pour chacun (**Autoriser…** ou **Ouvrir les réglages…**). Une coche verte signifie autorisé ; l’état se met à jour tout seul quand vous revenez des Réglages Système. Voir [Dépannage](#troubleshooting).

## Confidentialité et réseau {#privacy}
Votre audio, vos transcriptions et vos résumés ne quittent jamais votre Mac.

- Pas de compte, pas de statistiques, pas de suivi. Aucun serveur à nous.
- iCloud uniquement si vous activez [Synchroniser avec iCloud](#settings) : vos enregistrements sont alors dans votre propre iCloud Drive, comme vos autres fichiers. Band·je ne les voit jamais.
- Tout est stocké dans votre dossier d’enregistrements : `~/Music/Bandje`, sauf si vous en avez choisi un autre. Supprimez un dossier et il disparaît. Si vous choisissez un dossier dans iCloud Drive ou un autre service cloud, vos enregistrements vont vers ce service ; Band·je vous prévient d’abord.
- La transcription, la reconnaissance des locuteurs et la dictée s’effectuent sur votre Mac.
- Les résumés utilisent uniquement le modèle Apple Intelligence de votre Mac, jamais le Private Cloud Compute d’Apple.

Le moteur vocal de Desert Ant Labs vérifie sa licence par le réseau : au plus une fois par mois par modèle vocal. Il envoie un identifiant d’installation aléatoire, la version du modèle et du moteur, et l’identifiant de l’app. Jamais d’audio, jamais de texte. **À propos de Band·je** l’indique aussi.

## Mémoire et stockage {#resources}
Band·je est léger : environ 60 à 70 Mo de mémoire pendant son fonctionnement.

Les modèles vocaux sont fournis avec Band·je : environ 400 Mo de la taille de l’app. Band·je ne télécharge jamais rien lui-même.

Quelques secondes après le démarrage, Band·je charge le modèle vocal en arrière-plan, pour que la dictée soit prête tout de suite. La toute première fois sur un Mac, cela prend environ 20 secondes, car macOS optimise le modèle pour votre puce. Ensuite, c’est rapide.

Une heure d’audio occupe environ 55 Mo. La transcrire demande un peu de mémoire supplémentaire pendant l’opération.

## Dépannage {#troubleshooting}
Solutions aux problèmes possibles.

### Vérifiez d’abord les autorisations
Beaucoup de problèmes viennent d’une autorisation manquante. Choisissez **Réglages…** et regardez sous **Accès** :

- **Micro** : nécessaire pour enregistrer votre voix et pour dicter.
- **Son de votre Mac** : nécessaire pour enregistrer votre interlocuteur. macOS ne permet pas aux apps de lire cette autorisation, Band·je montre donc ce qui s’est passé lors du dernier enregistrement : du son est arrivé, ou c’était silencieux. Le silence est normal si rien ne jouait.
- **Collage automatique** : nécessaire pour coller le texte dicté à votre place.

Une coche verte signifie autorisé. Sinon, cliquez sur **Ouvrir les réglages…**, activez Band·je et revenez ; Band·je le voit tout seul.

À chaque démarrage, Band·je vérifie le microphone et le collage automatique, et vous prévient s’il en manque un. Vous n’avez pas besoin du collage automatique ? Cochez **Ne plus afficher ce message**, ou désactivez **Avertir au démarrage s’il manque quelque chose** sous Accès.

### Votre interlocuteur manque dans l’enregistrement
macOS n’a pas autorisé Band·je à enregistrer le son de votre Mac. Allez dans Réglages Système > Confidentialité et sécurité > Enregistrement de l’écran et des sons du système et activez Band·je sous Enregistrement des sons du système uniquement.

### Ma propre voix manque
Vérifiez le menu **Microphone**. Écran fermé, le microphone intégré est désactivé : choisissez-en un autre. Si Band·je n’a pas du tout le droit d’utiliser le microphone, activez-le dans Réglages Système > Confidentialité et sécurité > Microphone.

### Je n’entends plus rien après avoir retiré mes AirPods
macOS a envoyé le son vers un autre appareil, par exemple un microphone USB avec prise casque. Choisissez vos haut-parleurs dans **Sortie audio**.

### La transcription est incompréhensible
La conversation est probablement dans une langue que Band·je ne connaît pas. Band·je ne peut pas le détecter, il écrit donc ce qu’il croit avoir entendu.

### Il y a plus de locuteurs qu’en réalité
Les menus téléphoniques, la musique d’attente et les mauvaises lignes peuvent perturber la reconnaissance des locuteurs. Donnez les bons noms aux étiquettes dans [Nommer les locuteurs](#speakers).

### Résumer n’apparaît pas dans le menu
Les résumés nécessitent macOS 26 ou ultérieur avec Apple Intelligence activé dans Réglages Système > Apple Intelligence et Siri. La langue de votre Mac et celle de Siri doivent être identiques.

### Le raccourci ne fonctionne pas
Une autre app utilise peut-être la même combinaison. Choisissez-en une autre dans [Réglages](#settings).

## À propos de Band·je {#about}
Band·je est créé par Neurendal B.V. aux Pays-Bas.

Reconnaissance vocale et des locuteurs : Voz et Who de Desert Ant Labs, basés sur NVIDIA Parakeet TDT 0.6B v3 et pyannote community-1 (CC BY 4.0). Résumés : Apple Intelligence.

Choisissez **À propos de Band·je** dans le menu pour les versions et les liens.
