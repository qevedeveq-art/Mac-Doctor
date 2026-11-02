# Mac-Doctor / MacPilot

Application macOS locale pour examiner les ressources, la batterie, les processus et le stockage, puis agir avec confirmation. Le projet est au stade expérimental : les tests d’interface, les notifications et le comportement à long terme restent à valider avant un usage critique.

## Fonctions

- CPU global et batterie lus via des API natives ; mémoire, GPU et processus complétés par les outils macOS disponibles.
- Profils Précis, Équilibré et Économie ; fréquence réduite en arrière-plan et sur batterie. Le collecteur avancé est facultatif et suspendu sur batterie et en mode économie.
- Bouton **Optimiser la RAM** : examine les applications et leurs sous-processus, puis propose une fermeture normale après confirmation. La mémoire partagée n’est pas additionnée ; le cache macOS n’est pas vidé artificiellement.
- Historique SQLite local, durée de conservation réglable, pause, journal et rapport agrégé exportable sans commandes ni noms de processus. L’historique des noms de processus est désactivé par défaut.
- Mole optionnel : état et analyse JSON dans l’application ; les aperçus et actions interactifs restent dans Terminal. Un résultat sans indication de complétude ne doit pas être considéré comme exhaustif.
- Commandes locales : son, veille, verrouillage et raccourcis vers les réglages. La veille et le verrouillage demandent confirmation ; macOS peut demander des autorisations.

## Prérequis et compilation

macOS 13 ou ultérieur et outils de développement Apple (`xcrun`, Swift, clang). Testé ici sur MacBook Pro M5 Pro, macOS 27.2 ; les autres configurations doivent être vérifiées. Le suivi facultatif avec macmon cible Apple Silicon. Mole est utilisé uniquement s’il est déjà disponible dans `/opt/homebrew/bin/mo`.

```sh
./scripts/build.sh
./scripts/test.sh
```

L’application construite est `.build/MacPilot.app`, signée localement (ad hoc), non notariée. Le collecteur macmon n’est pas requis pour construire le tableau de bord : s’il est absent, les mesures avancées sont indisponibles. Pour télécharger explicitement la version 0.10.0 depuis sa publication GitHub et vérifier son empreinte SHA-256 :

```sh
./scripts/fetch-macmon.sh
./scripts/build.sh
./scripts/test.sh
```

Il est aussi possible d’utiliser `MACMON_BIN=/chemin/vers/macmon` pour la compilation et les tests. N’utilisez qu’un binaire de confiance. Les API matérielles utilisées par macmon sont privées et peuvent changer ; zéro ou une valeur invalide peut signifier « indisponible ». La puissance CPU/GPU ne représente pas à elle seule la consommation de la batterie.

`./scripts/test.sh` exécute les tests du moteur ; les tests d’intégration réels sont ajoutés si Mole et macmon sont disponibles. Ils utilisent un dossier temporaire et un petit processus de test, jamais une application utilisateur. `./scripts/benchmark.sh` mesure quatre collectes locales sans interface graphique : il ne mesure pas l’autonomie ni la mémoire de l’application graphique.

## Données et sécurité

L’historique et le journal se trouvent localement dans `~/Library/Application Support/MacPilotNext/`. Un verrou empêche deux instances de collecter simultanément. L’ancien `history.json` est migré vers SQLite ; les anciennes versions ne lisent pas cet historique migré. La conservation et l’effacement sont configurables depuis l’application.

Les noms/arguments complets des processus ne sont pas envoyés à un service distant. Les collectes ne doivent pas être présentées comme un diagnostic matériel certain. Les analyses Mole et les commandes système peuvent être partielles ou indisponibles. Avant de fermer une application, enregistrez vos données ; le système peut refuser ou différer sa fermeture.

## État des vérifications

La compilation et les tests automatisés du moteur ont été exécutés localement ; les essais d’intégration réels couvrent collecte, migration, Mole, macmon, pause et arrêt d’un processus temporaire. L’interface native, les notifications et les autorisations de verrouillage nécessitent encore des essais manuels. Les résultats d’un benchmark court ne constituent pas une garantie d’autonomie.

## Licences

Aucune licence de redistribution n’est encore indiquée pour le code propre à ce projet. macmon est un outil facultatif sous licence MIT : voir `ThirdParty/macmon-LICENSE`. Mole est un programme externe sous GPL-3.0, non inclus dans ce dépôt. Vérifiez les licences et obligations de distribution avant de redistribuer des binaires ou des dépendances.
