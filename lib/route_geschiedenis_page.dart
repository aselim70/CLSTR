import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);

const List<String> _dagAfkortingenGeschiedenis = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

/// Alleen-lezen overzicht van één specifieke route/rit over een zelf te
/// kiezen periode (van-tot): per dag de chauffeur, tijden en stops, plus een
/// korte samenvatting bovenaan. Los van RouteDetailPage (dat is voor het
/// invullen/bewerken van een enkele dag) - dit scherm is puur om terug te
/// kijken hoe een rit een periode is gegaan.
class RouteGeschiedenisPage extends StatefulWidget {
  final String routeNaam;
  final String depotNaam;
  final String? clusterId;
  final String bedrijfId;
  final DateTimeRange initieelBereik;

  const RouteGeschiedenisPage({
    super.key,
    required this.routeNaam,
    required this.depotNaam,
    required this.clusterId,
    required this.bedrijfId,
    required this.initieelBereik,
  });

  @override
  State<RouteGeschiedenisPage> createState() => _RouteGeschiedenisPageState();
}

class _RouteGeschiedenisPageState extends State<RouteGeschiedenisPage> {
  late DateTimeRange _bereik = DateTimeRange(
    start: alleenDatum(widget.initieelBereik.start),
    end: alleenDatum(widget.initieelBereik.end),
  );

  int get _periodeLengteInDagen => aantalDagen(_bereik.start, _bereik.end);

  void _vorigePeriode() {
    final lengte = _periodeLengteInDagen;
    setState(() {
      _bereik = DateTimeRange(start: plusDagen(_bereik.start, -lengte), end: plusDagen(_bereik.end, -lengte));
    });
  }

  void _volgendePeriode() {
    final lengte = _periodeLengteInDagen;
    setState(() {
      _bereik = DateTimeRange(start: plusDagen(_bereik.start, lengte), end: plusDagen(_bereik.end, lengte));
    });
  }

  Future<void> _kiesPeriode() async {
    final gekozen = await showDateRangePicker(
      context: context,
      initialDateRange: _bereik,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (gekozen != null) {
      setState(() => _bereik = DateTimeRange(start: alleenDatum(gekozen.start), end: alleenDatum(gekozen.end)));
    }
  }

  Widget _samenvattingItem(String waarde, String label) {
    return Column(
      children: [
        Text(
          waarde,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final startKey = dateKey(_bereik.start);
    final eindKey = dateKey(_bereik.end);

    // Belangrijk: net als bij RouteDetailPage ook op clusterId filteren
    // (indien bekend) - de query moet filteren op precies het veld dat de
    // security rule checkt, anders weigert Firestore de hele opvraging
    // vooraf voor sub-accounts.
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('dagplanning')
        .where('bedrijfId', isEqualTo: widget.bedrijfId)
        .where('routeNaam', isEqualTo: widget.routeNaam)
        .where('depotNaam', isEqualTo: widget.depotNaam)
        .where('datum', isGreaterThanOrEqualTo: startKey)
        .where('datum', isLessThanOrEqualTo: eindKey);
    if (widget.clusterId != null) {
      query = query.where('clusterId', isEqualTo: widget.clusterId);
    }

    return Scaffold(
      appBar: GradientAppBar(title: Text('Geschiedenis · ${widget.routeNaam}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _vorigePeriode, tooltip: 'Vorige periode'),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _kiesPeriode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.date_range_rounded, color: _kNavy.withValues(alpha: 0.7), size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${DateFormat('dd-MM-yyyy').format(_bereik.start)} t/m ${DateFormat('dd-MM-yyyy').format(_bereik.end)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Fout: ${snapshot.error}\n\nAls hier staat dat er een "index" nodig is: open de link in de foutmelding, klik op "Create Index" in Firebase, wacht ~1 minuut en probeer opnieuw.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppLoader());
                }

                final dataPerDag = <String, Map<String, dynamic>>{};
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data();
                  final key = data['datum']?.toString();
                  if (key != null) dataPerDag[key] = data;
                }

                final dagen = dagenTussen(_bereik.start, _bereik.end);

                int compleetTeller = 0;
                int totaalMinuten = 0;
                int totaalGeladen = 0;
                int totaalGeleverd = 0;
                for (final data in dataPerDag.values) {
                  final isCompleet =
                      data['starttijd'] != null &&
                      data['eindtijd'] != null &&
                      data['stopsGeladen'] != null &&
                      data['stopsGeleverd'] != null;
                  if (isCompleet) compleetTeller++;
                  final duur = data['duurMinuten'] as int?;
                  if (duur != null) totaalMinuten += duur;
                  final geladen = data['stopsGeladen'] as int?;
                  if (geladen != null) totaalGeladen += geladen;
                  final geleverd = data['stopsGeleverd'] as int?;
                  if (geleverd != null) totaalGeleverd += geleverd;
                }
                final urenTotaal = totaalMinuten ~/ 60;
                final minutenRest = totaalMinuten % 60;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _kNavy.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _samenvattingItem('$compleetTeller/${dagen.length}', 'Compleet'),
                            _samenvattingItem('${urenTotaal}u ${minutenRest}m', 'Totaal uren'),
                            _samenvattingItem('$totaalGeladen', 'Geladen'),
                            _samenvattingItem('$totaalGeleverd', 'Geleverd'),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: dagen.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          // Nieuwste dag bovenaan.
                          final dag = dagen[dagen.length - 1 - index];
                          final data = dataPerDag[dateKey(dag)];
                          return _GeschiedenisDagRij(datum: dag, data: data);
                        },
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

class _GeschiedenisDagRij extends StatelessWidget {
  final DateTime datum;
  final Map<String, dynamic>? data;

  const _GeschiedenisDagRij({required this.datum, required this.data});

  @override
  Widget build(BuildContext context) {
    final chauffeurNaam = data?['chauffeurNaam'] as String?;
    final starttijd = data?['starttijd'] as String?;
    final eindtijd = data?['eindtijd'] as String?;
    final stopsGeladen = data?['stopsGeladen'];
    final stopsGeleverd = data?['stopsGeleverd'];
    final heeftData = data != null;
    final isCompleet =
        heeftData && starttijd != null && eindtijd != null && stopsGeladen != null && stopsGeleverd != null;

    final Color achtergrond;
    final Color rand;
    final Color statusKleur;
    final String statusTekst;
    if (!heeftData) {
      achtergrond = Colors.white;
      rand = Colors.grey.shade300;
      statusKleur = Colors.grey.shade400;
      statusTekst = 'Geen data';
    } else if (isCompleet) {
      achtergrond = Colors.green.shade50;
      rand = Colors.green.shade200;
      statusKleur = Colors.green.shade600;
      statusTekst = 'Compleet';
    } else {
      achtergrond = Colors.orange.shade50;
      rand = Colors.orange.shade200;
      statusKleur = Colors.orange.shade600;
      statusTekst = 'Gedeeltelijk';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: achtergrond,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rand),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                Text(
                  _dagAfkortingenGeschiedenis[datum.weekday - 1],
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${datum.day}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: rand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chauffeurNaam ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: _kNavy),
                ),
                const SizedBox(height: 2),
                Text(
                  heeftData
                      ? '${starttijd ?? '?'} - ${eindtijd ?? '?'}${stopsGeladen != null && stopsGeleverd != null ? ' · $stopsGeladen/$stopsGeleverd stops' : ''}'
                      : 'Niet ingevuld',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusKleur.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusTekst,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusKleur),
            ),
          ),
        ],
      ),
    );
  }
}
