# Bêta gratuite : mise en ligne pas à pas

Objectif : une appli complète, hébergée et testable sur ton téléphone, sans payer quoi que ce soit. Décisions associées : DECISIONS.md, section « Bêta gratuite ».

| Brique | Service gratuit | Limite à connaître |
|---|---|---|
| Base, connexion, photos, fonctions | Supabase, offre Free, région UE | 500 Mo de base, 1 Go de fichiers ; pause après 7 jours sans activité (données conservées, bouton « Restore ») |
| Connexion | Code par e-mail (Supabase) | Le service e-mail intégré n'écrit qu'aux membres du projet, quelques envois par heure : assez pour toi seul. Pour d'autres testeurs : SMTP Brevo gratuit (étape 2.6) |
| Appli Android | EAS Build (Expo), APK installé hors store | Nombre de builds mensuels limité, file d'attente parfois lente |
| Appli iPhone | Expo Go (App Store) | L'appli tourne depuis ton PC ; pas de notifications ; achats simulés localement |
| Notifications Android | Expo + Firebase Cloud Messaging | Aucune |
| Paiements | RevenueCat, Test Store | Achats simulés, aucun vrai paiement |
| Géocodage | geo.api.gouv.fr (API de l'État) | France uniquement |
| Selfie, modération photo, analyse IA | Versions factices | Tu valides toi-même chaque selfie et chaque photo (étape 6) |

Prérequis sur ton PC : Node 22, `npm install` à la racine du dépôt, et un générateur de secret (`openssl rand -hex 32`, ou n'importe quelle suite de 64 caractères aléatoires).

---

## 1. Créer les comptes

Tous gratuits, sans carte bancaire :
- Supabase : https://supabase.com
- Expo : https://expo.dev
- Firebase (notifications Android) : https://console.firebase.google.com
- RevenueCat : https://app.revenuecat.com
- Facultatif, pour d'autres testeurs : Brevo (envoi d'e-mails) : https://www.brevo.com

## 2. Supabase

### 2.1 Projet
1. New project, offre **Free**, région **Europe** (Paris de préférence). Note le mot de passe de la base.
2. Note la **référence du projet** (`<ref>`, dans l'URL `https://<ref>.supabase.co`) et la **clé publique** (Project Settings > API Keys : clé `anon` ou `publishable`). Cette clé est publique par conception : les règles d'accès (RLS) protègent les données.

### 2.2 Base de données
Depuis la racine du dépôt :
```bash
npx supabase login
npx supabase link --project-ref <ref>
npx supabase db push
```
`db push` applique toutes les migrations. Les fichiers de `supabase/seeds` ne sont **jamais** envoyés (outils de test locaux).

### 2.3 Réglages de la bêta (SQL Editor du tableau de bord)
Génère un secret de cron (`openssl rand -hex 32`), puis exécute, en remplaçant `<ref>` et `<CRON_SECRET>` :
```sql
-- Prestataires : géocodage réel (geo.api.gouv.fr) et notifications réelles (Expo).
-- Selfie, modération des photos et analyse IA restent factices.
insert into public.app_config (key, value, description) values
  ('providers.geocoding', '"real"', 'Geocoding: geo.api.gouv.fr.'),
  ('providers.push', '"real"', 'Push: Expo.')
on conflict (key) do update set value = excluded.value, updated_at = now();

-- Numéro déclaré sans SMS pendant la bêta (en production il est vérifié par SMS).
update public.app_config set value = 'false', updated_at = now() where key = 'auth.phone_verification_required';

-- Achats simulés du Test Store RevenueCat (bêta uniquement).
update public.app_config set value = '["PRODUCTION", "SANDBOX"]', updated_at = now()
 where key = 'revenuecat.allowed_environments';

-- Tâches planifiées (notifications, effacements, modération des photos).
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<CRON_SECRET>', 'cron_secret');
```
Vérification : `select jobname, schedule from cron.job;` liste `attractr-send-push`, `attractr-process-deletions`, `attractr-moderate-photos` et `attractr-scheduled-jobs`.

### 2.4 Secrets et Edge Functions
Génère un secret pour le webhook RevenueCat (`openssl rand -hex 32`), puis :
```bash
npx supabase secrets set --project-ref <ref> APP_ENV=beta CRON_SECRET=<CRON_SECRET> REVENUECAT_WEBHOOK_SECRET=<WEBHOOK_SECRET>
npm run functions:deploy -- --project-ref <ref>
```
`functions:deploy` ne déploie jamais les fonctions `dev-*` (« tester en tant que » reste impossible sur un projet hébergé). `APP_ENV=beta` autorise les versions factices, mais envoie chaque selfie et chaque photo en revue humaine.

### 2.5 Connexion : e-mail et Google
L'appli propose les méthodes listées dans `EXPO_PUBLIC_AUTH_METHODS` (étape 5.1). En bêta : `email,google`. Le SMS (payant) et Apple (compte développeur à 99 $/an) s'ajoutent à la publication. Quelle que soit la méthode, l'onboarding demande le numéro de téléphone (blocage des contacts) ; en bêta il est déclaré sans SMS (étape 2.3).

Dans Authentication :
1. **Sign In / Providers** : Email activé, Phone désactivé. Longueur du code e-mail (Email OTP length) : **6**.
2. **Email Templates** : dans « Confirm signup » **et** « Magic Link », sujet `Ton code Attractr` et corps copié depuis `supabase/templates/otp_code.html` (il affiche le code `{{ .Token }}` au lieu d'un lien).
3. **URL Configuration > Redirect URLs** : ajoute `attractr://auth-callback` (APK) et `exp://**` (Expo Go).
4. **Google** :
   - Google Cloud Console (gratuit) : nouveau projet, écran de consentement OAuth en mode « Test » (tu y ajoutes les adresses Gmail autorisées, 100 au maximum), puis Identifiants > ID client OAuth, type « Application Web », URI de redirection autorisée `https://<ref>.supabase.co/auth/v1/callback`.
   - Supabase, Sign In / Providers > Google : active-le et colle l'ID client et le code secret.

### 2.6 Facultatif : e-mails pour d'autres testeurs (Brevo)
Le service e-mail intégré n'écrit qu'aux membres de ton organisation Supabase. Pour inviter quelqu'un d'autre : crée un compte Brevo, valide une adresse d'expéditeur, génère une clé SMTP, puis Authentication > Emails > SMTP Settings : hôte `smtp-relay.brevo.com`, port `587`, identifiant et clé SMTP de Brevo.

## 3. Vérifier le géocodage

Depuis ton PC :
```bash
curl "https://geo.api.gouv.fr/communes?lat=48.86&lon=2.35&fields=nom,codeDepartement,codeRegion"
```
Réponse attendue : Paris, département `75`, région `11`. C'est le service qu'utilise la fonction `update-location`.

## 4. RevenueCat (achats simulés)

1. Crée un projet. Il contient un **Test Store** (magasin de test intégré, achats simulés) avec sa clé d'API publique `test_...`.
2. Dans le Test Store, crée les produits de docs/PAYMENTS.md : `premium_monthly` et `premium_yearly` (abonnements), `boost_single` (consommable).
3. Entitlement `premium` relié aux deux abonnements ; offerings `premium` (courant, les deux abonnements) et `boosts` (`boost_single`).
4. Webhook (Integrations > Webhooks) : URL `https://<ref>.supabase.co/functions/v1/revenuecat-webhook`, en-tête Authorization = `<WEBHOOK_SECRET>`.
5. Après un premier achat de test, vérifie dans le SQL Editor :
   ```sql
   select type, payload ->> 'environment' as env, outcome from private.revenuecat_events order by received_at desc limit 5;
   ```
   `outcome` doit valoir `premium_active` ou `boost_credited`. S'il vaut `ignored_environment`, ajoute la valeur affichée dans `env` à `revenuecat.allowed_environments` (étape 2.3).

## 5. L'appli

### 5.1 Projet Expo et variables
Dans `apps/mobile` :
```bash
npx eas-cli@latest login
npx eas-cli@latest init
```
`init` crée le projet Expo. Comme la configuration est dynamique (`app.config.ts`), il peut te demander d'ajouter l'identifiant toi-même : mets `"extra": { "eas": { "projectId": "<id affiché>" } }` dans `app.json`, à l'intérieur de `"expo"`, puis committe (l'identifiant n'est pas un secret).

Variables de l'environnement EAS `preview` (utilisé par le build bêta) :
```bash
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_SUPABASE_URL --value https://<ref>.supabase.co
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_SUPABASE_ANON_KEY --value <clé publique>
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_APP_ENV --value beta
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_AUTH_METHODS --value email,google
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_REVENUECAT_ANDROID_KEY --value test_...
npx eas-cli@latest env:create --environment preview --visibility plaintext --name EXPO_PUBLIC_REVENUECAT_IOS_KEY --value test_...
```

### 5.2 Notifications Android (Firebase)
1. Firebase : nouveau projet (Google Analytics inutile), puis « Ajouter une appli Android » avec le nom de package `app.attractr`. Télécharge `google-services.json` (jamais committé, le `.gitignore` l'exclut) :
   ```bash
   npx eas-cli@latest env:create --environment preview --type file --visibility secret --name GOOGLE_SERVICES_JSON --value ./google-services.json
   ```
2. Firebase > Paramètres du projet > Comptes de service > Générer une nouvelle clé privée. Puis `npx eas-cli@latest credentials` > Android > profil `beta` > Google Service Account > clé pour les notifications (FCM V1) : envoie ce fichier. Supprime ensuite la clé de ton disque.

### 5.3 Android : l'APK
```bash
npx eas-cli@latest build --profile beta --platform android
```
À la fin, EAS donne un lien et un QR code : ouvre-le sur le téléphone, télécharge l'APK et autorise l'installation d'applis de source inconnue quand Android le demande.

### 5.4 iPhone : Expo Go
1. Installe **Expo Go** depuis l'App Store.
2. Crée `apps/mobile/.env` (jamais committé) avec les mêmes valeurs que l'étape 5.1 (`EXPO_PUBLIC_APP_ENV=beta`, `EXPO_PUBLIC_AUTH_METHODS=email,google`, etc.).
3. `npm run mobile` à la racine, puis scanne le QR code avec l'appareil photo de l'iPhone. Le téléphone et le PC doivent être sur le même Wi-Fi (sinon : `npx expo start --tunnel` dans `apps/mobile`).

Limites d'Expo Go : l'appli ne tourne que pendant que ton PC la sert, sans notifications ; les achats y sont simulés par le SDK RevenueCat sans passer par le serveur. Teste donc Premium et les Boosts sur Android.

## 6. Premier test

1. Inscris-toi avec ton adresse e-mail et va au bout de l'inscription.
2. Ton selfie et tes photos sont « en revue ». Valide-les dans le SQL Editor (docs/MODERATION.md) :
   ```sql
   select * from private.mod_queue('moderateur:moi');
   select private.mod_resolve_selfie('moderateur:moi', <id>, 'verified');
   select private.mod_resolve_photo('moderateur:moi', <id>, 'approved');
   ```
3. Facultatif, pour un feed rempli : charge les 100 profils fictifs (sans photos, impossibles à utiliser pour se connecter) en exécutant **uniquement** `supabase/seeds/20_profiles.sql` dans le SQL Editor. Ne charge jamais `00_test_helpers.sql` ni `10_dev_config.sql` sur un projet hébergé. Pour les retirer :
   ```sql
   delete from auth.users where id in (select id from public.profiles where is_seed);
   ```
4. Pour tester un match et le chat, il faut un second compte réel : une seconde adresse e-mail (avec Brevo, étape 2.6), sur l'autre téléphone.

## 7. Avant d'ouvrir la bêta à d'autres personnes

- SMTP Brevo (étape 2.6).
- Pages CGU et confidentialité publiées (GitHub Pages, gratuit), et l'analyse d'impact RGPD (docs/ARCHITECTURE.md, liste juridique) : dès qu'une personne extérieure saisit ses données, elles sont réelles.
- Tenir la file de modération : en bêta, aucun selfie ni aucune photo n'est validé sans toi.

## 8. Passage aux stores (payant)

Google Play (25 $ une fois ; un compte personnel récent doit d'abord faire tester l'appli 14 jours par 12 personnes), Apple (99 $ par an), fournisseur de SMS et connexion Apple (`EXPO_PUBLIC_AUTH_METHODS=phone,email,google,apple`, `auth.phone_verification_required` remis à `true`), prestataires selfie et âge, modération des photos, API Claude, nom de domaine. Côté réglages : `APP_ENV=production`, `revenuecat.allowed_environments` remis à `["PRODUCTION"]`, profils fictifs supprimés.
