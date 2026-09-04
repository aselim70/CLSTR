/// Controleert of de geïnstalleerde app nog nieuw genoeg is voor de backend.
///
/// Waarom dit bestaat: de app en de backend worden op totaal verschillende
/// snelheden bijgewerkt. Firestore-regels en Cloud Functions rol je binnen
/// seconden uit (`firebase deploy`), maar een nieuwe app-versie moet eerst
/// door de review van Google Play / de App Store én daarna nog door de
/// gebruiker geïnstalleerd worden. Tussen die twee momenten zitten dagen.
///
/// Zonder controle betekent dat: zodra je een veld hernoemt, een Cloud
/// Function-parameter wijzigt of een regel aanscherpt, blijven oude
/// installaties gewoon draaien — maar met stille fouten. De gebruiker ziet
/// dan een leeg scherm of een onbegrijpelijke melding en belt jou, terwijl de
/// echte oorzaak "app te oud" is.
///
/// Daarom: bij het opstarten wordt het document `app_config/versie` gelezen.
/// Staat daar een `minimumBuild` die hoger is dan het buildnummer van deze
/// installatie, dan komt de gebruiker niet verder dan het updatescherm.
///
/// Het document instellen (Firebase Console → Firestore → collectie
/// `app_config`, document-ID `versie`):
///
///   minimumBuild     (number)  bijv. 12 — verplicht; hieronder blokkeren
///   minimumBuildIos  (number)  optioneel; geldt op iOS in plaats van
///                              `minimumBuild`, omdat de buildnummers van de
///                              twee platforms uit aparte tellers komen
///   minimumVersie    (string)  bijv. "1.2.0" — alleen voor de schermtekst
///   bericht          (string)  optionele eigen uitleg
///   storeUrlAndroid  (string)  optioneel; standaard de Play Store-pagina
///   storeUrlIos      (string)  optioneel; App Store-link. Hier is géén
///                              standaard voor: een App Store-link bevat een
///                              nummer dat Apple pas toekent bij de eerste
///                              release. Staat het veld leeg, dan toont het
///                              updatescherm op iOS geen knop.
///
/// Zolang dat document niet bestaat, blokkeert er niets — de app werkt dan
/// precies zoals voorheen.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';

/// Hoe lang we maximaal op Firestore wachten. Firestore valt zonder
/// verbinding terug op zijn lokale cache, maar bij een half-open verbinding
/// (wél wifi, geen internet) kan een opvraging lang blijven hangen. Deze app
/// wordt door chauffeurs onderweg gebruikt, dus dat scenario is realistisch;
/// het opstarten mag daar nooit op vastlopen.
const Duration _maxWachttijd = Duration(seconds: 5);

/// Uitkomst van de controle.
class VersieControle {
  /// Moet de gebruiker eerst bijwerken voordat hij de app in mag?
  final bool updateVereist;

  /// Uitleg voor op het updatescherm.
  final String? bericht;

  /// Waar de knop "Nu bijwerken" naartoe gaat. Null = geen knop tonen.
  final String? storeUrl;

  /// Bijv. "1.0.0 (1)" — handig om op het scherm te tonen, zodat je bij een
  /// telefonische melding meteen weet welke versie iemand draait.
  final String huidigeVersie;

  const VersieControle._({
    required this.updateVereist,
    required this.huidigeVersie,
    this.bericht,
    this.storeUrl,
  });

  /// Doorlaten. Wordt óók gebruikt als de controle zelf mislukt: een gebruiker
  /// buitensluiten omdat er net even geen verbinding is, is een veel erger
  /// probleem dan een te oude app die nog even doordraait. Deze controle is
  /// een vangnet, geen slot.
  const VersieControle.toegestaan(String versie)
    : updateVereist = false,
      huidigeVersie = versie,
      bericht = null,
      storeUrl = null;
}

/// Leest `app_config/versie` en vergelijkt dat met deze installatie.
///
/// Start dit vanuit `main()`, vóór `runApp()`, en geef de Future door aan het
/// splash-scherm. Zo loopt de opvraging parallel aan de opstartanimatie en
/// kost de controle in de praktijk geen extra wachttijd. Roep het niet aan
/// vanuit een `build()`: die draait meerdere keren, en dan zou je bij elke
/// rebuild opnieuw gaan opvragen — dezelfde valkuil als bij de FutureBuilder
/// in main.dart.
Future<VersieControle> controleerAppVersie() async {
  // Het buildnummer (de `+1` uit pubspec.yaml) is het enige nummer dat
  // gegarandeerd bij elke release omhoog gaat — Google Play weigert een
  // upload met een bestaand buildnummer. De versienaam ("1.0.0") is een
  // menselijke keuze en dus niet betrouwbaar te vergelijken.
  int huidigeBuild = 0;
  String versieLabel = 'onbekend';
  String? playStoreUrl;

  try {
    final info = await PackageInfo.fromPlatform().timeout(_maxWachttijd);
    huidigeBuild = int.tryParse(info.buildNumber) ?? 0;
    versieLabel = '${info.version} ($huidigeBuild)';
    if (!kIsWeb && Platform.isAndroid) {
      playStoreUrl = 'https://play.google.com/store/apps/details?id=${info.packageName}';
    }
  } catch (fout) {
    debugPrint('Versiecontrole: app-info onleesbaar ($fout) - controle overgeslagen.');
    return VersieControle.toegestaan(versieLabel);
  }

  // Kon het buildnummer niet gelezen worden, dan is vergelijken zinloos —
  // 0 zou anders altijd "te oud" opleveren en iedereen buitensluiten.
  if (huidigeBuild <= 0) {
    debugPrint('Versiecontrole: geen bruikbaar buildnummer - controle overgeslagen.');
    return VersieControle.toegestaan(versieLabel);
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('versie')
        .get()
        .timeout(_maxWachttijd);

    if (!doc.exists) return VersieControle.toegestaan(versieLabel);
    final data = doc.data() ?? const <String, dynamic>{};

    // `as num` en niet `as int`: wie het veld in de Firebase Console invult,
    // krijgt er soms een double van gemaakt. Dat mag geen cast-fout geven.
    //
    // Twee velden en niet één, omdat de buildnummers van Android en iOS uit
    // verschillende tellers komen: beide releaseworkflows gebruiken hun eigen
    // GitHub-runnummer. Build 120 op Android is dus een andere release dan
    // build 120 op iOS. Zou je met één `minimumBuild` oude Android-versies
    // blokkeren, dan sluit je willekeurige iOS-gebruikers mee buiten. Staat
    // `minimumBuildIos` er niet, dan geldt gewoon `minimumBuild` — zo blijft
    // een bestaand document werken zonder dat je iets hoeft aan te passen.
    final minimumAlgemeen = (data['minimumBuild'] as num?)?.toInt();
    final minimumIos = (data['minimumBuildIos'] as num?)?.toInt();
    final minimumBuild = (!kIsWeb && Platform.isIOS) ? (minimumIos ?? minimumAlgemeen) : minimumAlgemeen;
    if (minimumBuild == null || huidigeBuild >= minimumBuild) {
      return VersieControle.toegestaan(versieLabel);
    }

    final minimumVersie = (data['minimumVersie'] as String?)?.trim();
    final eigenBericht = (data['bericht'] as String?)?.trim();
    final storeUrl = kIsWeb
        ? null
        : (Platform.isIOS
              ? (data['storeUrlIos'] as String?)?.trim()
              : (data['storeUrlAndroid'] as String?)?.trim() ?? playStoreUrl);

    final standaardBericht = minimumVersie == null
        ? 'Er is een nieuwere versie van CLSTR beschikbaar. Werk de app bij om verder te gaan.'
        : 'Er is een nieuwere versie van CLSTR beschikbaar (versie $minimumVersie). '
              'Werk de app bij om verder te gaan.';

    return VersieControle._(
      updateVereist: true,
      huidigeVersie: versieLabel,
      storeUrl: (storeUrl == null || storeUrl.isEmpty) ? null : storeUrl,
      bericht: (eigenBericht == null || eigenBericht.isEmpty) ? standaardBericht : eigenBericht,
    );
  } catch (fout) {
    // Geen verbinding, regels nog niet uitgerold, document onleesbaar: in al
    // die gevallen gewoon doorlaten. Zie de toelichting bij [toegestaan].
    debugPrint('Versiecontrole mislukt ($fout) - gebruiker wordt doorgelaten.');
    return VersieControle.toegestaan(versieLabel);
  }
}

/// Blokkerend scherm: hier komt de gebruiker niet langs zonder bij te werken.
///
/// Bewust géén "Later"-knop. Als dit scherm verschijnt, is de app niet meer
/// compatibel met de backend en zou doorklikken alleen maar tot onverklaarbare
/// fouten verderop leiden. Wél een "Opnieuw proberen": heeft iemand net
/// bijgewerkt, of stond de configuratie verkeerd, dan is dit scherm geen
/// doodlopende weg.
class UpdateVereistScherm extends StatefulWidget {
  final VersieControle controle;

  /// Waar we alsnog naartoe gaan als "Opnieuw proberen" uitwijst dat de app
  /// toch in orde is.
  final Widget volgendeScherm;

  const UpdateVereistScherm({super.key, required this.controle, required this.volgendeScherm});

  @override
  State<UpdateVereistScherm> createState() => _UpdateVereistSchermState();
}

class _UpdateVereistSchermState extends State<UpdateVereistScherm> {
  late VersieControle _controle = widget.controle;
  bool _bezig = false;

  Future<void> _openStore() async {
    final url = _controle.storeUrl;
    if (url == null) return;
    final gelukt = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!gelukt && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('De store kon niet geopend worden. Zoek de app handmatig op als "CLSTR".'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _opnieuwProberen() async {
    setState(() => _bezig = true);
    final opnieuw = await controleerAppVersie();
    if (!mounted) return;
    if (!opnieuw.updateVereist) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.volgendeScherm));
      return;
    }
    setState(() {
      _controle = opnieuw;
      _bezig = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBlauwGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/clstr_logo.png', height: 72, fit: BoxFit.contain),
                  const SizedBox(height: 40),
                  const Icon(Icons.system_update, size: 56, color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'Update vereist',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _controle.bericht ?? 'Werk de app bij om verder te gaan.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  if (_controle.storeUrl != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _bezig ? null : _openStore,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Nu bijwerken'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kBlauwBoven,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _bezig ? null : _opnieuwProberen,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: _bezig
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Opnieuw proberen'),
                  ),
                  const SizedBox(height: 28),
                  // Zichtbaar houden: bij een telefonische melding is dit het
                  // eerste wat je wilt weten.
                  Text(
                    'Geïnstalleerd: ${_controle.huidigeVersie}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
