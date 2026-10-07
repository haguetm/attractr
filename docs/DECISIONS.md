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

## Phase 3 (proposées, en attente de validation)
- **Réciprocité aussi sur l'âge** : un profil n'apparaît que si chacun est dans la tranche d'âge de l'autre (comme pour le rayon, Q6), sauf pendant l'élargissement automatique.
- **Élargissement automatique** : rayon doublé jusqu'à `feed.max_radius_km` (300 km) tant qu'il y a moins de `feed.min_results` (10) profils. Uniquement en recherche par rayon ; en département ou région, pas d'élargissement (message d'attente si vide).
- **Rayon par défaut 25 km**, choix proposés 5 à 300 km (`feed.default_radius_km`, `feed.max_radius_km`, provisoires).
- **Ordre du feed** : d'abord les personnes actives récemment, puis par distance. Le Boost (phase 7) passera devant.
- **Filtre boisson** (gratuit) : ne garde que les profils compatibles via au moins une des boissons choisies.
- **Badge d'activité, version provisoire** : « actif dans les 72 h ». Il deviendra « a répondu à un message dans les 72 h » quand le chat existera (phase 4, Q16).
- **Photos visibles par les autres** : seulement pour les profils que le feed leur a montrés dans les 24 h (et plus tard les matchs), via une URL signée. En attendant la modération (phase 5), seules les photos refusées sont masquées.
- **Département et région** déterminés côté serveur par le géocodage, comme le pays.
- **Blocages et signalements** : tables créées dès maintenant pour que le feed les exclue ; les actions et l'interface arrivent en phase 5.
- **« Tester en tant que »** : uniquement sur le Supabase local, avec `APP_ENV=development` et le drapeau `dev.impersonation_enabled` (activé par le seed local). La fonction n'est jamais déployée sur un projet hébergé (`npm run functions:deploy` l'exclut). Les profils fictifs ont un e-mail en `.test` pour cette connexion.
- **Environnement par défaut** : un projet hébergé sans `APP_ENV` est traité comme la production (versions factices refusées).

## Phase 4 (proposées, en attente de validation)
- **Un like vise toujours une photo ou une réponse** (le bouton principal « J'aime » vise la première photo, ou la première réponse s'il n'y a pas de photo).
- **On ne peut liker qu'un profil que le feed nous a montré**, ou quelqu'un qui nous a déjà liké (empêche de liker un identifiant au hasard).
- **« Réponses hors quota »** : liker en retour quelqu'un qui nous a déjà liké ne consomme pas le quota.
- **Quota glissant** : l'appli affiche les likes restants et l'heure à laquelle le prochain revient.
- **Premium** : table `private.entitlements` créée dès maintenant (likes illimités) ; elle sera alimentée par RevenueCat en phase 7.
- **Match expiré** (pas de premier message dans le délai) ou **annulé** (« Ne plus matcher ») : la conversation se ferme pour les deux et le profil ne revient pas dans le feed.
- **Relances** : rappel quand il reste 3 h pour le premier message, « À ton tour » après 24 h sans réponse (une seule fois par message). Valeurs dans `app_config`.
- **Notifications génériques** : aucun prénom ni contenu de message sur l'écran verrouillé (« Nouveau message — Ouvre Attractr pour le lire »).
- **Likes reçus en gratuit** : on indique seulement que des personnes ont liké, sans le nombre exact ni les profils (la liste est Premium, phase 7).
- **Badge d'activité** : il signifie désormais « a répondu dans le chat dans les 72 h » (Q16).

## Phase 5 (proposées, en attente de validation)
- **Contrôle d'âge** : une estimation sous 18 ans ne ferme jamais le compte automatiquement. Le profil est suspendu (invisible) et passe en revue humaine prioritaire ; seule la décision humaine ferme le compte (évite les faux positifs de l'IA).
- **Revue humaine aussi** pour : visage déjà utilisé par un autre compte, confiance de l'estimation sous 0,7, écart de plus de 5 ans entre âge déclaré et âge estimé (valeurs provisoires).
- **Selfie supprimé** dès qu'il est vérifié ou à reprendre ; conservé seulement le temps d'une revue humaine.
- **Photos** : rejet automatique au-delà de 0,9 (nudité ou violence), revue humaine entre 0,5 et 0,9, sinon acceptée. Les autres ne voient plus que les photos acceptées ; une photo refusée ne compte pas dans le minimum.
- **Signaler bloque aussi par défaut** (case cochée, décochable) et ferme le match. 10 signalements maximum par jour et par personne.
- **Sanctions automatiques sur signalement validé** : intention trompeuse (avertissement au 3ᵉ, suspension au 4ᵉ), suspicion de mineur (fermeture), arnaque / harcèlement / faux profil / pression d'un couple (suspension).
- **Arnaques, règles simples** : liens refusés dans les 3 premiers messages d'une personne dans une conversation ; demandes d'argent (virement, Western Union, cartes cadeaux, crypto…) délivrées mais envoyées en revue.
- **Blocage des contacts** : les empreintes SHA-256 des numéros sont calculées sur le téléphone, comparées puis oubliées ; la liste des contacts bloqués n'est jamais affichée (cela révélerait qui utilise l'appli).
- **Mode pause** : invisible dans le feed, matchs et conversations conservés.
- **Modération en V1 depuis l'éditeur SQL** de Supabase avec des fonctions journalisées (`docs/MODERATION.md`). Un back-office web reste à faire.
- **Réinscription bloquée** : un numéro dont le compte a été fermé pour minorité ne peut plus s'inscrire pendant la durée de conservation (hash HMAC avec un sel stocké dans Vault).

## Phase 6 (proposées, en attente de validation)
- **Ajout par lien** : le lien est à usage unique et valable 7 jours ; le partager vaut acceptation de son auteur, l'ouvrir vaut acceptation de l'autre (amitié immédiate). **Ajout par pseudo** : une demande que l'autre accepte ou refuse.
- **Pseudo** : uniquement pour s'ajouter en ami, jamais cherchable ni listé ; une recherche par pseudo inconnu ou indisponible donne la même réponse (on ne peut pas tester si quelqu'un est inscrit).
- **Ce qu'un ami voit de toi** : ton prénom et ton pseudo, rien d'autre (pas de photo ni de profil).
- **Bloquer quelqu'un met fin à l'amitié.**
- **Sortie** : une sortie prévue à la fois par match. Les 3 à 8 participants comptent les deux personnes matchées et toutes les invitations non refusées ; le minimum de 3 est indiqué (« invite un ami ») mais ne bloque pas la création.
- **Chacun n'invite que ses propres amis** ; les deux personnes matchées voient les prénoms des invités des deux côtés et leurs réponses.
- **Carte d'un ami** : jour, lieu, heure, les deux prénoms, qui l'invite, et le nombre de participants. Aucun identifiant, profil, boisson ni like.
- **Fin du match** (annulation, blocage) : la sortie apparaît annulée pour les invités.
- **Avis privé** : demandé 3 h après le début (provisoire), aux deux personnes matchées et aux amis venus ; note de 1 à 5 et commentaire, lisibles par l'équipe seulement.

## Phase 7 (proposées, en attente de validation)
- **Amitié avec le parrain** (réponse par défaut) : créée à la validation du filleul, avec les mêmes règles que toute amitié (selfies vérifiés, 10 amis maximum) ; ignorée silencieusement sinon.
- **Premium décidé par le serveur** à partir du webhook RevenueCat (idempotent), jamais par l'appli. Une résiliation garde Premium jusqu'à la fin de la période payée.
- **« Parrain abonné »** = abonnement payant en cours (pas un mois offert ni un test).
- **Mois offerts au parrain abonné : option B (validée le 2026-10-06).** Un **code d'offre store** (« 1 mois gratuit ») à utiliser au prochain renouvellement. Les codes sont générés dans App Store Connect / Google Play, chargés dans un stock (`private.load_offer_codes`), et attribués automatiquement selon le store où le parrain est abonné. Tant qu'aucun code n'est attribué, la récompense attend ; elle est perdue si l'abonnement expire avant. Le filleul d'un parrain abonné reçoit aussi un mois de Premium, accordé directement.
- **Parrain non abonné** : réduction de 10 % (ou 20 %, à décider ; `referral.non_subscriber_referrer_discount_pct`) sur son futur abonnement.
- **Réductions** (filleul -50 %, parrain non abonné -10 %) : enregistrées comme récompenses, utilisées au premier paiement ; elles passent par des offres promotionnelles à créer dans les stores.
- **Filtres Premium** ignorés dès que Premium s'arrête (les réglages sont gardés).
- **« Actifs récemment »** = actif dans les 3 jours (provisoire). **« Composition recherchée »** = filtrer les profils polyamoureux selon ce qu'ils cherchent.
- **Passeport** : uniquement en recherche par rayon ; la position réelle ne change pas.
- **Retour en arrière** : le dernier « passer » des dernières 24 h (provisoire).
- **Incognito** : visible seulement par les personnes qu'on a likées ; jamais d'indicateur de popularité.
- **Boost** : en tête de la zone (avant les personnes actives récemment), un à la fois, vues comptées une fois par personne et par jour. Boost mensuel Premium : le 1er de chaque mois (job quotidien).
- **Popularité** : calcul quotidien par département et boisson principale ; groupes de moins de 5 profils sans indicateur ; « beaucoup » = au-dessus du 80ᵉ centile, « peu » = sous le 20ᵉ.
- **Détails de profil** (études, taille, 5 centres d'intérêt max) : facultatifs, pour tout le monde ; seul le filtre est Premium.

## Phase 8 (proposées, en attente de validation)
- **Groupe romantique** : n'importe quel membre invite une personne qui a un match actif avec **tous** les membres ; elle accepte et entre (pas de vote : chacun a déjà matché avec elle). La règle est revérifiée au moment d'entrer (un match terminé entre-temps annule l'invitation).
- **Groupe de potes** : n'importe quel membre invite un de ses matchs Bière ; le vote de l'invitant compte. Majorité stricte des membres, ou l'admin seul selon le mode choisi à la création (Q18). Le refus est acquis dès que la moitié des membres a voté contre.
- **Un groupe se crée seul** puis on invite (pas de membres initiaux). Créateur Premium, avec la Bière pour un groupe de potes, une boisson romantique pour un groupe romantique.
- **Si le créateur n'est plus Premium** : la conversation continue, mais plus aucune nouvelle invitation (`groups.creator_only_premium`, provisoire).
- **Quitter** : le rôle d'admin passe au membre le plus ancien ; un groupe vide est fermé.
- **Invitation valable 7 jours** (provisoire).
- **Ce que voit l'invité avant d'entrer** : nom du groupe, type, taille, prénoms, et le profil de la personne qui l'invite (via leur match). **Ce que voient les membres d'un nouveau** : prénom et photo principale.

## Phase 9 (proposées, en attente de validation)
- **Modèle technique** : le profil commun est un profil à part entière (sans connexion possible), piloté par les deux partenaires, qui gardent leurs comptes individuels vérifiés. Feed, likes, matchs, chat, blocages et effacement fonctionnent ainsi pour les couples.
- **Invitation** par lien (valable 7 jours) ou par pseudo. Chemin B : le partenaire termine sa propre inscription puis ouvre le lien.
- **Publication** : profil commun rempli + au moins une photo commune acceptée par les deux et validée par la modération + les deux selfies vérifiés. Toute photo du profil commun demande l'accord de l'autre partenaire (on considère qu'elles montrent les deux).
- **Couple ouvert** : boissons libres selon la structure (relation ouverte, polyamour ou ouvert à voir). **Couple fermé** : Bière seule pour le couple et pour les deux profils individuels (changement forcé, sans délai de 7 jours).
- **Compatibilité avec un couple** : une personne seule doit avoir coché « ouvert aux couples » (sauf en Bière, Q8) ; le couple doit chercher « une personne » ou « un autre couple » ; genres recherchés croisés dans les deux sens (un couple = ses deux genres) ; structures compatibles. Pas d'appariement fin des compositions à plusieurs avec les couples (hors périmètre V1, passe par les groupes).
- **Âge d'un couple** pour les filtres : celui du plus jeune partenaire. Position : celle du partenaire qui a créé le couple.
- **Feed « Notre couple »** : chaque partenaire peut parcourir le feed au nom du couple ; « passer » ne demande pas d'accord, un like oui (proposition valable 3 jours, provisoire). Le quota de likes du couple est celui d'un compte gratuit (pas d'abonnement couple en V1).
- **Chat d'un match de couple** : les deux partenaires et la personne y participent, avec le bandeau « Les deux partenaires voient cette conversation » et le prénom de qui écrit.
- **Quitter** : un seul partenaire, un clic ; le profil commun, ses likes, matchs et conversations sont effacés. La suppression du compte d'un partenaire efface aussi le couple.
- **Signalement « pression exercée par un couple »** proposé quand la personne signalée est un compte couple.
- **Hors V1 pour les couples** : sorties à plusieurs et chats de groupe au nom du couple (chaque partenaire peut y participer avec son compte individuel).

## Phase 10 (proposées, en attente de validation)
- **Prestataire IA** : Claude (Anthropic), modèle `claude-opus-5-5` par défaut. Le modèle et le niveau d'effort se changent dans `app_config` (`ai.model`, `ai.effort`) sans redéploiement ; un autre prestataire = une nouvelle implémentation de `ProfileAnalysisProvider`.
- **Gratuit / Premium** : une seule analyse complète est calculée et mise en cache ; le gratuit voit le conseil principal (et ce que Premium débloque), le Premium voit tout. Passer Premium affiche l'analyse existante sans nouvel appel.
- **Limite** : une analyse tous les 7 jours (`ai.analysis_interval_days`, provisoire), pour tous. Un échec (prestataire, contrôle de sortie) ne compte pas.
- **Ce qui est envoyé** : jusqu'à 6 photos validées par la modération (`ai.max_photos`, provisoire), la bio, les réponses écrites et la boisson. Jamais le prénom, l'âge, le genre, la position ni les données sensibles.
- **Contrôle de sortie** : forme de la réponse vérifiée (chaque photo une fois, ordre complet, longueurs) et liste de termes interdits (beauté, corps, peau, âge, origine, orientation, santé, religion), sans accents ni majuscules. Une réponse rejetée est redemandée une fois, puis l'analyse échoue. **Exception** : la bio réécrite et les clichés cités peuvent reprendre un mot que la personne a écrit elle-même (ex. « croyante ») ; tout mot ajouté par l'IA est rejeté.
- **Rien ne change sans l'utilisateur** : la bio proposée est modifiable puis enregistrée par un bouton ; l'ordre conseillé s'applique par un bouton.
- **Conservation** : seule la dernière analyse est gardée ; effacée au retrait du consentement. Un consentement retiré pendant l'analyse fait jeter le résultat.
- **À faire avant la production** : demander la zéro rétention de données à Anthropic, l'ajouter au contrat de sous-traitance et à l'analyse d'impact RGPD (transfert hors UE possible).

## Phase 11 (proposées, en attente de validation)
- **Deux sources** : la rétention et les chiffres clés sont calculés côté serveur (référence, indépendante du consentement à la mesure d'audience) ; PostHog sert aux parcours dans l'appli. Détails : docs/METRICS.md.
- **Définition de la rétention** : J1 = actif le lendemain de l'activation ; J7 = actif au moins une fois entre J7 et J13 ; J30 = entre J30 et J36 (fenêtre de 7 jours, `metrics.retention_window_days`, provisoire). Jour 0 = fin de l'inscription. Jour actif = ouverture de l'appli, feed, like ou message (heure de Paris).
- **Les comptes supprimés restent comptés** dans leur cohorte, de façon anonyme (identifiant de mesure aléatoire dont le lien avec le compte est effacé). Profils fictifs et profils de couple exclus.
- **Segment** : boisson principale à l'activation uniquement. Cohortes de moins de 5 personnes masquées. Données brutes effacées après 400 jours (provisoire) ; totaux quotidiens conservés.
- **Tableau de bord** : page locale `tools/dashboard/index.html` qui lit la fonction `metrics`, protégée par un jeton dédié (`METRICS_DASHBOARD_TOKEN`), plutôt qu'un outil tiers branché sur la base.
- **PostHog sans SDK natif** : envoi par lots via l'API HTTP, liste fermée de 13 événements aux propriétés codées (jamais de boisson, genre, orientation, âge, nom, lieu ni message), identifiant aléatoire et non l'identifiant du compte, pas de géolocalisation IP. **Activé par défaut et désactivable** dans Réglages > Mesure d'audience : à valider juridiquement (exemption CNIL de consentement pour la mesure d'audience, sinon demander l'accord à l'inscription).
- **Sentry** : pas encore branché (il demande un module natif et un build de développement) ; à ajouter avec le premier build EAS, avec nettoyage des données personnelles.
- Correction au passage : deux tests dépendaient de l'ordre de lignes à égalité (membres d'un groupe arrivés dans la même transaction, profils à la même distance) ; ordre rendu stable.

## Ajustements après la phase 11
- **Type de compte demandé en premier** : l'écran « Compte individuel ou compte de couple » (spec §3, écran 4) passe en tête de l'inscription, avant l'âge. Sinon on ne sait pas quel prénom saisir. Avec « compte de couple », l'écran du prénom précise que chacun crée d'abord son propre profil vérifié avec son prénom ; le profil commun vient ensuite (inchangé, spec §6). Le choix reste mémorisé sur l'appareil : il est redemandé si l'appli est rouverte avant la fin de l'écran de l'âge.

## Bêta gratuite (proposées, en attente de validation)
- **Objectif** : une appli complète testée sans aucun coût avant de décider de la publication. D'abord testée seul, sur Android (APK installé hors store, notifications comprises) et sur iPhone via Expo Go (sans notifications). Guide pas à pas : docs/BETA.md.
- **Connexion par e-mail, SMS, Google et Apple** (validé le 2026-10-07, complète Q13) : le premier écran propose les méthodes de `EXPO_PUBLIC_AUTH_METHODS`. Google et Apple passent par le navigateur du système (OAuth de Supabase, PKCE), sans module natif. Apple est codé mais désactivé jusqu'au compte développeur ; le SMS demande un fournisseur payant. Bêta : e-mail et Google.
- **Numéro obligatoire pour tous** (validé le 2026-10-07) : il sert à « bloquer mes contacts ». Une connexion par SMS le vérifie ; sinon l'onboarding le demande, vérifié par SMS en production (`auth.phone_verification_required`), déclaré sans vérification en bêta. Un numéro déclaré n'est pas unique (sinon quelqu'un pourrait occuper celui d'un autre) ; seul un numéro vérifié vaut « un numéro = un compte ». Seules une empreinte SHA-256 (contacts) et une empreinte HMAC (réinscription) sont gardées.
- **Comptes suspendus** (validé le 2026-10-07) : leurs matchs sont mis en attente, fermés pour les deux personnes, et rouverts à la levée de la suspension avec un nouveau délai de 24 h pour le premier message. Un modérateur lève une suspension avec `private.mod_lift_suspension`, journalisée. La suppression du compte reste possible (RGPD, règles des stores), mais un compte supprimé pendant une suspension laisse une trace (empreinte du numéro, référence de visage) pendant `compliance.suspended_trace_retention_days` (365 j, provisoire, à valider juridiquement) : s'il revient, son selfie part en revue prioritaire (`returning_account`). Seul un compte fermé pour minorité empêche la réinscription.
- **Environnement `APP_ENV=beta`** : les prestataires factices sont autorisés sur le projet hébergé, mais chaque selfie et chaque photo partent en revue humaine (aucune validation automatique). « Tester en tant que » reste impossible hors du local.
- **Géocodage réel par geo.api.gouv.fr** (API de l'État, gratuite, sans clé) plutôt que des contours de départements chargés dans PostGIS : même résultat (pays, département, région), sans données volumineuses à maintenir. La position est arrondie à environ 1 km avant l'envoi. Hors de France, le pays reste inconnu (Q25).
- **Paiements** : Test Store de RevenueCat (achats simulés). Les événements de bac à sable ne comptent que si `revenuecat.allowed_environments` les autorise, ce qui n'est vrai qu'en bêta.
- **Analyse IA** : version factice pendant la bêta (l'API Claude n'a pas d'offre gratuite).
- **Tâches planifiées** : un secret dédié (`CRON_SECRET`) authentifie les appels de pg_cron aux Edge Functions ; la clé service_role n'est plus stockée dans Vault.
- **Accès aux photos** : une photo n'est lisible par un autre que si elle est validée par la modération et que cette personne peut voir le profil (feed des dernières 24 h, match actif, ou photo principale d'un membre de son groupe). Ouvrir un groupe ne donne plus accès au profil complet des membres ni au like (spec §8 : prénom et photo principale seulement).
- **« Bloquer mes contacts »** : une fois par 24 h (`contacts.block_cooldown_hours`), et l'appli dit seulement que la demande a été faite, jamais si un contact a été trouvé (sinon on pourrait tester si un numéro est inscrit).
- **Autres corrections de sécurité** : date de naissance impossible à effacer, likes simultanés sérialisés (match garanti si les deux likent en même temps, quota respecté), selfie jamais validé sur une réponse incomplète du prestataire, photos d'un couple effacées avec le couple, réponses écrites modifiables uniquement par `set_my_prompts`.
