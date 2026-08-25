import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'route_detail_page.dart';
import 'app_theme.dart';

const Color _kNavy = Color(0xFF002169);

class OverzichtPage extends StatefulWidget {
  final String rol;
  final List<String> toegewezenClusters;
  const OverzichtPage({super.key, required this.rol, required this.toegewezenClusters});

  @override
  State<OverzichtPage> createState() => _OverzichtPageState();
}

class _OverzichtPageState extends State<OverzichtPage> {
  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Widget _legendeItem(Color kleur, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: kleur)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

    final vandaag = DateTime.now();
    final vandaagKey = _dateKey(vandaag);

    // Belangrijk: filteren op clusterId (niet op depotNaam) - de query moet
    // filteren op precies het veld dat de security rule checkt, anders
    // weigert Firestore de hele lijst-opvraging vooraf.
    final Stream<QuerySnapshot> routesStream = isAdmin
        ? FirebaseFirestore.instance.collection('routes').orderBy('naam').snapshots()
        : FirebaseFirestore.instance
            .collection('routes')
            .where('clusterId', whereIn: widget.toegewezenClusters)
            .snapshots();

    // Belangrijk: voor een sub-account moet deze query ook op clusterId
    // filteren. De security rules staan alleen toe dat je documenten van je
    // eigen cluster leest, en Firestore keurt een hele lijst-query af zodra
    // er ook maar één resultaat bij zit dat niet mag (zoals dagplanningen
    // van een ander cluster van dezelfde dag). Door hier ook op clusterId
    // te filteren, blijft de query altijd binnen wat is toegestaan.
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance
            .collection('dagplanning')
            .where('datum', isEqualTo: vandaagKey)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('dagplanning')
            .where('datum', isEqualTo: vandaagKey)
            .where('clusterId', whereIn: widget.toegewezenClusters)
            .snapshots();

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
                  Icon(Icons.today_rounded, color: _kNavy.withOpacity(0.7), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Huidige situatie · ${DateFormat('dd-MM-yyyy').format(vandaag)}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: _kNavy.withOpacity(0.8)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _legendeItem(Colors.green.shade400, 'Compleet'),
                  _legendeItem(Colors.orange.shade400, 'Gestart, niet compleet'),
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

                  return StreamBuilder<QuerySnapshot>(
                    stream: dagStream,
                    builder: (context, dagSnapshot) {
                      if (dagSnapshot.hasError) {
                        return Center(child: Text('Fout: ${dagSnapshot.error}'));
                      }
                      if (dagSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: AppLoader());
                      }

                      final dagDataPerRoute = <String, Map<String, dynamic>>{};
                      for (final doc in dagSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final depotNaam = (data['depotNaam'] ?? '').toString();
                        final routeNaam = (data['routeNaam'] ?? '').toString();
                        dagDataPerRoute['$depotNaam|$routeNaam'] = data;
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: routes.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final routeDoc = routes[index];
                          final routeData = routeDoc.data() as Map<String, dynamic>;
                          final routeNaam = routeData['naam']?.toString() ?? 'Onbekende route';
                          final depotNaam = routeData['depotNaam']?.toString() ?? '';
                          final ritnummer = routeData['ritnummer']?.toString();
                          final routeClusterId = routeData['clusterId']?.toString();

                          final dagData = dagDataPerRoute['$depotNaam|$routeNaam'];
                          final chauffeurNaam = dagData?['chauffeurNaam'] as String?;
                          final isCompleet = dagData != null &&
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
                                    initieleDatum: vandaag,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
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
                decoration: BoxDecoration(
                  color: statusKleur,
                  borderRadius: BorderRadius.circular(4),
                ),
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
                    isCompleet ? Icons.check_circle : (heeftData ? Icons.hourglass_bottom : Icons.radio_button_unchecked),
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