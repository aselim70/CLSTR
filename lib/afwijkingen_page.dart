import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'route_detail_page.dart';
import 'app_theme.dart';

class AfwijkingenPage extends StatefulWidget {
  final String rol;
  final List<String> toegewezenClusters;
  const AfwijkingenPage({super.key, required this.rol, required this.toegewezenClusters});

  @override
  State<AfwijkingenPage> createState() => _AfwijkingenPageState();
}

class _AfwijkingenPageState extends State<AfwijkingenPage> {
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

  @override
  Widget build(BuildContext context) {
    if (_bezigMetToegangLaden) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Afwijkingen')),
        body: const Center(child: AppLoader()),
      );
    }

    final isAdmin = widget.rol == 'admin';

    if (!isAdmin && widget.toegewezenClusters.isEmpty) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Afwijkingen')),
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

    // Net als bij Overzicht: voor een sub-account moet deze query ook op
    // clusterId filteren, anders keurt Firestore de hele lijst-query af
    // zodra er een dagplanning van een ander cluster bij zit.
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance.collection('dagplanning').snapshots()
        : FirebaseFirestore.instance
            .collection('dagplanning')
            .where('clusterId', whereIn: widget.toegewezenClusters)
            .snapshots();

    return Scaffold(
      appBar: GradientAppBar(title: const Text('Afwijkingen')),
      body: StreamBuilder<QuerySnapshot>(
        stream: dagStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Fout: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppLoader());
          }

          final afwijkingen = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['eindtijd'] != null) return false;
            if (_toegestaneDepotNamen != null) {
              final depotNaam = (data['depotNaam'] ?? '').toString();
              if (!_toegestaneDepotNamen!.contains(depotNaam)) return false;
            }
            return true;
          }).toList()
            ..sort((a, b) {
              final datumA = (a.data() as Map<String, dynamic>)['datum'] as String? ?? '';
              final datumB = (b.data() as Map<String, dynamic>)['datum'] as String? ?? '';
              return datumB.compareTo(datumA);
            });

          if (afwijkingen.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                    SizedBox(height: 16),
                    Text(
                      'Geen afwijkingen. Alle geregistreerde ritten zijn compleet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: afwijkingen.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = afwijkingen[index];
              final data = doc.data() as Map<String, dynamic>;
              final routeNaam = data['routeNaam'] ?? 'Onbekende route';
              final depotNaam = data['depotNaam'] ?? '';
              final routeClusterId = data['clusterId']?.toString();
              final chauffeurNaam = data['chauffeurNaam'] ?? 'Onbekend';
              final starttijd = data['starttijd'] ?? '-';
              final datumRaw = data['datum'] as String?;
              final geparsedDatum = datumRaw != null ? DateTime.tryParse(datumRaw) : null;
              final datumWeergave = geparsedDatum != null ? DateFormat('dd-MM-yyyy').format(geparsedDatum) : (datumRaw ?? '-');

              return Card(
                elevation: 0,
                color: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.hourglass_bottom, color: Colors.white, size: 20),
                  ),
                  title: Text(routeNaam, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$depotNaam · $chauffeurNaam\n$datumWeergave · start $starttijd · eindtijd ontbreekt'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RouteDetailPage(
                          routeNaam: routeNaam,
                          depotNaam: depotNaam,
                          clusterId: routeClusterId,
                          initieleDatum: geparsedDatum,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}