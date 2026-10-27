# Textes légaux : sources et obligations (2026-10-27)

Décision du porteur (2026-10-24) : pas de juriste ; textes rédigés à partir
des lois fournies par le porteur, du RGPD et des règles Google Play.
Brouillon dans `content/legal.yaml` (statut `pending` tant que le porteur
ne l'a pas validé). Ceci n'est pas un avis juridique.

## Sources (textes fournis par le porteur)

| Texte | Articles utilisés |
|---|---|
| Loi n° 2014-038 du 9 janvier 2015, protection des données | 5-6 (champ), 9-10 (responsable, sous-traitant), 13 (consentement), 14 (principes), 15 (sécurité), 16 (sous-traitance), 17 (bases légales), 18 (données sensibles), 20 (transferts), 22-25 (droits), 27 (information), 43-52 (formalités, délégué), 53 (délégué résidant, distinct du responsable) |
| Loi n° 2014-024, transactions électroniques | 13 (contrat électronique), 16 (conditions mises à disposition), 17 (acceptation) |
| Loi n° 2015-014, protection des consommateurs | 5 (langues : malagasy, français ou anglais), 31 (coordonnées et adresse du professionnel), 43 et 90 (clauses abusives) |
| Loi n° 2014-006, cybercriminalité | 6-12 (accès et atteintes frauduleux), 40 (remise d'une convention de déchiffrement : Eripoo ne détient pas les clés) |
| Loi n° 94-036, propriété littéraire et artistique | 1 (droit de l'auteur), 9 (qualité d'auteur), 19 (logiciel) |
| RGPD (UE) 2016/679 | 3.2, 6, 13, 15-21, 27, 28, 32 |
| Google Play, suppression de compte | [aide Play Console](https://support.google.com/googleplay/android-developer/answer/13327111) |

Décret n° 2023-1541 : abrogé (information du porteur, 2026-10-27).
Majorité : 18 ans (information du porteur) ; âge minimum choisi : 18 ans.

## À faire par le porteur avant l'ouverture au public

1. **Adresse postale** de l'éditeur (loi 2015-014, art. 31) : à ajouter
   aux deux textes.
2. **CMIL** : déclarer le traitement avant sa mise en œuvre (loi 2014-038,
   art. 43 et 45), sauf désignation d'un délégué à la protection des
   données (art. 52). L'article 51 prévoit que tout responsable en désigne
   un ; il doit résider à Madagascar et ne peut pas être le responsable
   lui-même (art. 53). Point à trancher par le porteur. Les sanctions du
   défaut de formalités sont à l'art. 62.
3. **Transfert vers la France** (art. 20) : la similarité du RGPD est une
   appréciation de l'éditeur, pas une décision de la CMIL (NON VÉRIFIÉ) ;
   l'exception de l'art. 20-b (exécution du contrat) est aussi invoquée.
4. **RGPD** : si Eripoo vise des personnes dans l'UE, désigner un
   représentant dans l'UE (art. 27), sauf traitement occasionnel.
5. **Google Play** : publier la politique de confidentialité à une adresse
   web publique ; offrir une page web de demande de suppression de compte
   en plus de la suppression dans l'app (déjà présente) ; remplir le
   formulaire « Sécurité des données ».
6. **Âge** : l'app ne vérifie pas encore l'âge (le type `AgeBracket`
   existe mais n'est utilisé nulle part) ; une confirmation « J'ai 18 ans
   ou plus » est à ajouter avant la validation des textes.
7. Relire, puis passer `status: validated` dans `content/legal.yaml`.
