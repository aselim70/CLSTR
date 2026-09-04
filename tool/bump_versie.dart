/// Hoogt het versienummer in pubspec.yaml op.
///
///   dart run tool/bump_versie.dart patch    1.2.3+7 -> 1.2.4+8
///   dart run tool/bump_versie.dart minor    1.2.3+7 -> 1.3.0+8
///   dart run tool/bump_versie.dart major    1.2.3+7 -> 2.0.0+8
///   dart run tool/bump_versie.dart build    1.2.3+7 -> 1.2.3+8
///
/// Waarom dit een script is en geen "even met de hand aanpassen": het
/// buildnummer (het getal ná de `+`) is het enige dat Google Play
/// daadwerkelijk controleert. Upload je een bundle met een buildnummer dat al
/// eens gebruikt is, dan weigert Play hem — ook als die oude versie allang
/// is ingetrokken. Dat merk je pas nadat de hele build klaar is.
///
/// Let op de rolverdeling met CI: de workflow release-android.yml geeft zelf
/// een buildnummer mee (`--build-number`, afgeleid van het GitHub-runnummer),
/// omdat dat gegarandeerd oploopt zonder dat iemand eraan hoeft te denken.
/// Het buildnummer in pubspec.yaml telt dus alleen voor builds die je lokaal
/// maakt. De versienaam ("1.2.3") komt wél gewoon uit dit bestand — dat is
/// het nummer dat gebruikers in de Play Store zien, en dat is een menselijke
/// keuze die niemand voor je kan automatiseren.
library;

import 'dart:io';

void main(List<String> args) {
  final soort = args.isEmpty ? null : args.first.toLowerCase();
  const geldig = {'major', 'minor', 'patch', 'build'};

  if (soort == null || !geldig.contains(soort)) {
    stderr.writeln('Gebruik: dart run tool/bump_versie.dart <major|minor|patch|build>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml niet gevonden. Draai dit script vanuit de hoofdmap van het project.');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final inhoud = pubspec.readAsStringSync();
  final huidige = leesVersie(inhoud);
  if (huidige == null) {
    stderr.writeln('Geen regel "version: x.y.z+n" gevonden in pubspec.yaml.');
    exitCode = 65; // EX_DATAERR
    return;
  }

  final nieuwe = volgendeVersie(huidige, soort);
  pubspec.writeAsStringSync(vervangVersie(inhoud, nieuwe));

  stdout.writeln('$huidige  ->  $nieuwe');
  stdout.writeln('');
  stdout.writeln('Vergeet niet te committen: git commit -am "Versie $nieuwe"');
}

/// De `version:`-regel van pubspec.yaml. Bewust aan het begin van de regel
/// verankerd (`^` met multiLine), zodat een `version:` die dieper in het
/// bestand als onderdeel van iets anders voorkomt niet per ongeluk meetelt.
///
/// Let op de spatie-en-tab in plaats van `\s`: `\s` matcht óók newlines, dus
/// met `\s*$` slokte deze regex de regelovergang en de lege regel erna mee op.
/// Elke ophoging plakte `environment:` dan strak tegen de versieregel aan.
final RegExp _versieRegel = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

String? leesVersie(String pubspecInhoud) => _versieRegel.firstMatch(pubspecInhoud)?.group(1);

String vervangVersie(String pubspecInhoud, String nieuweVersie) =>
    pubspecInhoud.replaceFirst(_versieRegel, 'version: $nieuweVersie');

/// Rekent uit wat de volgende versie wordt. Aparte functie zodat dit los te
/// testen is — zie test/bump_versie_test.dart.
///
/// Het buildnummer gaat bij elke soort omhoog, ook bij 'major' en 'minor'.
/// Dat is expres: er bestaat geen release waarbij het buildnummer gelijk mag
/// blijven, want dan weigert Google Play de upload.
String volgendeVersie(String huidige, String soort) {
  final delen = huidige.split('+');
  final naam = delen.first;
  // Ontbreekt het buildnummer helemaal (dus "1.2.3" zonder "+n"), dan
  // beginnen we bij 1 — hetzelfde als wat Flutter zelf aanneemt.
  final build = delen.length > 1 ? (int.tryParse(delen[1]) ?? 0) : 0;

  final cijfers = naam.split('.').map((c) => int.tryParse(c) ?? 0).toList();
  while (cijfers.length < 3) {
    cijfers.add(0);
  }
  var (major, minor, patch) = (cijfers[0], cijfers[1], cijfers[2]);

  switch (soort) {
    case 'major':
      major += 1;
      minor = 0;
      patch = 0;
    case 'minor':
      minor += 1;
      patch = 0;
    case 'patch':
      patch += 1;
    case 'build':
      break;
  }

  return '$major.$minor.$patch+${build + 1}';
}
