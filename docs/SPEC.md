# Attractr — Spécification produit (V1)

> Source de vérité fonctionnelle. Toute valeur marquée **provisoire** vit dans la table `app_config`, jamais en dur dans le code.

## Méthode de travail

1. Spécification dans `docs/SPEC.md`, `CLAUDE.md` court qui y renvoie.
2. Proposition d'architecture (dépôt, schéma, décisions techniques, interfaces), validation avant implémentation.
3. Construction phase par phase (section 14). À la fin de chaque phase : résumé, comment tester, tests qui passent, décisions prises seul. Feu vert avant la phase suivante.
4. Règle ambiguë → question courte plutôt qu'invention. Valeur "provisoire" → `app_config`.
5. Petits commits, tests automatisés pour toute règle métier (compatibilité, quotas, parrainage, groupes), aucun secret dans le dépôt (`.env.example` uniquement).
6. Code et commentaires en anglais ; textes d'interface en français dans des fichiers i18n (anglais ajouté plus tard).

## Produit

Chaque utilisateur affiche une boisson qui indique ce qu'il cherche. Le feed ne montre que des profils compatibles. Inscription ouverte au monde entier, test en France. Prix unique pour tous, résiliation en un clic, aucune publicité. Ce n'est pas un réseau social : pas de fil d'actualité, pas de publications, pas de messages hors match ou hors groupe validé. L'appli est strictement réservée aux adultes (18 ans minimum). Aucun espace pour mineurs.

## Stack

- Mobile : Expo (React Native) + TypeScript.
- Backend : Supabase, région UE : Auth, Postgres avec PostGIS, Realtime pour le chat, Storage pour les photos, RLS sur toutes les tables, Edge Functions pour tout appel à un prestataire externe.
- Paiements : RevenueCat. Notifications : Expo Notifications. Mesure : PostHog (UE) et Sentry.
- Deux environnements : développement et production.
- Prestataires externes (vérification selfie et estimation d'âge, modération des photos, analyse IA, géocodage) : une interface et une implémentation factice (mock) pour chacun, utilisée en développement. Vraies implémentations plus tard, derrière un drapeau de configuration.

## 1. Boissons

Vin = relation sérieuse. Cocktail = relation purement sexuelle (« plan cul »). Café = pas encore décidé entre Vin et Cocktail. Bière = amitié uniquement.

- Un profil a une boisson, ou deux à condition que la Bière en fasse partie (Bière+Vin, Bière+Café, Bière+Cocktail). Aucune autre combinaison.
- Changement limité à une fois tous les 7 jours (historique privé, réservé à la modération).
- Sous-titres explicatifs à l'inscription, puis icône seule. Mention visible : « Les boissons sont des symboles, pas des invitations à boire », avec une icône alternative sans alcool au choix.
- Matrice de compatibilité stockée dans `drink_compatibility` (modifiable sans redéployer) :

  |          | Vin | Café | Cocktail | Bière |
  |----------|-----|------|----------|-------|
  | Vin      | oui | oui  | non      | non   |
  | Café     | oui | oui  | oui      | non   |
  | Cocktail | non | oui  | oui      | non   |
  | Bière    | non | non  | non      | oui   |

- Deux profils sont compatibles si au moins un croisement de leurs boissons est « oui ».
- Signalement « intention trompeuse » dans le chat : 3 signalements validés = avertissement, puis suspension.

## 2. Profil individuel

- Prénom, âge (18+), genre (liste ouverte).
- Genres recherchés (obligatoire, un ou plusieurs) : c'est lui qui fait le matching. Donnée sensible : chiffrée, jamais affichée publiquement.
- Label d'orientation : facultatif, masquable, sans aucun effet sur le matching.
- Situation actuelle : célibataire (toutes les boissons) ; en relation avec accord des partenaires, c'est-à-dire relation ouverte ou polyamour (toutes les boissons) ; en couple fermé (Bière uniquement). Statut déclaratif.
- Structure relationnelle, demandée seulement si une boisson romantique (Vin, Café, Cocktail) est choisie : « Une seule relation à la fois », « Ouvert à voir », « Relation ouverte », « Polyamour ». Compatibilité (matrice en base) :
  - monogamie ↔ monogamie, « ouvert à voir » ;
  - relation ouverte ↔ relation ouverte, « ouvert à voir » ;
  - polyamour ↔ polyamour, « ouvert à voir » ;
  - « ouvert à voir » ↔ tout.
- Polyamour, champ « Je cherche » (gratuit à déclarer) : une femme, un homme, une personne de n'importe quel genre ; une femme et un homme, deux femmes, deux hommes ; trois personnes ou plus (genres précisés, ou « peu importe »). L'autre personne doit être ouverte au polyamour et correspondre à l'un des genres demandés. En V1 le matching reste individuel, la composition se forme via les groupes (section 8).
- « Ouvert aux couples » : case à cocher pour les individus ayant une boisson romantique. Sans elle, aucun compte couple n'apparaît dans leur feed.
- 3 questions écrites choisies dans une liste (150 caractères maximum chacune), photos, selfie de vérification.

## 3. Inscription (ordre des écrans)

1. Âge, vérification 18+, conditions, code de parrainage facultatif.
2. Prénom, genre, genres recherchés.
3. Consentement RGPD séparé pour les données sensibles (retirable en un clic ensuite).
4. Compte individuel ou compte de couple.
5. Situation actuelle.
6. Boissons (couple fermé : Bière seule ; sinon une boisson, ou Bière plus une autre).
7. Structure relationnelle (sautée avec Bière seule), puis champ « Je cherche » si polyamour.
8. « Ouvert aux couples » (si boisson romantique).
9. Questions écrites.
10. Photos, puis selfie de vérification.
11. Label d'orientation, facultatif, en fin de parcours ou dans les réglages.

## 4. Découverte

- Le feed filtre dans cet ordre : distance, genres recherchés des deux côtés, compatibilité des boissons, structure (et composition recherchée), puis exclusion des profils déjà vus, bloqués ou signalés. Implémenté en SQL (fonction RPC) avec PostGIS.
- Gratuit : recherche autour de la position ou du domicile (rayon en km, département ou région). Premium (passeport) : recherche autour d'un autre lieu.
- Position publique arrondie à environ 1 km, distances affichées en tranches (« moins de 5 km »). Ne jamais stocker ni exposer de coordonnées exactes côté public.
- Élargissement automatique du rayon quand les profils manquent, avec un message d'attente à la place d'un écran vide.
- Badge d'activité réelle : on voit si la personne répond encore.

## 5. Likes, matchs, chat

- Gratuit : quota de 25 likes par période glissante de 24 h (**provisoire**, `app_config`). Premium : illimité.
- Likes ciblés sur une photo ou une réponse écrite.
- Après un match : 24 h pour envoyer le premier message, avec prolongation possible. Notification « à ton tour » pour relancer les conversations qui s'endorment.
- Le chat existe uniquement pour les matchs et les groupes validés (section 8). Chat, matchs et réponses hors quota.

## 6. Comptes de couple

Un compte couple est composé de deux comptes individuels vérifiés, liés. Deux chemins d'entrée :

- **Chemin A** : chacun a son compte, l'un envoie une invitation de couple à l'autre. Le lien n'existe qu'après acceptation (table `couple_invitations` : en attente, acceptée, refusée, expirée).
- **Chemin B** : un compte créé à deux à l'inscription. Le partenaire suit un lien et remplit lui-même son inscription (âge, selfie, consentements). Le profil commun n'est publié que lorsque les deux ont fini leur vérification.

Règles :

- Profil commun : photos des deux, bio commune, badge « Compte couple ». Chaque photo où figurent les deux demande l'accord des deux.
- Couple fermé : Bière uniquement, et le profil individuel de chacun passe en Bière uniquement. Couple ouvert : toutes les boissons selon sa structure ; chaque partenaire choisit de garder son profil individuel actif ou masqué, les deux affichant « en relation ouverte ».
- Un couple cherche une personne, un autre couple, ou une composition à plusieurs (même champ que le polyamour).
- Un like d'un couple demande l'accord des deux partenaires (table `couple_like_approvals`).
- Chat transparent : bandeau « Les deux partenaires voient cette conversation », avec le prénom de celui qui écrit.
- Un seul partenaire peut quitter le compte couple en un clic, sans l'accord de l'autre. Aucun partenaire ne voit les likes ni les matchs personnels de l'autre.
- Selfie des deux obligatoire. Signalement dédié à la pression exercée sur une troisième personne.

## 7. Amis et sorties à plusieurs

- Amis : ajout par lien ou pseudo, jamais par import de contacts, acceptation des deux côtés, compte vérifié obligatoire, 10 amis maximum, liste visible par son propriétaire seul. Pas de messages entre amis, pas de fil d'activité, pas d'amis d'amis.
- Sorties (3 à 8 participants, gratuit) : après un match, l'un des deux propose une sortie et invite des amis, l'autre invite les siens. Chaque ami reçoit une carte (jour, lieu, heure, prénoms des deux personnes matchées) avec « je viens » ou « je ne viens pas », sans accès aux profils, boissons ou likes. La logistique passe par le chat du match, sans chat entre invités. Retour d'avis privé après la sortie.

## 8. Chats de groupe (Premium)

- Groupes romantiques et polyamour (6 membres maximum) : chaque membre doit avoir matché avec tous les autres. L'application le vérifie à chaque ajout.
- Groupes de potes, boisson Bière (8 membres maximum) : quand deux personnes ont matché en Bière et que l'une a déjà un groupe, elle peut inviter l'autre. Le groupe accepte (majorité ou administrateur désigné). Avant d'accepter, le nouveau voit la taille du groupe et les prénoms, mais seulement le profil complet de la personne qui l'invite. Les membres du groupe ne voient du nouveau que son prénom et sa photo principale. Cette exception à la règle du match mutuel ne vaut jamais pour les groupes romantiques.
- Règles communes : chaque membre peut quitter, bloquer ou signaler ; un blocage entre deux membres exclut l'un des deux ; adhésion sur invitation uniquement ; aucun groupe public, aucune recherche de groupes, aucun message entre groupes.
- Abonnement : seul le créateur du groupe doit être Premium (**provisoire**).

## 9. Parrainage

- Parrain abonné Premium : 1 mois offert par filleul validé (plafond 6 mois par an). Le filleul reçoit 1 mois de Premium.
- Parrain non abonné : réduction sur son futur abonnement, et réduction sur le premier abonnement du filleul (50 % du premier paiement, **provisoire**). Un non-abonné n'obtient jamais d'abonnement gratuit.
- Filleul validé : selfie vérifié et compte actif depuis 7 jours. Les mois offerts s'arrêtent avec l'abonnement du parrain.
- Lien d'invitation anonyme : le parrain voit seulement « inscrit et vérifié », jamais le profil, les likes ou les matchs.
- À l'inscription, le filleul peut cocher « devenir ami de mon parrain ».
- Anti-abus : un compte par numéro de téléphone, un même visage ne peut pas servir à deux comptes (via le prestataire de vérification, interface prévue), pas d'auto-parrainage, plafond annuel.
- Les récompenses passent par RevenueCat (offres promotionnelles). Logique isolée pour s'adapter aux règles des stores.

## 10. Offres

**Gratuit** : 25 likes par 24 h, chat, matchs, vérification, blocage des contacts du téléphone, mode pause, sorties à plusieurs, déclaration de la composition de polyamour, filtres de base (âge, distance, genre, boisson), nombre de likes reçus flouté, 1 conseil d'analyse IA.

**Premium** (7,99 € par mois ou 49,99 € par an, prix identique pour tous, **provisoire**, configuré dans RevenueCat) : likes illimités, chats de groupe, filtres avancés (études, taille, centres d'intérêt, « actifs récemment », « vérifiés uniquement », composition recherchée), liste complète de « qui t'a liké » (profils vérifiés uniquement), mode incognito (visible seulement par les personnes que tu likes), retour en arrière, passeport, statistiques de profil (vues, likes par photo), indicateur de popularité des autres profils (voir ci-dessous), analyse IA complète, 1 boost offert par mois.

**Indicateur de popularité** (Premium) : sur chaque profil du feed, une indication qualitative du volume de likes reçus par ce profil (« reçoit beaucoup de likes » / « reçoit peu de likes »). Jamais de chiffre exact. Seuils et fenêtre de calcul **provisoires**, dans `app_config`.

**Boost** : achat à l'unité à 2 €. Le profil passe en tête de la zone pendant 30 minutes, avec affichage du nombre de vues obtenues.

Un seul abonnement par personne en V1 (pas d'abonnement couple).

## 11. Analyse IA du profil

- Photos : un point fort et une amélioration concrète par photo (lumière, cadrage, visage visible, variété), plus un ordre conseillé. Bio : détection des clichés, réécriture proposée dans le ton de l'utilisateur, cohérence avec sa boisson. L'utilisateur valide ou modifie.
- Interdits absolus dans les consignes du modèle : aucune note de beauté, aucun commentaire sur le corps, la peau, l'âge ou l'origine, aucune déduction d'orientation, d'origine, de santé ou de religion. Contrôle de la sortie qui rejette une réponse contenant ce type de contenu.
- Appel uniquement depuis une Edge Function, jamais depuis l'appli. Consentement explicite et séparé avant envoi des photos à un prestataire d'IA. Pas d'entraînement sur les photos, suppression après analyse. Limite d'une analyse par semaine, résultat mis en cache. Derrière un drapeau, avec une implémentation factice en développement.

## 12. Sécurité, confiance, conformité

- Âge : déclaration, estimation d'âge par le prestataire à partir du selfie, revue humaine des cas douteux. Une personne identifiée comme mineure voit son compte fermé et ses données supprimées. Bouton « suspicion de mineur » sur chaque profil et chaque chat, traité en priorité par la modération.
- Selfie de vérification obligatoire à l'inscription. Modération automatique des photos (nudité, violence) puis file de revue humaine pour les cas incertains. Détection d'arnaques en V1 par règles simples (liens dans les premiers messages, demandes d'argent).
- Blocage des contacts du téléphone, mode pause, signalement, blocage, suppression du compte en un clic avec effacement réel des données.
- RLS sur toutes les tables : un utilisateur ne lit que ses données et celles des profils compatibles. Tests vérifiant qu'un utilisateur ne peut pas lire les champs sensibles d'un autre.
- Chiffrement des champs sensibles (genres recherchés, orientation, structure, situation, composition) en plus du chiffrement au repos. Méthode proposée et justifiée.
- Table `consents` : type, version du texte, date, retrait possible. Journal des accès internes (`access_log`). Durées de conservation écrites dans la documentation.
- Aucune donnée sensible dans PostHog, Sentry, les logs ou les notifications push.
- Champs d'orientation, de structure et de composition désactivables par pays (configuration), pour ne pas exposer des personnes dans des pays où ces données les mettent en danger.
- Signaler les points exigeant une validation juridique avant la production (analyse d'impact RGPD, règles des stores sur le parrainage, contrats de traitement avec les prestataires).

## 13. Jeu de données de test et outils de développement

- Script de seed : 100 profils fictifs répartis entre Paris, Marseille, Lyon, Toulouse, Nice, Nantes, Montpellier, Strasbourg, Bordeaux et Lille. Avatars génériques (initiales), jamais de vraies photos. Couvre tous les cas : chaque boisson et combinaison, chaque structure, polyamour avec compositions variées, couples fermés et ouverts, groupes de potes, personnes « ouvertes aux couples », profils vérifiés et non vérifiés.
- Mode « tester en tant que » : connexion comme un compte fictif pour voir son feed. Uniquement en développement, derrière un drapeau, impossible à activer en production.
- Aucun vrai utilisateur avant que le consentement RGPD, la suppression de compte, le contrôle d'âge et les règles d'accès soient testés.

## 14. Phases

1. Base de données, authentification, consentements, RLS, seed, configuration.
2. Inscription complète (section 3), avec toutes les règles de profil.
3. Feed avec compatibilité et profils fictifs, outil « tester en tant que ».
4. Likes, quota, matchs, chat avec délai de 24 h, notifications.
5. Vérification selfie et contrôle d'âge (versions factices), modération des photos, blocage, signalements.
6. Amis et sorties à plusieurs.
7. Abonnement, filtres payants, boosts, parrainage.
8. Chats de groupe (romantiques puis potes).
9. Comptes de couple.
10. Analyse IA du profil.
11. Mesure de la rétention (à 7 et 30 jours) et tableaux de suivi.

## 15. Hors périmètre

Photos éphémères, matching par IA avec score de compatibilité, suggestions de lieux partenaires et sponsoring, classification des arnaques par modèle, matching de compositions à plusieurs avec règles de réciprocité fines, version anglaise, tout espace pour mineurs, toute fonction de réseau social (fil d'actualité, publications, messages hors match ou groupe validé, groupes publics).
