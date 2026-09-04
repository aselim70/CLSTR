import 'package:flutter_test/flutter_test.dart';

// Relatief geïmporteerd: het script staat in tool/ en niet in lib/, dus er is
// geen 'package:clstr_app/...'-pad naartoe. Voor een hulpscript is dat ook
// precies goed — het hoort niet mee de app in.
import '../tool/bump_versie.dart';

/// De rekenlogica van tool/bump_versie.dart. Klein stukje code, maar wel het
/// soort fout dat je pas ontdekt als Google Play een upload weigert nadat de
/// hele build al gedraaid heeft.
void main() {
  group('volgendeVersie', () {
    test('patch hoogt het laatste cijfer én het buildnummer op', () {
      expect(volgendeVersie('1.2.3+7', 'patch'), '1.2.4+8');
    });

    test('minor zet patch terug op nul', () {
      expect(volgendeVersie('1.2.3+7', 'minor'), '1.3.0+8');
    });

    test('major zet minor en patch terug op nul', () {
      expect(volgendeVersie('1.2.3+7', 'major'), '2.0.0+8');
    });

    test('build laat de versienaam ongemoeid', () {
      expect(volgendeVersie('1.2.3+7', 'build'), '1.2.3+8');
    });

    test('het buildnummer loopt bij elke soort op - anders weigert Play de upload', () {
      for (final soort in ['major', 'minor', 'patch', 'build']) {
        expect(volgendeVersie('1.0.0+41', soort), endsWith('+42'), reason: 'bij soort "$soort"');
      }
    });

    test('een versie zonder buildnummer begint bij +1', () {
      expect(volgendeVersie('1.0.0', 'patch'), '1.0.1+1');
    });

    test('een onvolledige versienaam wordt aangevuld tot drie cijfers', () {
      expect(volgendeVersie('2+3', 'patch'), '2.0.1+4');
    });
  });

  group('lezen en vervangen in pubspec.yaml', () {
    const pubspec = '''
name: clstr_app
description: "A new Flutter project."
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: '>=3.9.0 <4.0.0'
''';

    test('leest de versie van de juiste regel', () {
      expect(leesVersie(pubspec), '1.0.0+1');
    });

    test('vervangt alleen de versieregel en laat de rest heel', () {
      final nieuw = vervangVersie(pubspec, '1.1.0+2');
      expect(nieuw, contains('version: 1.1.0+2'));
      expect(nieuw, contains('name: clstr_app'));
      expect(nieuw, contains("sdk: '>=3.9.0 <4.0.0'"));
      expect(nieuw, isNot(contains('1.0.0+1')));
    });

    test('laat de lege regels rond de versieregel staan', () {
      // Deze ging eerder mis: de regex eindigde op `\s*$`, en omdat `\s` ook
      // newlines matcht slikte de vervanging de regelovergang plus de lege
      // regel erna in. Na één ophoging plakte `environment:` dus tegen de
      // versieregel aan.
      final nieuw = vervangVersie(pubspec, '1.1.0+2');
      expect(nieuw, contains("publish_to: 'none'\n\nversion: 1.1.0+2\n\nenvironment:"));
    });

    test('geeft null als er geen versieregel is', () {
      expect(leesVersie('name: clstr_app\n'), isNull);
    });
  });
}
