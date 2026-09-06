import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const List<String> _maandNamen = [
  'januari',
  'februari',
  'maart',
  'april',
  'mei',
  'juni',
  'juli',
  'augustus',
  'september',
  'oktober',
  'november',
  'december',
];

class _ChauffeurTotaal {
  int minuten = 0;
  int ritten = 0;
  int onvolledig = 0;
  int stopsGeladen = 0;
  int stopsGeleverd = 0;
}

class RapportagePage extends StatefulWidget {
  final String rol;
  final String bedrijfId;
  final List<String> toegewezenClusters;
  const RapportagePage({super.key, required this.rol, required this.bedrijfId, required this.toegewezenClusters});

  @override
  State<RapportagePage> createState() => _RapportagePageState();
}

class _RapportagePageState extends State<RapportagePage> {
  String _weergave = 'week';
  DateTime _referentieDatum = alleenDatum(DateTime.now());
  // Alleen gevuld zodra de gebruiker zelf een periode kiest ('aangepast').
  DateTimeRange? _eigenBereik;
  Set<String>? _geselecteerd;
  DepotToegang? _toegang;
  bool _zoekModusActief = false;
  String _zoekTerm = '';
  final TextEditingController _zoekController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laadToegestaneDepots();
  }

  @override
  void dispose() {
    _zoekController.dispose();
    super.dispose();
  }

  void _zoekModusWisselen() {
    setState(() {
      if (_zoekModusActief) {
        _zoekController.clear();
        _zoekTerm = '';
      }
      _zoekModusActief = !_zoekModusActief;
    });
  }

  Future<void> _laadToegestaneDepots() async {
    final toegang = await laadToegestaneDepotNamen(
      rol: widget.rol,
      bedrijfId: widget.bedrijfId,
      toegewezenClusters: widget.toegewezenClusters,
    );
    if (!mounted) return;
    setState(() => _toegang = toegang);
  }

  DateTime _maandStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _maandEind(DateTime d) => DateTime(d.year, d.month + 1, 0);

  /// Het bereik dat bij een zelfgekozen periode hoort. Zolang de gebruiker nog
  /// niets koos vallen we terug op de laatste zeven dagen, zodat het scherm
  /// nooit leeg staat te wachten op een keuze.
  DateTimeRange get _huidigEigenBereik {
    final vandaag = alleenDatum(DateTime.now());
    return _eigenBereik ?? DateTimeRange(start: plusDagen(vandaag, -6), end: vandaag);
  }

  /// Bij een zelfgekozen periode schuiven de pijlen met de lengte van die
  /// periode op, net als in de routegeschiedenis.
  int get _eigenPeriodeLengte => _huidigEigenBereik.end.difference(_huidigEigenBereik.start).inDays + 1;

  void _schuifPeriode(int richting) {
    setState(() {
      _geselecteerd = null;
      if (_weergave == 'week') {
        _referentieDatum = plusDagen(_referentieDatum, 7 * richting);
      } else if (_weergave == 'maand') {
        _referentieDatum = DateTime(_referentieDatum.year, _referentieDatum.month + richting, 1);
      } else {
        final stap = _eigenPeriodeLengte * richting;
        final bereik = _huidigEigenBereik;
        _eigenBereik = DateTimeRange(start: plusDagen(bereik.start, stap), end: plusDagen(bereik.end, stap));
      }
    });
  }

  void _vorigePeriode() => _schuifPeriode(-1);

  void _volgendePeriode() => _schuifPeriode(1);

  /// De periode die nu op het scherm staat, ongeacht de gekozen weergave.
  /// Daarmee opent de kalender op wat de gebruiker net bekeek.
  DateTimeRange get _zichtbarePeriode {
    if (_weergave == 'week') {
      return DateTimeRange(start: weekStart(_referentieDatum), end: weekEind(_referentieDatum));
    } else if (_weergave == 'maand') {
      return DateTimeRange(start: _maandStart(_referentieDatum), end: _maandEind(_referentieDatum));
    }
    return _huidigEigenBereik;
  }

  Future<void> _kiesEigenPeriode() async {
    final gekozen = await showDateRangePicker(
      context: context,
      initialDateRange: _zichtbarePeriode,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Kies begin- en einddatum',
      saveText: 'Kiezen',
    );
    if (gekozen == null || !mounted) return;
    setState(() {
      _weergave = 'aangepast';
      _geselecteerd = null;
      _eigenBereik = DateTimeRange(start: alleenDatum(gekozen.start), end: alleenDatum(gekozen.end));
    });
  }

  String _periodeLabel() {
    if (_weergave == 'week') {
      final start = weekStart(_referentieDatum);
      final eind = weekEind(_referentieDatum);
      return 'Week van ${DateFormat('dd-MM-yyyy').format(start)} t/m ${DateFormat('dd-MM-yyyy').format(eind)}';
    } else if (_weergave == 'maand') {
      return '${_maandNamen[_referentieDatum.month - 1]} ${_referentieDatum.year}';
    } else {
      final bereik = _huidigEigenBereik;
      return '${DateFormat('dd-MM-yyyy').format(bereik.start)} t/m ${DateFormat('dd-MM-yyyy').format(bereik.end)}';
    }
  }

  Future<void> _exporteerNaarPdf(Map<String, _ChauffeurTotaal> perChauffeur, List<String> geselecteerdeNamen) async {
    final periodeLabel = _periodeLabel();

    // MultiPage in plaats van Page: bij veel chauffeurs paste de tabel niet
    // op één A4 en werd de rest van de lijst simpelweg afgekapt. MultiPage
    // laat de tabel netjes doorlopen op een volgende pagina, met de
    // kolomkoppen die zichzelf herhalen.
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text('CLSTR — Rapportage · $periodeLabel', style: const pw.TextStyle(fontSize: 10)),
              ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pagina ${context.pageNumber} van ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (context) => [
          pw.Text('CLSTR — Rapportage', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(periodeLabel, style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerCount: 1,
            headers: ['Chauffeur', 'Ritten', 'Onvolledig', 'Totaal uren', 'Stops geladen', 'Stops geleverd'],
            data: geselecteerdeNamen.map((naam) {
              final totaal = perChauffeur[naam]!;
              final uren = totaal.minuten ~/ 60;
              final minuten = totaal.minuten % 60;
              return [
                naam,
                totaal.ritten.toString(),
                totaal.onvolledig.toString(),
                '${uren}u ${minuten}m',
                totaal.stopsGeladen.toString(),
                totaal.stopsGeleverd.toString(),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    // Zonder deze try/catch verdween een mislukte export (geen printer-
    // service op het toestel, geen geheugen, ...) geruisloos in de console en
    // leek de knop niets te doen.
    try {
      await Printing.layoutPdf(onLayout: (format) async => document.save());
    } catch (fout) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exporteren mislukt: $fout')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final toegang = _toegang;
    if (toegang == null) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Rapportage')),
        body: const Center(child: AppLoader()),
      );
    }
    if (!toegang.isGelukt) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Rapportage')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Kan je depots niet ophalen:\n${toegang.fout}', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _toegang = null);
                    _laadToegestaneDepots();
                  },
                  child: const Text('Opnieuw proberen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isAdmin = widget.rol == 'admin';
    final clusterFilter = beperkVoorWhereIn(widget.toegewezenClusters);

    if (!isAdmin && widget.toegewezenClusters.isEmpty) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Rapportage')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Je hebt nog geen cluster toegewezen gekregen. Neem contact op met de beheerder.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final DateTime periodeStart;
    final DateTime periodeEind;
    if (_weergave == 'week') {
      periodeStart = weekStart(_referentieDatum);
      periodeEind = weekEind(_referentieDatum);
    } else if (_weergave == 'maand') {
      periodeStart = _maandStart(_referentieDatum);
      periodeEind = _maandEind(_referentieDatum);
    } else {
      periodeStart = _huidigEigenBereik.start;
      periodeEind = _huidigEigenBereik.end;
    }
    final startKey = dateKey(periodeStart);
    final eindKey = dateKey(periodeEind);

    // Net als bij Overzicht/Afwijkingen: voor een sub-account moet deze
    // query ook op clusterId filteren, anders keurt Firestore de hele
    // lijst-query af zodra er een dagplanning van een ander cluster in de
    // gekozen periode bij zit.
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance
              .collection('dagplanning')
              .where('bedrijfId', isEqualTo: widget.bedrijfId)
              .where('datum', isGreaterThanOrEqualTo: startKey)
              .where('datum', isLessThanOrEqualTo: eindKey)
              .snapshots()
        : FirebaseFirestore.instance
              .collection('dagplanning')
              .where('bedrijfId', isEqualTo: widget.bedrijfId)
              .where('datum', isGreaterThanOrEqualTo: startKey)
              .where('datum', isLessThanOrEqualTo: eindKey)
              .where('clusterId', whereIn: clusterFilter)
              .snapshots();

    return Scaffold(
      appBar: GradientAppBar(
        title: _zoekModusActief
            ? TextField(
                controller: _zoekController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'Zoek op naam...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (waarde) => setState(() => _zoekTerm = waarde.toLowerCase()),
              )
            : const Text('Rapportage'),
        actions: [IconButton(icon: Icon(_zoekModusActief ? Icons.close : Icons.search), onPressed: _zoekModusWisselen)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'maand', label: Text('Maand')),
                ButtonSegment(value: 'aangepast', label: Text('Periode'), icon: Icon(Icons.date_range_rounded)),
              ],
              showSelectedIcon: false,
              selected: {_weergave},
              onSelectionChanged: (nieuweSelectie) {
                final keuze = nieuweSelectie.first;
                // Bij 'Periode' meteen de kalender openen: die stand heeft
                // zonder gekozen datums geen betekenis voor de gebruiker.
                if (keuze == 'aangepast') {
                  _kiesEigenPeriode();
                  return;
                }
                setState(() {
                  _weergave = keuze;
                  _geselecteerd = null;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _vorigePeriode,
                  tooltip: 'Vorige periode',
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _kiesEigenPeriode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          _periodeLabel(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _volgendePeriode,
                  tooltip: 'Volgende periode',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: dagStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Fout: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppLoader());
                }

                final perChauffeur = <String, _ChauffeurTotaal>{};
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (!toegang.magZien((data['depotNaam'] ?? '').toString())) continue;
                  final naam = (data['chauffeurNaam'] as String?) ?? 'Onbekend';
                  final duur = data['duurMinuten'] as int?;
                  final stopsGeladen = data['stopsGeladen'] as int?;
                  final stopsGeleverd = data['stopsGeleverd'] as int?;
                  final entry = perChauffeur.putIfAbsent(naam, () => _ChauffeurTotaal());
                  if (duur != null) {
                    entry.minuten += duur;
                    entry.ritten += 1;
                  } else {
                    entry.onvolledig += 1;
                  }
                  if (stopsGeladen != null) entry.stopsGeladen += stopsGeladen;
                  if (stopsGeleverd != null) entry.stopsGeleverd += stopsGeleverd;
                }

                final namen = perChauffeur.keys.toList()..sort();

                if (namen.isEmpty) {
                  return const Center(child: Text('Nog geen uren geregistreerd in deze periode.'));
                }

                final geselecteerdeNamen = namen
                    .where((naam) => _geselecteerd == null || _geselecteerd!.contains(naam))
                    .toList();

                // De zoekterm filtert alleen wat je ziet, niet wat je exporteert:
                // anders zou een openstaande zoekterm stilletjes chauffeurs uit
                // de PDF houden die je wél had aangevinkt.
                final zichtbareNamen = _zoekTerm.isEmpty
                    ? namen
                    : namen.where((naam) => naam.toLowerCase().contains(_zoekTerm)).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() => _geselecteerd = null),
                            icon: const Icon(Icons.select_all, size: 18),
                            label: const Text('Alles selecteren'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _geselecteerd = <String>{}),
                            icon: const Icon(Icons.deselect, size: 18),
                            label: const Text('Alles deselecteren'),
                          ),
                          const Spacer(),
                          Text(
                            '${geselecteerdeNamen.length}/${namen.length}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (zichtbareNamen.isEmpty)
                      const Expanded(
                        child: Center(child: Text('Geen chauffeur gevonden met deze naam.')),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: zichtbareNamen.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final naam = zichtbareNamen[index];
                            final totaal = perChauffeur[naam]!;
                            final uren = totaal.minuten ~/ 60;
                            final minuten = totaal.minuten % 60;
                            final isGeselecteerd = _geselecteerd == null || _geselecteerd!.contains(naam);
                            return CheckboxListTile(
                              isThreeLine: true,
                              value: isGeselecteerd,
                              onChanged: (waarde) {
                                setState(() {
                                  _geselecteerd ??= Set.of(namen);
                                  if (waarde == true) {
                                    _geselecteerd!.add(naam);
                                  } else {
                                    _geselecteerd!.remove(naam);
                                  }
                                });
                              },
                              title: Text(naam, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${totaal.ritten} ${totaal.ritten == 1 ? 'rit' : 'ritten'} geregistreerd'
                                '${totaal.onvolledig > 0 ? ' · ${totaal.onvolledig} onvolledig' : ''}'
                                '\n${totaal.stopsGeladen} geladen · ${totaal.stopsGeleverd} geleverd',
                              ),
                              secondary: Text(
                                '${uren}u ${minuten}m',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            );
                          },
                        ),
                      ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            onPressed: geselecteerdeNamen.isEmpty
                                ? null
                                : () => _exporteerNaarPdf(perChauffeur, geselecteerdeNamen),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [Icon(Icons.print), SizedBox(width: 8), Text('Printen / PDF exporteren')],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
