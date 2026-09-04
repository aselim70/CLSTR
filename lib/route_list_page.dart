import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_detail_page.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class RouteListPage extends StatelessWidget {
  final String depotNaam;
  final String clusterId;
  final String bedrijfId;
  final bool bewerkbaar;

  const RouteListPage({
    super.key,
    required this.depotNaam,
    required this.clusterId,
    required this.bedrijfId,
    this.bewerkbaar = false,
  });

  Future<void> _toonRouteDialoog(BuildContext context) async {
    final ritnummerController = TextEditingController();
    final naamController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      await toonDialoog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Route toevoegen'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: ritnummerController,
                    decoration: const InputDecoration(labelText: 'Ritnummer (bijv. 622)'),
                    keyboardType: TextInputType.number,
                    validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een ritnummer in' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: naamController,
                    decoration: const InputDecoration(labelText: 'Naam (bijv. 622 RSD Westrand)'),
                    validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een naam in' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final ritnummer = ritnummerController.text.trim();
                  final naam = naamController.text.trim();
                  final gelukt = await probeerSchrijfactie(context, 'Route toevoegen', () async {
                    await FirebaseFirestore.instance.collection('routes').add({
                      'ritnummer': ritnummer,
                      'naam': naam,
                      'depotNaam': depotNaam,
                      'clusterId': clusterId,
                      'bedrijfId': bedrijfId,
                    });
                  });
                  if (gelukt && dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Opslaan'),
              ),
            ],
          );
        },
      );
    } finally {
      // Zonder deze dispose() lekt er per geopend dialoogvenster een paar
      // TextEditingControllers dat nooit meer wordt opgeruimd.
      ritnummerController.dispose();
      naamController.dispose();
    }
  }

  Future<void> _bevestigRouteVerwijderen(BuildContext context, String docId, String naam) async {
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Route verwijderen?'),
        content: Text(
          'Weet je zeker dat je "$naam" wilt verwijderen? Eerder opgeslagen dagplanningen voor deze route blijven wel bestaan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (bevestigd != true || !context.mounted) return;
    await probeerSchrijfactie(context, 'Route verwijderen', () async {
      await FirebaseFirestore.instance.collection('routes').doc(docId).delete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: Text(depotNaam)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE7EAF3), Color(0xFFF4F5F9)],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          // Belangrijk: naast depotNaam ook op clusterId filteren. Firestore
          // keurt een lijst-opvraging alleen goed als de query zelf al
          // filtert op precies het veld dat de security rule checkt
          // (clusterId) - anders wordt de hele opvraging vooraf geweigerd,
          // ook al zou de data zelf wel kloppen.
          stream: FirebaseFirestore.instance
              .collection('routes')
              .where('bedrijfId', isEqualTo: bedrijfId)
              .where('depotNaam', isEqualTo: depotNaam)
              .where('clusterId', isEqualTo: clusterId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Fout: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: AppLoader());
            }
            final routes = snapshot.data!.docs;
            if (routes.isEmpty) {
              return const Center(child: Text('Nog geen routes bij dit depot.'));
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 20, 16, bewerkbaar ? 88 : 20),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                final data = route.data() as Map<String, dynamic>;
                final naam = data['naam']?.toString() ?? 'Onbekende route';
                final ritnummer = data['ritnummer']?.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RouteKaart(
                    naam: naam,
                    ritnummer: ritnummer,
                    bewerkbaar: bewerkbaar,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RouteDetailPage(
                            routeNaam: naam,
                            depotNaam: depotNaam,
                            clusterId: clusterId,
                            bedrijfId: bedrijfId,
                          ),
                        ),
                      );
                    },
                    onDelete: () => _bevestigRouteVerwijderen(context, route.id, naam),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: bewerkbaar
          ? FloatingActionButton(onPressed: () => _toonRouteDialoog(context), child: const Icon(Icons.add))
          : null,
    );
  }
}

class _RouteKaart extends StatelessWidget {
  final String naam;
  final String? ritnummer;
  final bool bewerkbaar;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RouteKaart({
    required this.naam,
    required this.ritnummer,
    required this.bewerkbaar,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.alt_route_rounded, color: _kNavy, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      naam,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kNavy),
                    ),
                    if (ritnummer != null && ritnummer!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Rit $ritnummer', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ),
                  ],
                ),
              ),
              if (bewerkbaar)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  onPressed: onDelete,
                ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right, color: _kOrange, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
