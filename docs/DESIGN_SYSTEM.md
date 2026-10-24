# Eripoo — Design system

Statut : **refonte visuelle du 2026-10-23** (direction du porteur). Code
dans `lib/design_system/`.

Direction : UI premium, minimaliste et immersive. **Mode sombre uniquement**
(le réglage clair/sombre a été retiré), palette de marque **#232123** (fond)
et **#FDCB20** (jaune, actions principales), typographies **Instrument
Serif** (titres, voix de la marque) et **Jost** (texte et libellés), toutes
deux embarquées sous licence SIL OFL (`assets/fonts/`). Cartes épurées sans
bordure sur une surface légèrement plus claire, boutons en pilule,
micro-interactions discrètes. Logo officiel tracé en vecteur
(`EripooLogo`), icône Android et écran de démarrage générés depuis le
fichier du porteur. Les « visuels 3D organiques » sont des formes douces en
dégradé dessinées en code (`EripooOrganicShape`) : légères, nettes, sans
image lourde ; remplaçables par de vrais rendus plus tard.

**Signature visuelle (validée le 2026-10-23)**, construite sur la forme du
logo : coin bas-droit coupé en diagonale sur toutes les cartes, boutons,
dialogues et confirmations (`EripooCutBorder`) ; titres éditoriaux avec mot
clé en italique jaune (`EripooHeadline`, marqueurs `*…*` dans les ARB) ;
jaune réservé à l'action ou l'information principale (boutons secondaires
et liens en blanc, suppression en contour) ; grain très léger sur toute
l'app (`EripooGrain`, dessiné une fois) ; formes organiques derrière les
états vides et d'erreur ; parcours des quêtes et des étapes en chemin de
marques du logo (`EripooPathItem`) ; onglet actif posé sur une marque du
logo ; transitions de page en diagonale, pression des cartes et validation
d'étape par l'apparition du logo (`EripooDoneMark`), toutes coupées quand
l'utilisateur réduit les animations.

**Accueil et parcours (2026-10-23)**, inspirés de références sans les
copier : salutation selon l'heure avec le nom du projet (aucun prénom
demandé) ; carte héros jaune avec la quête en cours, sa progression
dessinée sur le contour du logo (`EripooProgressMark`) et une seule
action ; quatre chiffres du projet en grille (`EripooStatCard` : étapes,
hypothèses validées, notes de terrain, prix ; badge « +N cette semaine »
en texte, jamais culpabilisant) ; frise des 7 derniers jours
(`EripooWeekStrip`, sans série à tenir) ; logo géant en filigrane ;
bouton principal avec pastille fléchée, fixé en bas des étapes et de
l'écran de bienvenue ; options de réponse en tuiles à coin coupé, deux
par ligne quand les libellés sont courts, avec marque du logo pleine ou
vide.

**Deuxième série de références (2026-10-23)** : carte « prêt à terminer »
en fin d'étape (enregistré sur le téléphone, chiffré) ; filtres en
pastilles à coin coupé retirables d'un geste, conservés au retour
(hypothèses) ; barre flottante pendant une sélection (`EripooSelectionBar`,
corbeille : « Restaurer N ») ; carte d'identité du projet partageable en
image (exactement la carte affichée, sans réponse privée) ; outils en
grille, le plus utile en pleine largeur ; champ de réponse avec l'action
« Répondre à l'oral » à l'intérieur ; forme organique qui respire pendant
l'enregistrement (`EripooListeningShape`) ; titres de quête en deux tons
(« *Quête 3* » puis l'objectif).

**Troisième série de références (2026-10-23)** : feuille jaune de
célébration à la fin d'une quête (`showEripooCelebration`, une fois, une
action) ; repères chiffrés en tête de quête (`EripooMetrics` : étapes,
stade, missions — aucune durée inventée, le contenu n'en donne pas) ;
lignes de navigation à flèche (`EripooNavRow`, onglet Projet) ; étapes
avec vignette organique et type (Apprendre, Agir…) ; grand chiffre serif
de progression dans l'étape (`EripooStepCounter`) ; « Retour » et
« Suivant » côte à côte ; jauge de confiance des hypothèses avec un mot au
centre ; pastilles Tout / Observations / Rencontres dans les notes de
terrain. Les 69 règles
UX/UI transmises par le porteur s'appliquent à tous les écrans ; l'audit
écran par écran est en cours (NEXT_STEPS, chantier C-15).

---

## 1. Règles

| Règle | Comment elle est garantie |
|---|---|
| Aucune couleur codée en dur hors des tokens | test `test/architecture/source_rules_test.dart` (seuls `eripoo_colors.dart` et `eripoo_theme.dart` peuvent définir des couleurs) |
| Aucune chaîne visible codée en dur | même test (interdit `Text('…')` avec littéral) ; les textes viennent des ARB ou du contenu |
| Domaine et `core` en Dart pur | même test (pas d'import `package:flutter/` dans `lib/core` et `features/*/domain`) |
| Pas de `print` | même test + lint `avoid_print` |
| Contraste WCAG AA | `test/design_system/contrast_test.dart` (calcul sur chaque paire de tokens) + `textContrastGuideline` sur tous les composants |
| Cibles tactiles ≥ 48 dp, actions principales 56 dp | `androidTapTargetGuideline` sur tous les composants |
| Tout élément interactif a un libellé | `labeledTapTargetGuideline` |
| Texte agrandi jusqu'à 200 % sans débordement | matrice de tests à `textScaler` 2,0 |
| Sombre, téléphone et tablette, fr/en | matrice 1 × 2 × 2 = 4 variantes, chacune à 100 % et 200 % |
| Navigation lisible | chaque libellé tient sur une ligne à 360 dp en fr et en |

Ces tests ont été vérifiés comme **capables d'échouer** : une violation
volontaire (couleur, texte, import, `print`) et l'ancien style de navigation
(qui coupait « Fandraisana ») les font bien échouer.

## 2. Tokens

### 2.1 Couleurs (`EripooColors`, `ThemeExtension`)

| Rôle | Clair | Sombre | Usage |
|---|---|---|---|
| `background` | `#FAFAF7` | `#121412` | fond de page |
| `surface` | `#FFFFFF` | `#1A1C1A` | cartes, feuilles, navigation |
| `surfaceMuted` | `#F2F2EE` | `#242723` | zones calmes (aide, pistes inactives) |
| `border` | `#D9D9D2` | `#4A4E48` | séparateurs décoratifs |
| `borderStrong` | `#7D7F78` | `#7E8179` | bord des champs et boutons secondaires (≥ 3:1) |
| `textPrimary` / `textSecondary` | `#1B1C1A` / `#5C5E58` | `#ECEDE8` / `#B0B2AB` | textes (≥ 4,5:1 sur toutes les surfaces) |
| `brand` | `#0B6E5F` | `#5CCFB9` | action principale, focus, progression |
| `accent` | `#E8A317` | `#F5BE4A` | célébrations, badges — **jamais en texte sur une surface** |
| `success`, `warning`, `danger`, `info` | voir `eripoo_colors.dart` | | états |

Chaque teinte a 4 valeurs : `base`, `onBase`, `container`, `onContainer`.
Ratios de contraste mesurés : tous les textes ≥ 4,5:1 (de 5,4:1 à 17:1),
bords de contrôle ≥ 3:1.

### 2.2 Typographie (`EripooTypography`)

Police système (Roboto sur Android) : **aucune police embarquée** (taille
de l'APK, démarrage). Corps de texte à **17 sp** (un peu plus grand que le
standard Material) pour la lisibilité. Échelle : 32 / 26 / 22 / 20 / 17 / 15
/ 13 sp ; libellés 16 / 14 / 12 sp. Tout suit la taille de police du
système.

### 2.3 Espacements, rayons, mise en page, mouvement

- Espacement (grille de 4 dp) : 2, 4, 8, 12, 16, 24, 32, 48.
- Rayons : 8, 12, 16, 24, pilule.
- Mise en page : cible tactile 48 dp, action principale 56 dp, marges
  16 dp (téléphone) / 24 dp (tablette), colonne de lecture max 640 dp.
- Mouvement : 120 / 200 / 320 ms, courbes douces ; **tout passe à 0** si
  l'utilisateur réduit les animations (réglage système ou réglage Eripoo,
  appliqué via `MediaQuery.disableAnimations`, source unique).

## 3. Composants (`lib/design_system/components/`)

| Composant | Rôle |
|---|---|
| `EripooButton` | 4 variantes (principal, secondaire, tertiaire, danger), icône, état « en cours » lisible (pas grisé) qui ignore les appuis, pleine largeur |
| `EripooCard` | surface à bordure, cliquable avec libellé pour lecteur d'écran |
| `EripooTextField` | libellé toujours visible, mention « facultatif » localisée, erreur écrite (pas seulement en couleur) |
| `EripooProgress` | progression « 4 / 12 » + barre ; annoncée « 4 sur 12 » ; mesure le travail fait, jamais une chance de réussite |
| `EripooStepTrack` | suite d'étapes (ex. maturité du projet) ; seul le nom de l'étape courante est affiché, pour tenir sur téléphone |
| `EripooBadge` | médaillon ; les badges à obtenir restent visibles (grisés, cadenas) |
| `showEripooConfirmDialog`, `showEripooSheet` | confirmation (renvoie `true` seulement sur confirmation explicite), feuille modale défilante |
| `EripooLoadingView`, `EripooErrorView`, `EripooMessageView`, `EripooOfflineBanner` | états chargement / erreur (rassurant : « tes données sont en sécurité ») / message / hors ligne (calme) |
| `EripooHelpButton` + `HelpAction` | « Besoin d'aide ? » → Je ne sais pas, Je ne comprends pas, Voir un exemple, M'aider, Passer pour l'instant, Revenir plus tard. Le composant **rapporte seulement le choix** : la suite est décidée par le moteur de parcours (Phase 3) |
| `AdaptiveScaffold` | barre de navigation en bas (< 600 dp) ou rail latéral (≥ 600 dp) |
| `ReadableColumn` | marges et largeur de lecture maximale |
| `WindowSize` | classes de largeur compacte / moyenne / étendue |

Formatage (`lib/core/format/eripoo_formatter.dart`, Dart pur) : montants
entiers en ariary (« 15 000 Ar »), nombres, pourcentages, fractions
insécables, dates longues et courtes, jours, durées, pour mg/fr/en, sans
dépendre des symboles `intl` (absents pour `mg`).

## 4. Navigation

- Coquille à 5 onglets (Accueil, Ma quête, Projet, Outils, Profil) avec
  `go_router` (`StatefulShellRoute`, état de chaque onglet conservé).
- Chaque onglet affiche pour l'instant un écran **honnête** « Pas encore
  disponible » (`SectionPlaceholderScreen`), remplacé dans sa phase.
- **Orientation** : l'app demande le mode portrait. Mais pour les apps
  ciblant Android 16 (API 36, cible actuelle de Flutter 3.47), le système
  **ignore** le verrouillage d'orientation sur les grands écrans (≥ 600 dp
  de petite dimension) ([Android Developers](https://developer.android.com/develop/adaptive-apps/guides/app-orientation-aspect-ratio-resizability),
  [annonce](https://android-developers.googleblog.com/2025/01/orientation-and-resizability-changes-in-android-16.html)).
  Une tablette peut donc être en paysage : toutes les mises en page
  dépendent uniquement de la largeur disponible, et un test couvre la
  tablette en paysage.

## 5. Chaînes du framework Flutter visibles (inventaire)

**Phase 10** : ces chaînes ont une version malagasy (premier jet, à
relire) dans `lib/l10n/mg_material_localizations.dart` ; le reste des
chaînes Material (sélecteurs de date et d'heure, tableaux, noms de
touches — non utilisés) et les formats de date restent en **français**.
Cupertino (non utilisé sur Android) reste en français.

| Chaîne (`MaterialLocalizations`) | Où | Visible / lue |
|---|---|---|
| `copyButtonLabel`, `cutButtonLabel`, `pasteButtonLabel`, `selectAllButtonLabel` (+ recherche, partage selon l'appareil) | menu contextuel des champs de texte | **visible** |
| `backButtonTooltip` | bouton retour des écrans imbriqués (Phase 3+) | lue (info-bulle) |
| `modalBarrierDismissLabel`, `scrimLabel`, `scrimOnTapHint` | fond des dialogues et feuilles | lue |
| `alertDialogLabel` | dialogues | lue |
| `bottomSheetLabel` | feuilles modales | lue — **non traduite même en français** dans Flutter 3.47 (« Bottom sheet ») |
| `closeButtonTooltip` | bouton fermer (si utilisé) | lue |
| Sélecteurs de date et d'heure | non utilisés à ce stade | — |

Traduits en Phase 10 : menu contextuel des champs, boutons et libellés
lus, dialogues et feuilles (dont `bottomSheetLabel`), compteur de
caractères, page des licences.

## 6. Traductions malagasy

Aucune traduction actuelle n'est définitive. Trois statuts (détail dans
[DEVELOPMENT_PLAN P9](DEVELOPMENT_PLAN.md#p9--d13--relecture-native-du-malagasy-)) :
**validé** (nom et slogan, fournis par le porteur), **proposition à relire
par un locuteur natif** (toutes les autres chaînes malagasy, mois, jours,
« ora »), **proposition à valider par le porteur** (textes fr et en). Leur statut est suivi dans `lib/l10n/mg_review_status.json` ;
un test oblige à y déclarer chaque nouvelle clé. Points d'attention pour la
relecture : « Ny diako » pour « Ma quête », « Momba ahy » pour « Profil »,
les noms de mois et de jours, « ora » dans les durées, et le format
« 15 000 Ar » en anglais (« 15,000 Ar »).

## 7. Captures pour la revue visuelle

```sh
flutter test --tags screenshots --run-skipped --update-goldens
```

Produit dans `test/screenshots/goldens/` (non versionné) : composants en
clair et en sombre, coquille téléphone en malagasy, coquille tablette en
sombre, feuille d'aide. Rendu avec la vraie police Roboto du SDK Flutter.
Ce n'est pas un test de non-régression (les pixels varient selon les
machines) ; il est ignoré par défaut.

## 8. Non vérifié dans cette phase

- **Aucun test sur un vrai téléphone** : pas d'appareil de référence (D11)
  ni de SDK Android dans l'environnement de développement. Les mesures de
  fluidité et de démarrage restent à faire.
- **Build Android jamais exécuté** : ni localement (pas de SDK Android), ni
  en CI (la CI ne se déclenche que sur une pull request ou sur `main`).
- Relecture malagasy (D13).
- Les réglages (thème, langue, animations réduites) existent mais sont
  **en mémoire seulement** : ils sont perdus au redémarrage jusqu'à la base
  locale (Phase 2), et aucun écran ne permet encore de les changer.
- La palette est une proposition, non validée par des utilisateurs.

## Mascotte (test, 2026-10-24)

Eripoo, la mascotte, est un essai décidé par le porteur. Les quatre
expressions (`assets/mascot/`, WebP transparents d'environ 80 Ko) viennent
d'images générées par IA par le porteur, détourées à partir d'un fond vert.
`EripooMascot` les anime sans bibliothèque : quelques respirations à
l'apparition, un saut au toucher et en fin de quête, et aucune animation
quand elles sont réduites. Elle est décorative, donc masquée aux lecteurs
d'écran, et l'interrupteur « Mascotte » du Profil la retire partout.
Emplacements : bienvenue et introduction, en-tête des étapes, célébration de
fin de quête, mission terminée ou abandonnée, états vides et erreurs.
Droits sur des images générées par IA : **NON VÉRIFIÉ** (protection par le
droit d'auteur et conditions commerciales de l'outil à confirmer avant une
diffusion publique).
