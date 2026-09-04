import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_list_page.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class AlleDepotsPage extends StatelessWidget {
  final String rol;
  final String bedrijfId;
  final List<String> toegewezenClusters;

  const AlleDepotsPage({super.key, required this.rol, required this.bedrijfId, required this.toegewezenClusters});

  Future<void> _toonDepotDialoog(BuildContext context) async {
    // Clusters van dit bedrijf ophalen voor de dropdown - niet meer
    // hardcoded, want elk bedrijf heeft nu zijn eigen clusters (aan te maken
    // via "Bedrijf & clusters beheren").
    final List<MapEntry<String, String>> clusterOpties;
    try {
      final clustersSnapshot = await FirebaseFirestore.instance
          .collection('clusters')
          .where('bedrijfId', isEqualTo: bedrijfId)
          .orderBy('naam')
          .get();
      clusterOpties = clustersSnapshot.docs
          .map((doc) => MapEntry(doc.id, (doc.data()['naam'] ?? doc.id).toString()))
          .toList();
    } catch (fout) {
      // Ging deze opvraging mis, dan gebeurde er voorheen letterlijk niets:
      // de + knop leek kapot terwijl de fout alleen in de console stond.
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kan clusters niet ophalen: $fout'), backgroundColor: Colors.red.shade700));
      return;
    }

    if (!context.mounted) return;
    if (clusterOpties.isEmpty) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nog geen clusters'),
          content: const Text(
            'Maak eerst een cluster aan via "Bedrijf & clusters beheren" voordat je een depot toevoegt.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sluiten'))],
        ),
      );
      return;
    }

    // De controller hoort bij dit dialoogvenster en wordt in de finally weer
    // opgeruimd - zonder die dispose() lekt er per geopend dialoogvenster een
    // TextEditingController (met listeners) die nooit meer vrijkomt.
    final naamController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String geselecteerdCluster = clusterOpties.first.key;

    try {
      await toonDialoog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Depot toevoegen'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: naamController,
                        decoration: const InputDecoration(labelText: 'Naam (bijv. Depot Breda)'),
                        validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een naam in' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: geselecteerdCluster,
                        decoration: const InputDecoration(labelText: 'Cluster'),
                        items: clusterOpties
                            .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                            .toList(),
                        onChanged: (waarde) {
                          if (waarde != null) setDialogState(() => geselecteerdCluster = waarde);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final naam = naamController.text.trim();
                      final gelukt = await probeerSchrijfactie(context, 'Depot toevoegen', () async {
                        await FirebaseFirestore.instance.collection('depots').add({
                          'naam': naam,
                          'clusterId': geselecteerdCluster,
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
        },
      );
    } finally {
      naamController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final magToevoegen = rol == 'admin';
    final isAdmin = rol == 'admin';

    if (!isAdmin && toegewezenClusters.isEmpty) {
      return Scaffold(
        appBar: GradientAppBar(title: const Text('Depots')),
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

    final Stream<QuerySnapshot> stream = isAdmin
        ? FirebaseFirestore.instance
              .collection('depots')
              .where('bedrijfId', isEqualTo: bedrijfId)
              .orderBy('naam')
              .snapshots()
        : FirebaseFirestore.instance
              .collection('depots')
              .where('bedrijfId', isEqualTo: bedrijfId)
              .where('clusterId', whereIn: beperkVoorWhereIn(toegewezenClusters))
              .snapshots();

    return Scaffold(
      appBar: GradientAppBar(title: const Text('Depots')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE7EAF3), Color(0xFFF4F5F9)],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            // Zonder deze hasError-tak bleef het scherm eindeloos de
            // laad-animatie tonen als de query mislukte (ontbrekende index,
            // geen rechten, geen verbinding) — er kwam dan immers nooit data.
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Kan depots niet laden:\n${snapshot.error}', textAlign: TextAlign.center),
                ),
              );
            }
            if (!snapshot.hasData) return const Center(child: AppLoader());
            final depots = snapshot.data!.docs.toList();
            if (!isAdmin) {
              depots.sort((a, b) {
                final naamA = (a.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                final naamB = (b.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                return naamA.compareTo(naamB);
              });
            }
            if (depots.isEmpty) {
              return const Center(child: Text('Nog geen depots toegevoegd.'));
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 20, 16, magToevoegen ? 88 : 20),
              itemCount: depots.length,
              itemBuilder: (context, index) {
                final data = depots[index].data() as Map<String, dynamic>;
                final naam = data['naam']?.toString() ?? 'Onbekend';
                final clusterId = data['clusterId']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DepotKaart(
                    naam: naam,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RouteListPage(
                            depotNaam: naam,
                            clusterId: clusterId,
                            bedrijfId: bedrijfId,
                            bewerkbaar: true,
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
      ),
      floatingActionButton: magToevoegen
          ? FloatingActionButton(onPressed: () => _toonDepotDialoog(context), child: const Icon(Icons.add))
          : null,
    );
  }
}

class _DepotKaart extends StatelessWidget {
  final String naam;
  final VoidCallback onTap;

  const _DepotKaart({required this.naam, required this.onTap});

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
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warehouse_rounded, color: _kNavy, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  naam,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kNavy),
                ),
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
