# Bulk-import: chauffeurs en routes

Twee scripts om in één keer een hele lijst chauffeurs of routes aan een
bedrijf toe te voegen, in plaats van ze stuk voor stuk in de app in te
tikken. Ze schrijven rechtstreeks in Firestore met de Admin SDK.

> **Let op:** de Admin SDK gaat **niet** langs `firestore.rules`. Deze
> scripts kunnen dus in élk bedrijf schrijven, ook in dat van een andere
> klant. Daarom is een droogloop de standaard en moet je `--schrijf`
> expliciet meegeven.

## Volgorde bij een nieuw bedrijf

Deze scripts zijn de **laatste** stap van het onboarden. Eerst dit, in de app:

1. **Bedrijf + admin aanmaken** — scherm *Bedrijven (Superadmin)*.
2. **Clusters aanmaken** — scherm *Bedrijf & clusters beheren*.
3. **Depots aanmaken** — scherm *Depots*.
4. **Dan pas importeren.** Chauffeurs mag eerder (die hangen alleen aan het
   bedrijf), maar routes niet: het script zoekt het `clusterId` op bij het
   depot, dus zonder depots stopt het meteen.

## Eenmalig klaarzetten

```bash
cd tool/import
npm install
```

Dat moet op **elke machine** waar je de scripts draait: `node_modules/` staat
in `.gitignore` en gaat dus niet mee in git.

En inloggen, op één van deze twee manieren:

- **Servicesleutel** (aanrader): Firebase Console → Projectinstellingen →
  Serviceaccounts → nieuwe privésleutel genereren. Die JSON geef je mee met
  `--sleutel=pad/naar/sleutel.json`. Bewaar het bestand **buiten de repo** —
  het geeft volledige toegang tot de database van alle bedrijven.
- **Je eigen Google-account**: `gcloud auth application-default login`. Werkt
  alleen als dat account rechten heeft op het project `clstr-794ed`.

Het `<bedrijfId>` hieronder is de document-ID uit de collectie `bedrijven`.
Weet je hem niet uit je hoofd, vul dan iets willekeurigs in: het script stopt
dan en toont de lijst met bestaande bedrijven.

## Chauffeurs toevoegen

Maak een tekstbestand met één naam per regel (zie
`voorbeeld_chauffeurs.txt`):

```
# Chauffeurs cluster Noord
Jan Jansen
Piet de Vries
```

```bash
# Eerst kijken wat er zou gebeuren (schrijft niets weg):
node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=chauffeurs.txt

# En dan pas echt:
node tool/import/importeer_chauffeurs.js --bedrijf=<bedrijfId> --bestand=chauffeurs.txt --schrijf
```

Er wordt per chauffeur een document `{ naam, bedrijfId }` aangemaakt —
precies wat het scherm *Chauffeurs* in de app ook doet.

## Routes toevoegen

Maak een bestand met één routenaam per regel, precies zoals hij in de app
moet komen te staan (zie `voorbeeld_routes.txt`):

```
622 RSD Westrand
623 RSD Oost
```

```bash
node tool/import/importeer_routes.js --bedrijf=<bedrijfId> --bestand=routes.txt --depot="Depot Noord"
node tool/import/importeer_routes.js --bedrijf=<bedrijfId> --bestand=routes.txt --depot="Depot Noord" --schrijf
```

Het ritnummer typ je niet apart: dat zit al vooraan in de naam en wordt
daar automatisch uitgehaald (`623 RSD Oost` → `623`). De app gebruikt het
alleen voor het label *Rit 623* onder de routenaam; begint een naam niet met
een cijfer, dan blijft dat veld leeg en valt het label gewoon weg.

Staan de routes in verschillende depots, dan zet je het depot erachter in een
tweede kolom (puntkomma, tab of komma) en laat je `--depot` weg:

```
622 RSD Westrand ; Depot Noord
711 RSD Centrum  ; Depot Zuid
```

Het `clusterId` typ je niet zelf: het script zoekt op bij welk cluster het
depot hoort. Een route met een ander `clusterId` dan zijn depot is in de app
namelijk onvindbaar — elk scherm filtert op `bedrijfId` én `clusterId` — en
dat merk je pas weken later. Staat dezelfde depotnaam in meerdere clusters,
dan stopt het script en kies je met `--cluster=<clusterId>`.

## Wat de scripts zelf al controleren

- Het bedrijf moet bestaan; zo niet, dan tonen ze welke bedrijven er wél zijn.
- Het depot moet bestaan bij dát bedrijf; zo niet, idem met de depotlijst.
- De depotnaam wordt overgenomen zoals hij in de database staat, niet zoals
  hij in je bestand staat. `route_list_page.dart` zoekt hoofdlettergevoelig
  op `depotNaam`, dus "depot noord" zou daar nooit gevonden worden.
- Dubbelingen worden overgeslagen, niet dubbel aangemaakt: chauffeurs op naam,
  routes op depot + naam. Hoofdletters en dubbele spaties maken daarbij niet
  uit. Je kunt een script dus gerust nog een keer draaien met een aangevulde
  lijst.
- Bestaat het ritnummer al in dat depot onder een ándere naam, dan krijg je
  een waarschuwing te zien (maar het script gaat door — twee routes met
  hetzelfde nummer mag).
- Kopregels uit Excel (`naam;depot`) worden herkend en overgeslagen.

## Wat ze bewust níet doen

Niets bijwerken of verwijderen — alleen toevoegen. Een verkeerd
geïmporteerde naam pas je aan in de app of in de Firebase Console.
