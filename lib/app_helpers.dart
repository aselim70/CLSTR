/// Gedeelde hulpjes voor datum-rekenwerk en Firestore-toegang.
///
/// Datum-hulpjes. Stonden eerder als losse kopieën in
/// route_detail_page, overzicht_page, rapportage_page en
/// route_geschiedenis_page — met in elke kopie dezelfde zomertijd-fout.
///
/// De kern van het probleem: `datum.add(const Duration(days: 1))` telt er
/// precies 24 uur bij op, geen "één kalenderdag". Op de nacht dat de klok
/// verspringt (eind maart / eind oktober in Nederland) duurt een dag 23 of
/// 25 uur. Een lus die met Duration(days: 1) door een periode loopt, slaat
/// daardoor rond die dagen een datum over of geeft er één dubbel — en omdat
/// deze app dagen als sleutel ('yyyy-MM-dd') in Firestore gebruikt, betekent
/// dat verkeerd getoonde of "verdwenen" dagplanningen.
///
/// Alles hieronder rekent daarom via de DateTime-constructor (die overloop
/// van maand/jaar zelf netjes afhandelt) op datum-niveau, met de tijd altijd
/// op middernacht.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _sleutelFormaat = DateFormat('yyyy-MM-dd');

/// De sleutel zoals dagplanning-documenten hem in Firestore opslaan.
String dateKey(DateTime d) => _sleutelFormaat.format(d);

/// Zelfde dag, maar met de tijd op 00:00 — zodat vergelijken en optellen
/// niet meer van het tijdstip afhangt.
DateTime alleenDatum(DateTime d) => DateTime(d.year, d.month, d.day);

/// Telt hele kalenderdagen op (of eraf, met een negatief getal). Veilig rond
/// de zomer-/wintertijdovergang, in tegenstelling tot `add(Duration(days:))`.
DateTime plusDagen(DateTime d, int dagen) => DateTime(d.year, d.month, d.day + dagen);

/// De maandag van de week waar deze datum in valt.
DateTime weekStart(DateTime d) => plusDagen(d, -(d.weekday - 1));

/// De zondag van de week waar deze datum in valt.
DateTime weekEind(DateTime d) => plusDagen(weekStart(d), 6);

/// Maandag t/m zondag van de week waar deze datum in valt.
List<DateTime> weekDagen(DateTime d) {
  final maandag = weekStart(d);
  return List.generate(7, (i) => plusDagen(maandag, i));
}

/// Alle kalenderdagen van [start] t/m [eind], inclusief allebei.
List<DateTime> dagenTussen(DateTime start, DateTime eind) {
  final dagen = <DateTime>[];
  for (var d = alleenDatum(start); !d.isAfter(alleenDatum(eind)); d = plusDagen(d, 1)) {
    dagen.add(d);
  }
  return dagen;
}

/// Aantal kalenderdagen in een periode, inclusief begin- en einddag.
///
/// Bewust via UTC: in de nacht dat de klok vooruit gaat liggen er maar 47 uur
/// tussen twee middernachten die drie dagen beslaan, en `.inDays` kapt dat af
/// naar 1 — dan telde een periode een dag te weinig. UTC kent geen zomertijd,
/// dus daar klopt het verschil altijd.
int aantalDagen(DateTime start, DateTime eind) =>
    DateTime.utc(eind.year, eind.month, eind.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
    1;

/// Firestore weigert een `whereIn`-filter met meer dan 30 waarden: de query
/// gooit dan een ArgumentError nog vóór er iets naar de server gaat, wat in
/// de app neerkomt op een leeg scherm of een crash. Een gebruiker met meer
/// dan 30 toegewezen clusters is zeldzaam, maar niet onmogelijk — dus knippen
/// we hier af in plaats van onderuit te gaan. Zie [whereInOverschreden] om
/// dat zichtbaar te maken voor de gebruiker.
const int maxWhereInWaarden = 30;

List<String> beperkVoorWhereIn(List<String> waarden) =>
    waarden.length <= maxWhereInWaarden ? waarden : waarden.sublist(0, maxWhereInWaarden);

bool whereInOverschreden(List<String> waarden) => waarden.length > maxWhereInWaarden;

/// Uitkomst van [laadToegestaneDepotNamen]: óf de set depotnamen waar deze
/// gebruiker bij mag, óf een foutmelding. Een aparte klasse in plaats van een
/// `Set?` die op twee manieren leeg kan zijn — anders is "nog niets geladen",
/// "geen enkel depot" en "opvraging mislukt" niet uit elkaar te houden, en dat
/// was precies wat de drie schermen hieronder in een eeuwige laad-animatie
/// liet hangen zodra de opvraging faalde.
class DepotToegang {
  /// null = geen beperking (admin/superadmin ziet alles).
  final Set<String>? toegestaneNamen;
  final String? fout;

  const DepotToegang.alles() : toegestaneNamen = null, fout = null;
  const DepotToegang.beperkt(Set<String> namen) : toegestaneNamen = namen, fout = null;
  const DepotToegang.mislukt(String this.fout) : toegestaneNamen = const {};

  bool get isGelukt => fout == null;

  /// Mag deze depotnaam getoond worden?
  bool magZien(String depotNaam) => toegestaneNamen == null || toegestaneNamen!.contains(depotNaam);
}

/// Voert een schrijfactie op Firestore uit en toont een foutmelding als die
/// mislukt; geeft terug of het gelukt is.
///
/// Alle toevoeg-/wijzig-/verwijderknoppen in deze app riepen Firestore eerder
/// zonder afhandeling aan. Mislukte de schrijfactie — geen internet, geen
/// rechten volgens firestore.rules — dan sloot het dialoogvenster alsnog en
/// leek alles gelukt, terwijl er in werkelijkheid niets was opgeslagen. Geef
/// hier de context van de PAGINA mee (niet die van het dialoogvenster), zodat
/// de melding blijft staan nadat het dialoogvenster gesloten is.
Future<bool> probeerSchrijfactie(BuildContext context, String omschrijving, Future<void> Function() actie) async {
  try {
    await actie();
    return true;
  } catch (fout) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$omschrijving mislukt: $fout'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return false;
  }
}

/// Haalt op welke depotnamen bij de clusters van deze gebruiker horen.
/// Wordt gebruikt door Afwijkingen, Rapportage en de bel op de homepage, die
/// alle drie de dagplanning-lijst nog eens extra op depotnaam nafilteren.
Future<DepotToegang> laadToegestaneDepotNamen({
  required String rol,
  required String bedrijfId,
  required List<String> toegewezenClusters,
}) async {
  if (rol == 'admin' || rol == 'superadmin') return const DepotToegang.alles();
  if (toegewezenClusters.isEmpty) return const DepotToegang.beperkt({});
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('depots')
        .where('bedrijfId', isEqualTo: bedrijfId)
        .where('clusterId', whereIn: beperkVoorWhereIn(toegewezenClusters))
        .get();
    return DepotToegang.beperkt(snapshot.docs.map((d) => (d.data()['naam'] ?? '').toString()).toSet());
  } catch (fout) {
    return DepotToegang.mislukt('$fout');
  }
}

/// Zelfde als `showDialog()`, maar keert pas terug als het dialoogvenster
/// écht weg is — dus ook nadat de sluit-animatie is afgelopen.
///
/// Waarom dit bestaat. Een dialoogvenster met invoervelden maakt zijn
/// TextEditingControllers aan vóór het openen en ruimt ze op in een
/// `finally` erna:
///
/// ```dart
/// final naamController = TextEditingController();
/// try {
///   await toonDialoog(context: context, builder: ...);
/// } finally {
///   naamController.dispose();
/// }
/// ```
///
/// Met het gewone `showDialog()` gaat dat mis. Dat keert namelijk al terug
/// zodra er `Navigator.pop()` is gedaan, terwijl het venster dan nog 150 ms
/// staat weg te faden. Sluit in diezelfde 150 ms het toetsenbord — en dat
/// gebeurt altijd, want je hebt net in een tekstveld getypt — dan verandert
/// de schermhoogte, wordt de boom opnieuw opgebouwd inclusief dat wegfadende
/// venster, en pakt het tekstveld een controller die er niet meer is:
///
///     A TextEditingController was used after being disposed.
///
/// Daarna volgt de echte schade: de opbouw klapt er middenin uit, en de
/// gebruiker krijgt een rood scherm met een verwarrende vervolgfout
/// (`'_dependents.isEmpty': is not true`) die niets met de oorzaak te maken
/// lijkt te hebben.
///
/// `route.completed` wacht wél op de animatie: die is klaar zodra het
/// venster uit de overlay is verwijderd. Daarna kan er niets meer opnieuw
/// worden opgebouwd en is opruimen veilig.
///
/// Gebruik dit dus overal waar een dialoogvenster eigen controllers heeft.
/// Voor een simpel ja/nee-venster zonder invoervelden maakt het niet uit.
Future<T?> toonDialoog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  // rootNavigator: true — zelfde keuze als showDialog() zelf maakt, zodat een
  // dialoogvenster boven alles komt en niet in een geneste Navigator blijft
  // hangen.
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    // Zonder dit meegeven verliest het venster het thema van de pagina
    // waar het vandaan komt (kleuren, tekststijlen).
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  final resultaat = await navigator.push<T>(route);
  await route.completed;
  return resultaat;
}
