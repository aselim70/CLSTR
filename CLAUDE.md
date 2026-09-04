# CLSTR — projectkennis

Flutter-app voor routeplanning per bedrijf/cluster, met Firebase als backend.
Nederlandstalig project: **code, commentaar, commits en documentatie in het
Nederlands.** Variabelen en functies dus ook (`bedrijfId`, `magToegang`,
`probeerSchrijfactie`), niet in het Engels.

## Waar wat staat

| Pad | Wat |
| --- | --- |
| `lib/` | De hele app. Plat, één bestand per scherm; geen submappen. |
| `lib/app_helpers.dart` | Gedeelde datum- en Firestore-hulpjes. Nieuwe gedeelde logica hoort hier. |
| `lib/app_theme.dart` | Kleuren, `GradientAppBar`, `AppLoader`, `GradientButton`. |
| `lib/versie_check.dart` | Blokkeert te oude app-versies. Zie "Een update uitbrengen". |
| `functions/index.js` | Cloud Functions: alle account- en bedrijfsmutaties. |
| `firestore.rules` | Beveiligingsregels. Lees de kop van dat bestand vóór je iets wijzigt. |
| `tool/bump_versie.dart` | Versienummer ophogen. |
| `tool/import/` | Bulk-import van chauffeurs en routes. Zie de README daar. |
| `.github/workflows/` | CI (controleren) + drie handmatige uitrol-workflows. |

Firebase-project: **`clstr-794ed`**. Android-package en iOS-bundle-id zijn
allebei **`com.clstr.app`**.

## Drie lagen die apart updaten

Dit is het belangrijkste om te snappen bij elke wijziging:

1. **Backend** (`firestore.rules`, `firestore.indexes.json`, `functions/`) —
   uitrollen met `firebase deploy`, **binnen seconden live bij iedereen**.
2. **De app** (`lib/`) — moet gebouwd, door Google Play heen, en dan nog door
   de gebruiker geïnstalleerd. Duurt dagen.
3. **Data** (Firestore-documenten) — via de beheerschermen in de app.

Gevolg: er is altijd een periode waarin de nieuwe backend draait naast oude
app-versies. **Wijzig je iets in de backend dat oude app-versies breekt, hoog
dan `minimumBuild` op** (zie hieronder) — anders krijgen gebruikers stille
fouten in plaats van een duidelijk updatescherm.

## Dagelijks werk

```bash
flutter pub get
flutter analyze          # moet schoon zijn
flutter test             # moet groen zijn
flutter run
```

`dart format` is **niet** leidend in dit project: de bestaande code gebruikt
langere regels dan de standaard van 80 tekens. CI controleert daar bewust niet
op. Ga niet spontaan het hele project formatteren — dat geeft een enorme diff
die echte wijzigingen onvindbaar maakt.

## De backend uitrollen

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions
firebase deploy --only firestore:indexes
```

Of via GitHub: Actions → **Deploy Firebase** → Run workflow (vereist het
secret `FIREBASE_SERVICE_ACCOUNT`, zie de kop van
`.github/workflows/deploy-firebase.yml`).

Let op bij `firestore.rules`: een fout daarin sluit in één klap iedereen buiten.
De regels lezen alle velden via `.get('veld', default)` en nooit rechtstreeks —
de reden staat uitgelegd bovenaan het bestand. Houd dat aan.

## Een update van de app uitbrengen (Android)

1. Versienaam ophogen:
   ```bash
   dart run tool/bump_versie.dart patch    # of minor / major
   ```
2. Committen en pushen. CI draait `flutter analyze` + `flutter test`.
3. Actions → **Release Android** → Run workflow. Die bouwt een ondertekende
   `.aab` en zet hem klaar als download (of uploadt naar de Play Store als
   `PLAY_SERVICE_ACCOUNT_JSON` is ingesteld).
4. De workflow meldt aan het eind welk **buildnummer** het geworden is.
5. Pas als de release bij iedereen binnen is en je oude versies wilt
   uitsluiten: zet `minimumBuild` in Firestore op dat nummer.

Het buildnummer komt in CI **niet** uit `pubspec.yaml` maar uit het
GitHub-runnummer (+ een offset van 100), omdat dat gegarandeerd oploopt.
Google Play weigert een upload met een buildnummer dat al eens is gebruikt.

De keystore staat lokaal in `android/key.properties` en verwijst naar een
`.jks` buiten de repo. Beide horen **nooit** in git. Raakt die sleutel kwijt,
dan kun je nooit meer een update van deze app publiceren.

## De iOS-app uitbrengen

De projectconfiguratie is compleet: bundle-id `com.clstr.app`, een eigen
iOS-app in Firebase, `ios/Runner/GoogleService-Info.plist`, app-icoon en
opstartscherm. Er is nog nooit een iOS-build gedraaid, dus dat de app op
Android werkt zegt nog niets over iOS.

Bouwen gaat via Actions → **Release iOS** → Run workflow, met twee standen:

- **`controleren`** — bouwt onondertekend op een macOS-runner. Vereist geen
  Apple-account en geen enkel secret. Dit is de enige manier om vanaf Windows
  te merken dat de iOS-build stuk is. Draai dit na elke `flutter pub upgrade`.
- **`release`** — bouwt een ondertekende `.ipa`. Vereist het betaalde Apple
  Developer Program en de secrets die bovenaan `release-ios.yml` staan.

Let op: macOS-runners kosten 10× zoveel Actions-minuten als Linux. Daarom
draait de iOS-build bewust **niet** mee in de gewone CI.

Wat je zelf nog bij Apple moet regelen voordat een release kan:

1. Apple Developer Program (€99/jaar), daarna een App-ID voor `com.clstr.app`,
   een distributiecertificaat en een App Store-provisioningprofiel.
2. De app aanmaken in App Store Connect en de **allereerste** build met de hand
   uploaden (Transporter of Xcode) — pas daarna mag de API het overnemen.
3. Een **demo-account** invullen bij de reviewgegevens. De app zit volledig
   achter een login; zonder testaccount wordt hij gegarandeerd afgewezen.
4. In de reviewnotitie vermelden dat gebruikers zich niet zelf registreren
   (beheerders maken accounts aan) en verwijzen naar de pagina voor het
   verwijderen van accounts op Hosting. Dat voorkomt een discussie over
   richtlijn 5.1.1(v), die in-app accountverwijdering eist bij apps waar
   gebruikers zélf een account aanmaken.
5. Reken op een vraag over richtlijn 4.2: een app die maar voor één
   organisatie bruikbaar is, stuurt Apple richting Apple Business Manager in
   plaats van de publieke App Store.

`ITSAppUsesNonExemptEncryption` staat op `false` in `Info.plist`, zodat je die
exportvraag niet bij elke upload opnieuw hoeft te beantwoorden.

Er is geen `Podfile`. Dat is goed: dit project gebruikt Swift Package Manager
(zie `FlutterGeneratedPluginSwiftPackage` in het Xcode-project). Flutter maakt
zelf een Podfile aan zodra er ooit een plugin bij komt die alleen CocoaPods
ondersteunt. Schrijf er dus geen met de hand.

De keten certificaat + provisioningprofiel is voor iOS wat de keystore voor
Android is: raak je hem kwijt, dan is een nieuwe aan te vragen — anders dan bij
Android is dat dus geen ramp. Wat je niet kwijt moet raken is het
Apple-account zelf.

## De versiecheck (`app_config/versie`)

Firestore-document `app_config/versie`, met deze velden:

| Veld | Type | Betekenis |
| --- | --- | --- |
| `minimumBuild` | number | Onder dit buildnummer blokkeert de app. Verplicht. |
| `minimumBuildIos` | number | Optioneel; geldt op iOS in plaats van `minimumBuild`. |
| `minimumVersie` | string | Alleen voor de tekst op het scherm, bijv. `"1.2.0"`. |
| `bericht` | string | Optionele eigen uitleg. |
| `storeUrlAndroid` | string | Optioneel; standaard de Play Store-pagina. |
| `storeUrlIos` | string | Optioneel; géén standaard (zie hieronder). |

**Waarom twee buildnummers.** Het runnummer van GitHub Actions telt per
workflow, dus de Android- en de iOS-releaseworkflow delen elk hun eigen reeks
uit (offset 100 respectievelijk 1000). Build 120 op Android is daarom een
andere release dan build 120 op iOS. Zou je met één `minimumBuild` oude
Android-versies blokkeren, dan sluit je willekeurige iOS-gebruikers mee buiten.
Vul je `minimumBuildIos` niet in, dan geldt op iOS gewoon `minimumBuild` — een
bestaand document blijft dus werken.

Voor `storeUrlIos` is er bewust geen standaardwaarde: een App Store-link bevat
een nummer dat Apple pas bij de eerste release toekent. Staat het veld leeg,
dan toont het updatescherm op iOS geen knop. Vul het dus in zodra de app in de
App Store staat.

Bestaat het document niet, dan blokkeert er niets. Mislukt het ophalen (geen
verbinding, timeout van 5 seconden), dan wordt de gebruiker **doorgelaten** —
iemand buitensluiten door een netwerkstoring is erger dan een te oude app die
nog even doordraait. Houd dat principe aan bij wijzigingen.

Dit document is publiek leesbaar (`allow read: if true`), want de controle
draait vóór het inloggen. Zet er daarom nooit iets anders in dan versie-info.

## Valkuilen die al een keer misgingen

Deze staan uitgebreider toegelicht in de code zelf; hier de korte versie:

- **Datumrekenen**: gebruik `plusDagen()` uit `app_helpers.dart`, nooit
  `add(Duration(days: 1))`. Dat laatste telt 24 uur en gaat mis op de nacht van
  de klokwissel, waardoor dagplanningen verspringen of verdwijnen.
- **`whereIn` in Firestore** accepteert maximaal 30 waarden en gooit daarboven
  een fout vóórdat er iets naar de server gaat. Gebruik `beperkVoorWhereIn()`.
- **Schrijfacties**: wikkel ze in `probeerSchrijfactie()`, met de context van de
  **pagina** (niet van het dialoogvenster). Anders sluit het dialoogvenster bij
  een mislukte schrijfactie alsof alles goed ging.
- **Lijstopvragingen** moeten in Dart expliciet filteren op `bedrijfId` én
  `clusterId`, omdat `firestore.rules` een lijstquery anders niet kan
  goedkeuren.
- **Geen futures aanmaken in `build()`** — die draait meerdere keren. Start ze
  in `initState()` of in `main()` en geef ze door.
