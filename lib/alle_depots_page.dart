import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_list_page.dart';
import 'app_theme.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class AlleDepotsPage extends StatelessWidget {
  final String rol;
  final List<String> toegewezenClusters;

  const AlleDepotsPage({super.key, required this.rol, required this.toegewezenClusters});

  Future<void> _toonDepotDialoog(BuildContext context) async {
    final naamController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String geselecteerdCluster = 'cluster_1';

    await showDialog(
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
                      value: geselecteerdCluster,
                      decoration: const InputDecoration(labelText: 'Cluster'),
                      items: const [
                        DropdownMenuItem(value: 'cluster_1', child: Text('Cluster 1')),
                        DropdownMenuItem(value: 'cluster_2', child: Text('Cluster 2')),
                        DropdownMenuItem(value: 'cluster_3', child: Text('Cluster 3')),
                      ],
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
                    await FirebaseFirestore.instance.collection('depots').add({
                      'naam': naamController.text.trim(),
                      'clusterId': geselecteerdCluster,
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );
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
            child: Text('Je hebt nog geen cluster toegewezen gekregen. Neem contact op met de beheerder.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final Stream<QuerySnapshot> stream = isAdmin
        ? FirebaseFirestore.instance.collection('depots').orderBy('naam').snapshots()
        : FirebaseFirestore.instance.collection('depots').where('clusterId', whereIn: toegewezenClusters).snapshots();

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
                          builder: (context) => RouteListPage(depotNaam: naam, clusterId: clusterId, bewerkbaar: true),
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
          ? FloatingActionButton(
              onPressed: () => _toonDepotDialoog(context),
              child: const Icon(Icons.add),
            )
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
      shadowColor: Colors.black.withOpacity(0.15),
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
                  color: _kNavy.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warehouse_rounded, color: _kNavy, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  naam,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _kNavy,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _kOrange.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_right, color: _kOrange, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}