# CLSTR

Flutter-app voor het plannen en bijhouden van bezorgroutes, per bedrijf en per
cluster. Backend draait op Firebase (Firestore, Authentication, Cloud
Functions) in project `clstr-794ed`.

Rollen: **superadmin** (beheert alle bedrijven), **admin** (beheert één
bedrijf) en **subaccount** (ziet alleen de toegewezen clusters).

## Aan de slag

```bash
flutter pub get
flutter run
```

Voor een release-build heb je `android/key.properties` nodig met de
signing-gegevens. Dat bestand staat bewust niet in git. Ontbreekt het, dan
bouwt de app nog steeds, maar met de debug-sleutel — Google Play weigert zo'n
bundle.

Controleren vóór het committen:

```bash
flutter analyze
flutter test
```

## Updaten: drie lagen, drie snelheden

| Wat je wijzigt | Hoe het live komt | Hoe snel |
| --- | --- | --- |
| `firestore.rules`, `firestore.indexes.json`, `functions/` | `firebase deploy` of Actions → Deploy Firebase | seconden |
| `lib/` (de app zelf) | Actions → Release Android → Play Store | dagen |
| Gegevens (bedrijven, clusters, routes) | via de beheerschermen in de app | direct |

Omdat de backend veel sneller vernieuwt dan de app, draaien er altijd tijdelijk
oude app-versies tegen een nieuwe backend. De app controleert daarom bij het
opstarten het Firestore-document `app_config/versie`: staat daar een
`minimumBuild` hoger dan de geïnstalleerde versie, dan krijgt de gebruiker een
updatescherm in plaats van onverklaarbare fouten.

Hoog dat veld dus op zodra je iets in de backend wijzigt dat oudere
app-versies breekt.

## Een nieuwe versie uitbrengen

```bash
dart run tool/bump_versie.dart patch   # of minor / major
git commit -am "Versie 1.0.1"
git push
```

Daarna op GitHub: **Actions → Release Android → Run workflow**. De workflow
bouwt een ondertekende App Bundle en meldt aan het eind welk buildnummer het
geworden is.

De benodigde GitHub-secrets staan beschreven bovenaan
[.github/workflows/release-android.yml](.github/workflows/release-android.yml)
en [.github/workflows/deploy-firebase.yml](.github/workflows/deploy-firebase.yml).

iOS bouwen kan alleen op een Mac; de configuratie zit al in het project.

## Chauffeurs of routes in bulk toevoegen

Voor een nieuw bedrijf hoef je niet alles met de hand in te tikken:

```bash
cd tool/import && npm install          # eenmalig
node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=chauffeurs.txt
node tool/import/importeer_routes.js    --bedrijf=<bedrijfId> --bestand=routes.txt --depot="Depot Noord"
```

Zonder `--schrijf` laten ze alleen zien wát ze zouden doen. Zie
[tool/import/README.md](tool/import/README.md) voor het bestandsformaat en
het inloggen.

## Meer

[CLAUDE.md](CLAUDE.md) bevat de projectconventies, de uitrolprocedure in detail
en de valkuilen die eerder al eens tot bugs hebben geleid (zomertijd bij
datumberekeningen, de `whereIn`-limiet van Firestore, foutafhandeling bij
schrijfacties).
