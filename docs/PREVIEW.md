# Aperçu web (tests du porteur)

But : tester les écrans et les parcours dans un navigateur, sans
téléphone. Ce n'est **pas** une version web d'Eripoo.

- Point d'entrée séparé : `lib/preview/main_preview.dart`. L'app Android
  (`lib/main.dart`) n'est pas modifiée.
- Base SQLite en mémoire (WebAssembly), **non chiffrée**, effacée à la
  fermeture de la page. Pas de compte, pas de serveur Supabase, pas de
  voix, pas de biométrie. Données fictives uniquement.
- Construction : `tool/build_preview.sh` (sortie `build/web`, moteur
  CanvasKit seul, `sqlite3.wasm` épinglé par empreinte SHA-256).
- Publication : page privée claude.ai du porteur, republiée après chaque
  correction.
