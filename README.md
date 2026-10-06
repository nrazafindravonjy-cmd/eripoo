# Eripoo

> Mihary ho an'ny ho avy.

Application Android (Flutter) d'accompagnement à la construction de projets
entrepreneuriaux, pensée pour Madagascar, offline-first, en malagasy,
français et anglais.

**État : Phase 1 — design system implémenté, en attente de validation.**
Aucune fonctionnalité produit n'est encore implémentée.

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
flutter pub get        # génère aussi lib/l10n/generated
flutter analyze
flutter test
flutter run
```
