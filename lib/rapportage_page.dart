import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_theme.dart';

const List<String> _maandNamen = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
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
  final List<String> toegewezenClusters;
  const RapportagePage({super.key, required this.rol, required this.toegewezenClusters});

  @override
  State<RapportagePage> createState() => _RapportagePageState();
}

class _RapportagePageState extends State<RapportagePage> {
  String _weergave = 'week';
  DateTime _referentieDatum = DateTime.now();
  Set<String>? _geselecteerd;
  Set<String>? _toegestaneDepotNamen;
  bool _bezigMetToegangLaden = true;

  @override
  void initState() {
    super.initState();
    _laadToegestaneDepots();
  }

  Future<void> _laadToegestaneDepots() async {
    if (widget.rol == 'admin') {
      setState(() => _bezigMetToegangLaden = false);
      return;
    }
    if (widget.toegewezenClusters.isEmpty) {
      setState(() {
        _toegestaneDepotNamen = <String>{};
        _bezigMetToegangLaden = false;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('depots')
        .where('clusterId', whereIn: widget.toegewezenClusters)
        .get();
    if (!mounted) return;
    setState(() {
      _toegestaneDepotNamen = snapshot.docs.map((d) => (d.data()['naam'] ?? '').toString()).toSet();
      _bezigMetToegangLaden = false;
    });
  }

  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  DateTime _weekStart(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
  DateTime _weekEind(DateTime d) => _weekStart(d).add(const Duration(days: 6));
  DateTime _maandStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _maandEind(DateTime d) => DateTime(d.year, d.month + 1, 0);

  void _vorigePeriode() {
    setState(() {
      _geselecteerd = null;
      if (_weergave == 'week') {
        _referentieDatum = _referentieDatum.subtract(const Duration(days: 7));
      } else {
        _referentieDatum = DateTime(_referentieDatum.year, _referentieDatum.month - 1, 1);
      }
    });
  }

  void _volgendePeriode() {
    setState(() {
      _geselecteerd = null;
      if (_weergave == 'week') {
        _referentieDatum = _referentieDatum.add(const Duration(days: 7));
      } else {
        _referentieDatum = DateTime(_referentieDatum.year, _referentieDatum.month + 1, 1);
      }
    });
  }

  String _periodeLabel() {
    if (_weergave == 'week') {
      final start = _weekStart(_referentieDatum);
      final eind = _weekEind(_referentieDatum);
      return 'Week van ${DateFormat('dd-MM-yyyy').format(start)} t/m ${DateFormat('dd-MM-yyyy').format(eind)}';
    } else {
      return '${_maandNamen[_referentieDatum.month - 1]} ${_referentieDatum.year}';
    }
  }

  Future<void> _exporteerNaarPdf(Map<String, _ChauffeurTotaal> perChauffeur, List<String> geselecteerdeNamen) async {
    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CLSTR — Rapportage', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(_periodeLabel(), style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
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
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => document.save());
  }

  @override
  Widget build(BuildContext context) {
    if (_bezigMetToegangLaden) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Rapportage')),
        body: const Center(child: AppLoader()),
      );
    }

    final isAdmin = widget.rol == 'admin';

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

    final periodeStart = _weergave == 'week' ? _weekStart(_referentieDatum) : _maandStart(_referentieDatum);
    final periodeEind = _weergave == 'week' ? _weekEind(_referentieDatum) : _maandEind(_referentieDatum);
    final startKey = _dateKey(periodeStart);
    final eindKey = _dateKey(periodeEind);

    // Net als bij Overzicht/Afwijkingen: voor een sub-account moet deze
    // query ook op clusterId filteren, anders keurt Firestore de hele
    // lijst-query af zodra er een dagplanning van een ander cluster in de
    // gekozen periode bij zit.
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance
            .collection('dagplanning')
            .where('datum', isGreaterThanOrEqualTo: startKey)
            .where('datum', isLessThanOrEqualTo: eindKey)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('dagplanning')
            .where('datum', isGreaterThanOrEqualTo: startKey)
            .where('datum', isLessThanOrEqualTo: eindKey)
            .where('clusterId', whereIn: widget.toegewezenClusters)
            .snapshots();

    return Scaffold(
      appBar: GradientAppBar(title: const Text('Rapportage')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'maand', label: Text('Maand')),
              ],
              selected: {_weergave},
              onSelectionChanged: (nieuweSelectie) {
                setState(() {
                  _weergave = nieuweSelectie.first;
                  _geselecteerd = null;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _vorigePeriode),
                Expanded(
                  child: Center(
                    child: Text(_periodeLabel(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _volgendePeriode),
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
                  if (_toegestaneDepotNamen != null) {
                    final depotNaam = (data['depotNaam'] ?? '').toString();
                    if (!_toegestaneDepotNamen!.contains(depotNaam)) continue;
                  }
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

                final geselecteerdeNamen = namen.where((naam) => _geselecteerd == null || _geselecteerd!.contains(naam)).toList();

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
                          Text('${geselecteerdeNamen.length}/${namen.length}', style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: namen.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final naam = namen[index];
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
                            secondary: Text('${uren}u ${minuten}m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                              children: [
                                Icon(Icons.print),
                                SizedBox(width: 8),
                                Text('Printen / PDF exporteren'),
                              ],
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