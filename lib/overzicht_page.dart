import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'route_detail_page.dart';
import 'route_geschiedenis_page.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);

class OverzichtPage extends StatefulWidget {
  final String rol;
  final String bedrijfId;
  final List<String> toegewezenClusters;
  const OverzichtPage({super.key, required this.rol, required this.bedrijfId, required this.toegewezenClusters});

  @override
  State<OverzichtPage> createState() => _OverzichtPageState();
}

class _OverzichtPageState extends State<OverzichtPage> {
  DateTime _geselecteerdeDatum = alleenDatum(DateTime.now());
  DateTimeRange? _bereik; // null = één dag bekijken (op basis van _geselecteerdeDatum); anders een periode
  String? _geselecteerdDepot; // null = alle depots
  String? _geselecteerdeRoute; // null = alle routes

  bool get _isVandaag {
    final nu = DateTime.now();
    return _geselecteerdeDatum.year == nu.year &&
        _geselecteerdeDatum.month == nu.month &&
        _geselecteerdeDatum.day == nu.day;
  }

  void _vorigePeriode() {
    setState(() {
      if (_bereik != null) {
        final lengte = aantalDagen(_bereik!.start, _bereik!.end);
        _bereik = DateTimeRange(start: plusDagen(_bereik!.start, -lengte), end: plusDagen(_bereik!.end, -lengte));
      } else {
        _geselecteerdeDatum = plusDagen(_geselecteerdeDatum, -1);
      }
    });
  }

  void _volgendePeriode() {
    setState(() {
      if (_bereik != null) {
        final lengte = aantalDagen(_bereik!.start, _bereik!.end);
        _bereik = DateTimeRange(start: plusDagen(_bereik!.start, lengte), end: plusDagen(_bereik!.end, lengte));
      } else {
        _geselecteerdeDatum = plusDagen(_geselecteerdeDatum, 1);
      }
    });
  }

  /// Vraagt eerst of de gebruiker één dag of een periode wil bekijken, en
  /// opent daarna de bijbehorende kiezer (losse datum, of een van-tot
  /// periode). Zo blijft "snel 1 dag bekijken" net zo makkelijk als voorheen,
  /// terwijl je ook een vrije periode kunt kiezen.
  Future<void> _kiesDatumOfPeriode() async {
    final keuze = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Wat wil je bekijken?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'dag'),
            child: const Row(
              children: [
                Icon(Icons.today_rounded, color: _kNavy),
                SizedBox(width: 12),
                Text('Eén specifieke dag'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'periode'),
            child: const Row(
              children: [
                Icon(Icons.date_range_rounded, color: _kNavy),
                SizedBox(width: 12),
                Text('Periode (van - tot)'),
              ],
            ),
          ),
        ],
      ),
    );

    if (!mounted || keuze == null) return;

    if (keuze == 'dag') {
      final gekozen = await showDatePicker(
        context: context,
        initialDate: _geselecteerdeDatum,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (gekozen != null) {
        setState(() {
          _geselecteerdeDatum = alleenDatum(gekozen);
          _bereik = null;
        });
      }
    } else {
      final huidigBereik =
          _bereik ?? DateTimeRange(start: plusDagen(_geselecteerdeDatum, -6), end: _geselecteerdeDatum);
      final gekozen = await showDateRangePicker(
        context: context,
        initialDateRange: huidigBereik,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (gekozen != null) {
        setState(() => _bereik = DateTimeRange(start: alleenDatum(gekozen.start), end: alleenDatum(gekozen.end)));
      }
    }
  }

  bool get _heeftActieveFilters =>
      _geselecteerdDepot != null || _geselecteerdeRoute != null || _bereik != null || !_isVandaag;

  void _wisFilters() {
    setState(() {
      _geselecteerdeDatum = alleenDatum(DateTime.now());
      _bereik = null;
      _geselecteerdDepot = null;
      _geselecteerdeRoute = null;
    });
  }

  Widget _legendeItem(Color kleur, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: kleur),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.rol == 'admin';

    if (!isAdmin && widget.toegewezenClusters.isEmpty) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Overzicht')),
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

    final bereikActief = _bereik != null;
    final geselecteerdeDatumKey = dateKey(_geselecteerdeDatum);
    final periodeDagenAantal = bereikActief ? aantalDagen(_bereik!.start, _bereik!.end) : 0;

    // Firestore accepteert maximaal 30 waarden in een whereIn-filter; met meer
    // gooit de query een ArgumentError nog voordat er iets verstuurd wordt.
    final clusterFilter = beperkVoorWhereIn(widget.toegewezenClusters);

    // Belangrijk: filteren op clusterId (niet op depotNaam) - de query moet
    // filteren op precies het veld dat de security rule checkt, anders
    // weigert Firestore de hele lijst-opvraging vooraf.
    final Stream<QuerySnapshot> routesStream = isAdmin
        ? FirebaseFirestore.instance
              .collection('routes')
              .where('bedrijfId', isEqualTo: widget.bedrijfId)
              .orderBy('naam')
              .snapshots()
        : FirebaseFirestore.instance
              .collection('routes')
              .where('bedrijfId', isEqualTo: widget.bedrijfId)
              .where('clusterId', whereIn: clusterFilter)
              .snapshots();

    // Belangrijk: voor een sub-account moet deze query ook op clusterId
    // filteren. De security rules staan alleen toe dat je documenten van je
    // eigen cluster leest, en Firestore keurt een hele lijst-query af zodra
    // er ook maar één resultaat bij zit dat niet mag (zoals dagplanningen
    // van een ander cluster van dezelfde dag). Door hier ook op clusterId
    // te filteren, blijft de query altijd binnen wat is toegestaan.
    final Stream<QuerySnapshot> dagStream = bereikActief
        ? (isAdmin
              ? FirebaseFirestore.instance
                    .collection('dagplanning')
                    .where('bedrijfId', isEqualTo: widget.bedrijfId)
                    .where('datum', isGreaterThanOrEqualTo: dateKey(_bereik!.start))
                    .where('datum', isLessThanOrEqualTo: dateKey(_bereik!.end))
                    .snapshots()
              : FirebaseFirestore.instance
                    .collection('dagplanning')
                    .where('bedrijfId', isEqualTo: widget.bedrijfId)
                    .where('datum', isGreaterThanOrEqualTo: dateKey(_bereik!.start))
                    .where('datum', isLessThanOrEqualTo: dateKey(_bereik!.end))
                    .where('clusterId', whereIn: clusterFilter)
                    .snapshots())
        : (isAdmin
              ? FirebaseFirestore.instance
                    .collection('dagplanning')
                    .where('bedrijfId', isEqualTo: widget.bedrijfId)
                    .where('datum', isEqualTo: geselecteerdeDatumKey)
                    .snapshots()
              : FirebaseFirestore.instance
                    .collection('dagplanning')
                    .where('bedrijfId', isEqualTo: widget.bedrijfId)
                    .where('datum', isEqualTo: geselecteerdeDatumKey)
                    .where('clusterId', whereIn: clusterFilter)
                    .snapshots());

    return Scaffold(
      appBar: GradientAppBar(title: const Text('Overzicht')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE7EAF3), Color(0xFFF4F5F9)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: _kNavy,
                    onPressed: _vorigePeriode,
                    tooltip: bereikActief ? 'Vorige periode' : 'Vorige dag',
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _kiesDatumOfPeriode,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              bereikActief ? Icons.date_range_rounded : Icons.calendar_today_rounded,
                              color: _kNavy.withValues(alpha: 0.7),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                bereikActief
                                    ? '${DateFormat('dd-MM-yyyy').format(_bereik!.start)} t/m ${DateFormat('dd-MM-yyyy').format(_bereik!.end)}'
                                    : (_isVandaag
                                          ? 'Vandaag · ${DateFormat('dd-MM-yyyy').format(_geselecteerdeDatum)}'
                                          : DateFormat('dd-MM-yyyy').format(_geselecteerdeDatum)),
                                style: TextStyle(fontWeight: FontWeight.w600, color: _kNavy.withValues(alpha: 0.8)),
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
                    color: _kNavy,
                    onPressed: _volgendePeriode,
                    tooltip: bereikActief ? 'Volgende periode' : 'Volgende dag',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: bereikActief
                    ? [
                        _legendeItem(Colors.green.shade400, 'Alle dagen compleet'),
                        _legendeItem(Colors.orange.shade400, 'Deels compleet'),
                        _legendeItem(Colors.grey.shade400, 'Geen data'),
                      ]
                    : [
                        _legendeItem(Colors.green.shade400, 'Compleet'),
                        _legendeItem(Colors.orange.shade400, 'Gestart'),
                        _legendeItem(Colors.grey.shade400, 'Nog niet gestart'),
                      ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: routesStream,
                builder: (context, routeSnapshot) {
                  if (routeSnapshot.hasError) {
                    return Center(child: Text('Fout: ${routeSnapshot.error}'));
                  }
                  if (routeSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: AppLoader());
                  }
                  final routes = routeSnapshot.data!.docs.toList();
                  if (!isAdmin) {
                    routes.sort((a, b) {
                      final naamA = (a.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                      final naamB = (b.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                      return naamA.compareTo(naamB);
                    });
                  }
                  if (routes.isEmpty) {
                    return const Center(child: Text('Nog geen routes gevonden.'));
                  }

                  // Beschikbare depot- en route-namen voor de filters, op basis
                  // van alle routes waar deze gebruiker toegang toe heeft
                  // (dus onafhankelijk van de gekozen datum/periode).
                  final alleDepotNamen =
                      routes
                          .map((doc) => (doc.data() as Map<String, dynamic>)['depotNaam']?.toString() ?? '')
                          .where((naam) => naam.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();

                  final routesVoorDepotFilter = _geselecteerdDepot == null
                      ? routes
                      : routes
                            .where(
                              (doc) =>
                                  (doc.data() as Map<String, dynamic>)['depotNaam']?.toString() == _geselecteerdDepot,
                            )
                            .toList();

                  final alleRouteNamen =
                      routesVoorDepotFilter
                          .map((doc) => (doc.data() as Map<String, dynamic>)['naam']?.toString() ?? '')
                          .where((naam) => naam.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();

                  // Als de eerder gekozen route niet meer bij het gekozen
                  // depot hoort (bijv. na het wijzigen van het depot-filter),
                  // negeren we het route-filter stilzwijgend totdat de
                  // gebruiker opnieuw kiest.
                  final actieveRouteFilter =
                      (_geselecteerdeRoute != null && alleRouteNamen.contains(_geselecteerdeRoute))
                      ? _geselecteerdeRoute
                      : null;

                  var gefilterdeRoutes = routesVoorDepotFilter;
                  if (actieveRouteFilter != null) {
                    gefilterdeRoutes = gefilterdeRoutes
                        .where((doc) => (doc.data() as Map<String, dynamic>)['naam']?.toString() == actieveRouteFilter)
                        .toList();
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _geselecteerdDepot,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: _kNavy, width: 1.5),
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Alle depots')),
                                  ...alleDepotNamen.map(
                                    (naam) => DropdownMenuItem<String?>(
                                      value: naam,
                                      child: Text(naam, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (waarde) {
                                  setState(() {
                                    _geselecteerdDepot = waarde;
                                    _geselecteerdeRoute = null; // route-filter reset bij ander depot
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: actieveRouteFilter,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: _kNavy, width: 1.5),
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Alle routes')),
                                  ...alleRouteNamen.map(
                                    (naam) => DropdownMenuItem<String?>(
                                      value: naam,
                                      child: Text(naam, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (waarde) => setState(() => _geselecteerdeRoute = waarde),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_heeftActieveFilters)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _wisFilters,
                              icon: const Icon(Icons.filter_alt_off, size: 18),
                              label: const Text('Filters wissen'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: gefilterdeRoutes.isEmpty
                            ? const Center(child: Text('Geen routes gevonden voor deze filters.'))
                            : StreamBuilder<QuerySnapshot>(
                                stream: dagStream,
                                builder: (context, dagSnapshot) {
                                  if (dagSnapshot.hasError) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          'Fout: ${dagSnapshot.error}\n\nAls hier staat dat er een "index" nodig is: open de link in de foutmelding, klik op "Create Index" in Firebase, wacht ~1 minuut en probeer opnieuw.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    );
                                  }
                                  if (dagSnapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: AppLoader());
                                  }

                                  if (!bereikActief) {
                                    // Weergave voor één dag: per route de status/chauffeur van die dag.
                                    final dagDataPerRoute = <String, Map<String, dynamic>>{};
                                    for (final doc in dagSnapshot.data!.docs) {
                                      final data = doc.data() as Map<String, dynamic>;
                                      final depotNaam = (data['depotNaam'] ?? '').toString();
                                      final routeNaam = (data['routeNaam'] ?? '').toString();
                                      dagDataPerRoute['$depotNaam|$routeNaam'] = data;
                                    }

                                    return ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                      itemCount: gefilterdeRoutes.length,
                                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final routeDoc = gefilterdeRoutes[index];
                                        final routeData = routeDoc.data() as Map<String, dynamic>;
                                        final routeNaam = routeData['naam']?.toString() ?? 'Onbekende route';
                                        final depotNaam = routeData['depotNaam']?.toString() ?? '';
                                        final ritnummer = routeData['ritnummer']?.toString();
                                        final routeClusterId = routeData['clusterId']?.toString();

                                        final dagData = dagDataPerRoute['$depotNaam|$routeNaam'];
                                        final chauffeurNaam = dagData?['chauffeurNaam'] as String?;
                                        final isCompleet =
                                            dagData != null &&
                                            dagData['starttijd'] != null &&
                                            dagData['eindtijd'] != null &&
                                            dagData['stopsGeladen'] != null &&
                                            dagData['stopsGeleverd'] != null;

                                        return _RouteOverzichtBalk(
                                          routeNaam: routeNaam,
                                          depotNaam: depotNaam,
                                          ritnummer: ritnummer,
                                          chauffeurNaam: chauffeurNaam,
                                          heeftData: dagData != null,
                                          isCompleet: isCompleet,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => RouteDetailPage(
                                                  routeNaam: routeNaam,
                                                  depotNaam: depotNaam,
                                                  clusterId: routeClusterId,
                                                  bedrijfId: widget.bedrijfId,
                                                  initieleDatum: _geselecteerdeDatum,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }

                                  // Weergave voor een periode: per route een samenvatting over
                                  // alle dagen in de gekozen periode; tikken opent de volledige
                                  // dag-voor-dag geschiedenis van die ene route.
                                  final dataPerRoute = <String, List<Map<String, dynamic>>>{};
                                  for (final doc in dagSnapshot.data!.docs) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final depotNaam = (data['depotNaam'] ?? '').toString();
                                    final routeNaam = (data['routeNaam'] ?? '').toString();
                                    dataPerRoute.putIfAbsent('$depotNaam|$routeNaam', () => []).add(data);
                                  }

                                  return ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                    itemCount: gefilterdeRoutes.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final routeDoc = gefilterdeRoutes[index];
                                      final routeData = routeDoc.data() as Map<String, dynamic>;
                                      final routeNaam = routeData['naam']?.toString() ?? 'Onbekende route';
                                      final depotNaam = routeData['depotNaam']?.toString() ?? '';
                                      final ritnummer = routeData['ritnummer']?.toString();
                                      final routeClusterId = routeData['clusterId']?.toString();

                                      final dagen = dataPerRoute['$depotNaam|$routeNaam'] ?? const [];

                                      return _RoutePeriodeBalk(
                                        routeNaam: routeNaam,
                                        depotNaam: depotNaam,
                                        ritnummer: ritnummer,
                                        dagen: dagen,
                                        totaalDagenInPeriode: periodeDagenAantal,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => RouteGeschiedenisPage(
                                                routeNaam: routeNaam,
                                                depotNaam: depotNaam,
                                                clusterId: routeClusterId,
                                                bedrijfId: widget.bedrijfId,
                                                initieelBereik: _bereik!,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
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
      ),
    );
  }
}

class _RouteOverzichtBalk extends StatelessWidget {
  final String routeNaam;
  final String depotNaam;
  final String? ritnummer;
  final String? chauffeurNaam;
  final bool heeftData;
  final bool isCompleet;
  final VoidCallback onTap;

  const _RouteOverzichtBalk({
    required this.routeNaam,
    required this.depotNaam,
    required this.ritnummer,
    required this.chauffeurNaam,
    required this.heeftData,
    required this.isCompleet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color achtergrond;
    final Color rand;
    final Color statusKleur;
    final String statusTekst;

    if (!heeftData) {
      // Helemaal niets gekoppeld voor vandaag -> neutraal, geen kleurlabel.
      achtergrond = Colors.white;
      rand = Colors.grey.shade300;
      statusKleur = Colors.grey.shade400;
      statusTekst = 'Nog niet gestart';
    } else if (isCompleet) {
      achtergrond = Colors.green.shade50;
      rand = Colors.green.shade200;
      statusKleur = Colors.green.shade600;
      statusTekst = 'Compleet';
    } else {
      // Er is al iets ingevuld (bijv. chauffeur + starttijd), maar nog niet alles.
      achtergrond = Colors.orange.shade50;
      rand = Colors.orange.shade200;
      statusKleur = Colors.orange.shade600;
      statusTekst = 'Gestart, nog niet compleet';
    }

    final chauffeurWeergave = chauffeurNaam ?? '—';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: achtergrond,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rand),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 44,
                decoration: BoxDecoration(color: statusKleur, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeNaam,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ritnummer != null && ritnummer!.isNotEmpty ? 'Rit $ritnummer · ' : ''}$depotNaam · $statusTekst',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    chauffeurWeergave,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kNavy),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    isCompleet
                        ? Icons.check_circle
                        : (heeftData ? Icons.hourglass_bottom : Icons.radio_button_unchecked),
                    size: 16,
                    color: statusKleur,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rij voor de periode-weergave: samenvatting van één route over de hele
/// gekozen periode (in plaats van de status van 1 dag). Tikken opent de
/// volledige dag-voor-dag geschiedenis van die route.
class _RoutePeriodeBalk extends StatelessWidget {
  final String routeNaam;
  final String depotNaam;
  final String? ritnummer;
  final List<Map<String, dynamic>> dagen;
  final int totaalDagenInPeriode;
  final VoidCallback onTap;

  const _RoutePeriodeBalk({
    required this.routeNaam,
    required this.depotNaam,
    required this.ritnummer,
    required this.dagen,
    required this.totaalDagenInPeriode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heeftData = dagen.isNotEmpty;
    final aantalCompleet = dagen
        .where(
          (d) =>
              d['starttijd'] != null &&
              d['eindtijd'] != null &&
              d['stopsGeladen'] != null &&
              d['stopsGeleverd'] != null,
        )
        .length;
    final isVolledigCompleet = heeftData && aantalCompleet == dagen.length;

    final Color achtergrond;
    final Color rand;
    final Color statusKleur;
    final String statusTekst;
    if (!heeftData) {
      achtergrond = Colors.white;
      rand = Colors.grey.shade300;
      statusKleur = Colors.grey.shade400;
      statusTekst = 'Geen data in deze periode';
    } else if (isVolledigCompleet) {
      achtergrond = Colors.green.shade50;
      rand = Colors.green.shade200;
      statusKleur = Colors.green.shade600;
      statusTekst = '$aantalCompleet/$totaalDagenInPeriode dagen compleet';
    } else {
      achtergrond = Colors.orange.shade50;
      rand = Colors.orange.shade200;
      statusKleur = Colors.orange.shade600;
      statusTekst = '$aantalCompleet/$totaalDagenInPeriode dagen compleet';
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: achtergrond,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rand),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 44,
                decoration: BoxDecoration(color: statusKleur, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeNaam,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavy),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ritnummer != null && ritnummer!.isNotEmpty ? 'Rit $ritnummer · ' : ''}$depotNaam · $statusTekst',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: statusKleur),
            ],
          ),
        ),
      ),
    );
  }
}
