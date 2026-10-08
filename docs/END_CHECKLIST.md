# Eripoo — Vérifications et modifications à faire à la fin

Liste compilée des points laissés ouverts pendant les Phases 2 à 8, pour
les traiter ensemble quand les appareils, le projet Supabase en ligne et
les avis extérieurs seront disponibles. Chaque ligne renvoie à sa source.
Rien ici n'est déclaré fait tant que la case n'est pas cochée avec une
preuve (mesure, capture, journal de CI, avis écrit).

État au 2026-10-08 (fin de la Phase 8 livrée pour revue).

## 1. À fournir par le porteur du projet (bloquant)

- [ ] **Appareils de référence A et B** (puis C à E si possible) —
  DEVELOPMENT_PLAN P7 / D11. Toute la section 2 en dépend.
- [ ] **Projet Supabase de développement en ligne** (pas la production) —
  P4. Toute la section 3 en dépend. Clés dans les secrets de CI et le
  fichier local non versionné, jamais dans Git.
- [ ] **Avis juridique** — P6 / D12 :
  - [ ] utilisateurs mineurs de 14 à 17 ans (avant tout onboarding de
    mineurs) ;
  - [ ] transferts de données hors de Madagascar (loi 2014-038) ;
  - [ ] données de tiers dans les interviews ; **aucun enregistrement
    audio** des personnes interrogées tant que l'avis n'est pas rendu
    (le guide d'interview dit « n'enregistre personne ») ;
  - [ ] **contenu réglementaire de la préparation administrative**
    (`content/formalization.yaml`, sources EDBM lues le 2026-10-08) :
    relecture complète avant publication, y compris les traductions ;
  - [ ] licence de SQLite3MultipleCiphers dans la distribution complète
    (mentions dans l'app relues par un juriste) — P3.
- [ ] **Relecteurs natifs malagasy** — P9 / D13 : 520 chaînes d'interface
  `needs_review` (`lib/l10n/mg_review_status.json`) et tout le contenu
  malagasy en `machine_draft` (quêtes, missions, sections, outils, guide
  de financement, contenu réglementaire).
- [ ] **Auteurs du contenu** — D14 : relecture du français et de
  l'anglais ; validation des quêtes, missions, sections du projet, **règles
  de déblocage des outils** et textes des outils, sections amenées par
  les outils (modèle économique, marketing, pitch, résumé, lancement),
  guide de financement ; avis d'entrepreneurs malgaches sur les exemples.
- [ ] **Informations de financement sourcées** — §18/§49 : organismes,
  taux, conditions (microfinance, banques, concours, incubateurs) ;
  aujourd'hui Eripoo ne cite **aucun** organisme ; à ajouter seulement
  vérifiés, sourcés et datés (avec la Phase 8).
- [ ] **Région Supabase de production** — P5 / D9 (après mesures depuis
  Madagascar et l'avis juridique).

## 2. Sur appareils réels A et B (NON VÉRIFIÉ à ce jour)

Procédure : [DEVICE_TESTS.md](DEVICE_TESTS.md) §1 et §3.

Socle (Phase 2) :
- [ ] mesures Argon2id et ouverture de la base chiffrée → choix définitif
  des paramètres (V7 : 3 passes / 64 Mio, planchers 2 / 32 Mio) ;
- [ ] biométrie réelle, Keystore matériel, verrou applicatif ;
- [ ] processeur ARM 32 bits (A), vrai 1 Go de RAM, autonomie, ANR sous
  charge, absence de gel avec 5 000 éléments ;
- [ ] lisibilité en extérieur, palette et design system (P10).

Parcours (Phases 3 et 4) :
- [ ] « Ma quête » de bout en bout : lisibilité, rythme, compréhension ;
- [ ] photos chiffrées : prise de vue, gel d'interface avec un fichier de
  10 Mo.

Synchronisation et appareils (Phase 5) :
- [ ] lecture des QR avec la vraie caméra (lumière faible, écran de l'autre
  téléphone, distance) ; permission caméra accordée puis refusée ;
- [ ] `FLAG_SECURE` : capture d'écran refusée, aperçu des applications
  récentes masqué sur les écrans de clé et de code ;
- [ ] WorkManager réellement lancé application fermée (et retardé par
  l'économie de batterie) ;
- [ ] envoi des photos en Wi-Fi seulement, puis avec le réglage « données
  mobiles » ;
- [ ] transfert complet A → B par double QR, puis par code de secours.

Outils (Phase 6) :
- [ ] pastille de l'onglet Outils et célébration (lisibles, non
  envahissantes, désactivation respectée) ; lecteur d'écran TalkBack sur
  l'onglet (la pastille n'est pas annoncée vocalement : les cartes
  portent la mention « Nouveau »).

Finance et documents (Phase 7) :
- [ ] saisie des montants au clavier numérique (espaces, points) et
  lisibilité des résultats sur petit écran ;
- [ ] partage du PDF vers une vraie application (messagerie, Drive,
  impression) ; rendu des caractères malagasy ; taille du fichier ;
- [ ] effacement de la copie de partage au démarrage suivant (cache
  `share_plus`) ;
- [ ] diapositives lisibles une fois projetées ou montrées sur un
  téléphone.

## 3. Contre le projet Supabase de développement en ligne

- [ ] suite de contrat RPC et Storage (aujourd'hui passée sur Supabase
  local en CI) ;
- [ ] tests pgTAP RLS sur le projet en ligne ;
- [ ] connexion par e-mail depuis l'APK de développement ;
- [ ] synchronisation de deux téléphones réels, transfert, médias ;
- [ ] révocation d'un appareil (effacement local, session refusée).

## 4. Fonctionnalités à construire avant la production

- [ ] **déconnexion avec effacement local** — Phase 5, non faite ;
- [ ] **suppression de compte** (Edge Function, effacement serveur et
  local) — Phase 2, non faite ;
- [ ] **notification « Nouvel appareil ajouté »** aux autres appareils et
  par e-mail (SECURITY §6.8) — l'événement est enregistré côté serveur,
  rien n'est envoyé ;
- [ ] **quota de stockage des médias** par utilisateur — non appliqué ;
- [ ] **confirmation d'identité par le verrou Eripoo** quand le téléphone
  n'a pas de verrouillage (aujourd'hui : verrouillage du téléphone) ;
- [ ] **message après effacement** au redémarrage (appareil révoqué ou
  effacé : dire clairement ce qui s'est passé) ;
- [ ] **badges** (§21) : non faits ; mêmes règles et même validateur que
  les outils ;
- [ ] **préparation administrative** — construite en Phase 8 ; à
  compléter : liste officielle pour l'entreprise individuelle, autres
  régions que l'Analamanga, sources fiscales et sociales directes
  (`impots.mg`, `cnaps.mg` injoignables pendant la collecte), codes
  d'activité (NOMAC) ; relire les sources tous les trois mois et à chaque
  loi de finances (`dart run tool/check_sources.dart`) ;
- [ ] **chapitre « Marché »** du dossier : absent, aucune donnée
  de marché n'est recueillie par les quêtes actuelles (à prévoir dans le
  contenu) ;
- [ ] **niveau de préparation** (§23, « éventuellement ») : non fait ;
- [ ] **associés** (§48) : aide à la recherche d'associé non faite ;
- [ ] **plusieurs scénarios de prix** : un seul plan par projet
  aujourd'hui (DATA_MODEL v7) ; à rouvrir si les utilisateurs le
  demandent ;
- [ ] **16 quêtes minimum** (4 écrites à ce jour, plus le diagnostic) ;
- [ ] édition du contenu hors du dépôt (D5) avant la production ;
- [ ] **rotation de l'UMK** avant le lancement public (D17, Phase 10).

## 5. Pas encore commencé, volontairement

Ne pas démarrer sans décision explicite : environnement Supabase de
production, analytics de production (D7), fournisseur SMS (D10),
connexion Google et par téléphone, transcription et IA (Phase 9),
identifiant Android définitif (D6), publication Play Console.

## 6. Mesures sur émulateur

- [x] DEVICE_TESTS §2quater relevé (run CI 48, 2026-10-07) : gel
  d'interface à 10 Mo sous 0,1 s, transfert complet 18–37 ms, lecture
  d'un QR 640×480 58–87 ms. Reste à refaire sur A et B (section 2).
