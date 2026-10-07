# Eripoo

> Mihary ho an'ny ho avy.

Application Android (Flutter) d'accompagnement à la construction de projets
entrepreneuriaux, pensée pour Madagascar, offline-first, en malagasy,
français et anglais.

**État : Phase 5 (« Offline + sync ») livrée pour revue, non acceptée.**
Phase 1 acceptée ; Phases 2 à 4 en attente de validation (appareils réels
et projet Supabase de développement non vérifiés). La sauvegarde en ligne
ne s'active que dans une version construite avec un serveur de
développement ; sans serveur, tout reste sur le téléphone. Le contenu pédagogique est un **brouillon non
relu** (malagasy à réécrire par des auteurs natifs). Détail :
[plan de développement](docs/DEVELOPMENT_PLAN.md).

## Documentation

- [Architecture technique](docs/ARCHITECTURE.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Architecture produit (quêtes, missions, hypothèses, contenu)](docs/PRODUCT_ARCHITECTURE.md)
- [Modèle de données](docs/DATA_MODEL.md)
- [Offline et synchronisation](docs/OFFLINE_SYNC.md)
- [Sécurité et confidentialité](docs/SECURITY.md)
- [Plan de développement et décisions ouvertes](docs/DEVELOPMENT_PLAN.md)

## Démarrer

Prérequis : Flutter 3.47.6 (stable), JDK 17, Android SDK.

```sh
flutter pub get                 # génère aussi lib/l10n/generated
dart run build_runner build     # génère le code Drift (*.g.dart)
flutter analyze
flutter test
flutter run
```

## Contenu pédagogique

Le contenu (diagnostic, quêtes, missions) s'écrit en YAML dans `content/`,
puis se compile dans le pack embarqué :

```sh
dart run tool/content_build.dart          # valide et écrit assets/content/base_pack.json
dart run tool/content_build.dart --check  # CI : échoue si le pack n'est pas à jour
```
