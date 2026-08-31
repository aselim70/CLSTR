import 'package:flutter_test/flutter_test.dart';
import 'package:clstr_app/app_helpers.dart';

/// De oude test/widget_test.dart was nog het standaard Flutter-voorbeeld voor
/// een teller-app die hier nooit heeft bestaan — `flutter test` faalde daar
/// dus altijd op. Vervangen door tests op de datum-logica: dat is de plek waar
/// een fout stilletjes tot verkeerde dagplanningen leidt, en het is precies
/// het stuk dat zonder emulator te testen is.
void main() {
  group('plusDagen / alleenDatum', () {
    test('telt hele kalenderdagen op, ook over een maandgrens', () {
      expect(plusDagen(DateTime(2026, 1, 30), 3), DateTime(2026, 2, 2));
      expect(plusDagen(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });

    test('werkt over een jaargrens', () {
      expect(plusDagen(DateTime(2025, 12, 31), 1), DateTime(2026, 1, 1));
    });

    test('houdt rekening met een schrikkeljaar', () {
      expect(plusDagen(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    });

    test('zet de tijd op middernacht', () {
      expect(alleenDatum(DateTime(2026, 5, 4, 23, 59, 59)), DateTime(2026, 5, 4));
    });
  });

  group('weekDagen', () {
    test('geeft maandag t/m zondag, ongeacht welke dag je meegeeft', () {
      // 2026-09-02 is een woensdag.
      final dagen = weekDagen(DateTime(2026, 9, 2));
      expect(dagen.length, 7);
      expect(dagen.first, DateTime(2026, 8, 31)); // maandag
      expect(dagen.last, DateTime(2026, 9, 6)); // zondag
      expect(dagen.first.weekday, DateTime.monday);
      expect(dagen.last.weekday, DateTime.sunday);
    });

    test('geeft voor een zondag de week die er die dag mee eindigt', () {
      final dagen = weekDagen(DateTime(2026, 9, 6));
      expect(dagen.first, DateTime(2026, 8, 31));
      expect(dagen.last, DateTime(2026, 9, 6));
    });
  });

  group('dagenTussen', () {
    test('is inclusief begin- en einddag', () {
      final dagen = dagenTussen(DateTime(2026, 4, 1), DateTime(2026, 4, 3));
      expect(dagen, [DateTime(2026, 4, 1), DateTime(2026, 4, 2), DateTime(2026, 4, 3)]);
    });

    test('geeft één dag terug als begin en eind gelijk zijn', () {
      expect(dagenTussen(DateTime(2026, 4, 1), DateTime(2026, 4, 1)).length, 1);
    });

    // Dit is de bug waar het om ging: rond de overgang naar wintertijd (in
    // Nederland de laatste zondag van oktober) duurt de dag 25 uur. Een lus
    // met add(Duration(days: 1)) leverde die zondag twee keer op en sloeg een
    // andere dag over.
    test('slaat rond de klokwissel in oktober geen dag over en herhaalt er geen', () {
      final dagen = dagenTussen(DateTime(2026, 10, 23), DateTime(2026, 11, 2));
      expect(dagen.length, 11);
      expect(dagen.map(dateKey).toSet().length, 11, reason: 'geen dubbele datums');
      expect(dagen.map(dateKey), contains('2026-10-25')); // de dag van de klokwissel
      expect(dagen.map(dateKey), contains('2026-10-26'));
    });

    test('slaat rond de klokwissel in maart geen dag over', () {
      final dagen = dagenTussen(DateTime(2026, 3, 26), DateTime(2026, 4, 2));
      expect(dagen.length, 8);
      expect(dagen.map(dateKey).toSet().length, 8);
      expect(dagen.map(dateKey), contains('2026-03-29')); // de dag van de klokwissel
    });
  });

  group('aantalDagen', () {
    test('telt begin- en einddag mee', () {
      expect(aantalDagen(DateTime(2026, 1, 1), DateTime(2026, 1, 7)), 7);
      expect(aantalDagen(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), 1);
    });

    // Beide richtingen van de klokwissel, want ze gaan elk een andere kant op
    // mis: in oktober zit er een uur extra tussen twee middernachten, in maart
    // een uur minder (waardoor een naïeve .inDays-berekening naar beneden
    // afkapt en er een dag te weinig uitkomt).
    test('klopt over de klokwissel in oktober (25 uur durende dag)', () {
      expect(aantalDagen(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 3);
    });

    test('klopt over de klokwissel in maart (23 uur durende dag)', () {
      expect(aantalDagen(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 3);
      expect(aantalDagen(DateTime(2026, 3, 29), DateTime(2026, 3, 29)), 1);
    });

    test('klopt voor een hele week rond beide klokwissels', () {
      expect(aantalDagen(DateTime(2026, 3, 23), DateTime(2026, 3, 29)), 7);
      expect(aantalDagen(DateTime(2026, 10, 19), DateTime(2026, 10, 25)), 7);
    });

    test('komt overeen met de lengte van dagenTussen', () {
      final start = DateTime(2026, 10, 20);
      final eind = DateTime(2026, 11, 5);
      expect(aantalDagen(start, eind), dagenTussen(start, eind).length);
    });
  });

  group('dateKey', () {
    test('gebruikt het formaat waarin dagplanning-documenten zijn opgeslagen', () {
      expect(dateKey(DateTime(2026, 9, 1)), '2026-09-01');
      expect(dateKey(DateTime(2026, 12, 25, 14, 30)), '2026-12-25');
    });

    test('sorteert alfabetisch in dezelfde volgorde als chronologisch', () {
      // Hier leunen de Firestore-queries op (datum >= start en <= eind).
      final sleutels = [DateTime(2026, 9, 9), DateTime(2026, 9, 10), DateTime(2026, 10, 1)].map(dateKey).toList();
      final gesorteerd = [...sleutels]..sort();
      expect(gesorteerd, sleutels);
    });
  });

  group('beperkVoorWhereIn', () {
    test('laat een lijst binnen de limiet ongemoeid', () {
      final waarden = List.generate(5, (i) => 'cluster$i');
      expect(beperkVoorWhereIn(waarden), waarden);
      expect(whereInOverschreden(waarden), isFalse);
    });

    test('knipt af op de Firestore-limiet van 30 in plaats van te crashen', () {
      final waarden = List.generate(42, (i) => 'cluster$i');
      expect(beperkVoorWhereIn(waarden).length, maxWhereInWaarden);
      expect(whereInOverschreden(waarden), isTrue);
    });
  });
}
