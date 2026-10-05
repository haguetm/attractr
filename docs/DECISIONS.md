# Décisions validées (complément à SPEC.md)

Réponses aux ambiguïtés relevées lors du cadrage. Validées le 2026-10-05. En cas de conflit avec SPEC.md, ce fichier fait foi ; toute nouvelle décision s'ajoute ici.

## Matching
- **Q1 – Comptes mixtes Bière + romantique** : la compatibilité est évaluée croisement par croisement. Structure et composition ne s'appliquent qu'aux croisements romantiques (Vin, Café, Cocktail). Le match enregistre la boisson qui a matché ; le feed l'affiche (« compatible en Bière »).
- **Q2 – Genres en Bière** : champ séparé « genres pour l'amitié » (défaut : tous). Les genres recherchés romantiques ne s'appliquent qu'aux croisements romantiques.
- **Q3 – Cohérence situation / structure** : « en relation avec accord » n'autorise que Relation ouverte, Polyamour ou Ouvert à voir.
- **Q4 – « Je cherche » polyamour** : filtre additionnel aux genres recherchés. « Ouverte au polyamour » = structure Polyamour ou Ouvert à voir.
- **Q5 – Genre** : liste fermée (femme, homme, personne non binaire) + précision libre affichable sans effet sur le matching. Les genres recherchés utilisent la même liste.
- **Q6 – Rayon** : réciproque (les deux rayons doivent être respectés), sauf pendant l'élargissement automatique.
- **Q7 – Profils déjà vus** : un profil passé revient après N jours (`app_config`) ; un profil liké ne revient jamais.
- **Q8 – Couples et Bière** : un individu en Bière voit les comptes couple en Bière sans avoir coché « ouvert aux couples » (la case ne concerne que les croisements romantiques).

## Profil et inscription
- **Q9 – Bio** : bio individuelle facultative, 300 caractères maximum (`app_config`).
- **Q10 – Filtres avancés** : études, taille, centres d'intérêt ajoutés comme champs de profil facultatifs.
- **Q11 – Non vérifiés** : un profil dont le selfie est en attente peut liker et apparaître dans le feed ; le badge « vérifié » est visible ; « qui t'a liké » n'affiche que les profils vérifiés.
- **Q12 – Délai de 7 jours sur la boisson** : ni le choix initial ni un changement forcé (passage en couple fermé) ne déclenchent le délai.
- **Q13 – Authentification** : connexion par SMS (OTP via Supabase Auth), un compte par numéro. Apple / Google plus tard, avec numéro obligatoire.

## Likes, chat, modération
- **Q14 – Délai de 24 h** : n'importe lequel des deux peut écrire en premier ; à l'expiration le match expire ; une prolongation gratuite de 24 h (nombre et durée dans `app_config`).
- **Q15 – Intention trompeuse** : seuils dans `app_config` ; défaut : avertissement au 3ᵉ signalement validé, suspension au 4ᵉ.
- **Q16 – Badge d'activité** : « a répondu à au moins un message dans les 72 h » (seuil dans `app_config`).
- **Q17 – Blocage dans un groupe** : la personne qui bloque quitte le groupe ; elle peut signaler en parallèle.
- **Q18 – Acceptation dans un groupe de potes** : le créateur choisit le mode à la création (majorité stricte des membres ou administrateur désigné) ; demande expirée après 48 h (`app_config`).

## Parrainage
- **Q19** : parrain abonné → filleul 1 mois de Premium offert ; parrain non abonné → filleul 50 % sur le premier paiement. Montant de la réduction du parrain non abonné et règle de cumul dans `app_config`.
- **Q20** : les mois offerts passent par les *promotional entitlements* RevenueCat (droit Premium accordé côté serveur), pas par les offres promotionnelles des stores. À valider juridiquement.

## Conformité
- **Q21 – Pays** : le pays est celui de la position, géocodé côté serveur. Champs désactivés dans un pays = ni demandés ni utilisés pour le matching.
- **Q22 – Compte mineur supprimé** : on conserve uniquement l'empreinte de visage du prestataire et un hash du téléphone, pour une durée limitée (`app_config`), afin d'empêcher la réinscription. À valider juridiquement.
- **Q23 – Blocage des contacts** : numéros hachés sur l'appareil, comparés côté serveur, carnet jamais stocké. Usage limité au blocage.

## Boissons (libellés)
- Le sens de Cocktail est « relation purement sexuelle », mais le texte affiché est adouci pour les stores (ex. « Rencontre sans engagement »). Libellé dans le fichier i18n, à trancher avant publication.

## Indicateur de popularité (Premium)
- **P1** : trois niveaux (peu, moyen, beaucoup) ; rien n'est affiché au niveau moyen.
- **P2** : calcul relatif aux profils de même zone et même boisson, sur 7 jours glissants. « Beaucoup » = 20 % les plus likés, « peu » = 20 % les moins likés (`app_config`).
- **P3** : rien n'est affiché si le profil a moins de 7 jours ou moins de N vues (`app_config`).
- **P4** : les likes obtenus pendant un boost sont exclus du calcul.
- **P5** : la personne voit son propre niveau dans ses statistiques Premium.
- **P6** : jamais d'indicateur pour les profils en incognito ; les couples suivent la même règle que les individus.

## Phase 1 (validées le 2026-10-06)
- Monorepo npm (pas pnpm).
- Écrans 5 à 8 de l'inscription enregistrés ensemble (`set_my_intent`) car leurs règles se croisent.
- « Je cherche » (polyamour) à choix multiples.
- Orientation choisie dans une liste (`orientation_labels`), pas en texte libre.
- Date de naissance non modifiable une fois saisie.
- Conditions et confidentialité retirées uniquement par suppression du compte ; retrait du consentement « données sensibles » = effacement de ces données.
- Pays déterminé côté serveur (géocodage), jamais envoyé par l'appli.
- Valeurs : `popularity.min_views` 50, `feed.pass_recycle_days` 30, `compliance.minor_trace_retention_days` 365, journal d'accès conservé 1 an.

## Phase 2 (proposées, en attente de validation)
- **Position demandée juste après l'écran 1** (avant les questions sensibles) : le pays décide quels champs existent (Q21).
- **Les genres recherchés restent en mémoire jusqu'au consentement** (écran 3) ; si l'appli est fermée entre les deux, l'écran 2 est redemandé. Rien de sensible n'est stocké sur le téléphone.
- **Changements de boisson libres pendant l'inscription** : le délai de 7 jours ne s'applique qu'après (Q12).
- **Photos : 2 minimum, 6 maximum** (`photos.min_count`, `photos.max_count`, provisoire). Stockage privé, URL signées.
- **Selfie pris uniquement avec la caméra frontale**, jamais depuis la galerie ; il passe en « en attente » jusqu'à la phase 5.
- **Compte couple affiché « bientôt disponible »** jusqu'à la phase 9.
- **Code de parrainage enregistré tel quel** (`private.signup_referrals`), résolu en phase 7.
- **Icônes de boissons provisoires** (émojis, avec variante sans alcool) en attendant un jeu d'icônes dessiné.
- **Libellé Cocktail affiché** : « Rencontre sans engagement ».

## Réponses du 2026-10-07
- **Q24** : réduction de 10 % pour le parrain non abonné (`referral.non_subscriber_referrer_discount_pct`, provisoire).
- **Q25** : V1 centrée sur la France ; aucun pays restreint pour l'instant. La liste sera à établir avant toute ouverture hors de France.
- **Q27** : seul `Logo.jpg` est utilisé (icône, écran de démarrage, connexion). Source : `docs/brand/logo.jpg`.

## Publicité (Q28, 2026-10-07)
- **Pas de publicité tant que l'appli n'est pas déployable.** Rien n'est développé d'ici là.
- Ensuite : publicité **légère et fermable**, pour les **non-abonnés uniquement** (Premium = sans publicité), à plusieurs endroits de l'appli.
- Ciblage (personnalisé ou non) : **à décider plus tard**. Contrainte déjà posée : aucune donnée sensible ne sort vers un tiers, donc aucun ciblage fondé sur le profil ; un ciblage personnalisé exigerait un consentement dédié (et l'App Tracking Transparency sur iOS).
- À cadrer avant l'implémentation : emplacements exacts (jamais à l'intérieur d'une conversation ?), régie et contrat de traitement, impact sur l'analyse d'impact RGPD.
