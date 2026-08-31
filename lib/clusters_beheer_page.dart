import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

/// Pagina voor een bedrijf-admin om het eigen bedrijf te beheren: de
/// bedrijfsnaam hernoemen, en clusters toevoegen/hernoemen/verwijderen.
/// Wordt ook gebruikt door de superadmin, die via de "Openen"-knop op
/// SuperadminBedrijvenPage met dezelfde rechten in een specifiek bedrijf
/// terechtkomt (zie firestore.rules: magBeherenBedrijf()).
class ClustersBeheerPage extends StatelessWidget {
  final String bedrijfId;
  const ClustersBeheerPage({super.key, required this.bedrijfId});

  Future<void> _hernoemBedrijf(BuildContext context, String huidigeNaam) async {
    final naamController = TextEditingController(text: huidigeNaam);
    final formKey = GlobalKey<FormState>();

    final String? nieuweNaam;
    try {
      nieuweNaam = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bedrijfsnaam wijzigen'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: naamController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Bedrijfsnaam'),
              validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een naam in' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, naamController.text.trim());
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      );
    } finally {
      naamController.dispose();
    }
    if (nieuweNaam == null || !context.mounted) return;
    await probeerSchrijfactie(context, 'Bedrijfsnaam wijzigen', () async {
      await FirebaseFirestore.instance.collection('bedrijven').doc(bedrijfId).update({'naam': nieuweNaam!});
    });
  }

  Future<void> _toonClusterDialoog(BuildContext context, {String? docId, String? huidigeNaam}) async {
    final naamController = TextEditingController(text: huidigeNaam ?? '');
    final formKey = GlobalKey<FormState>();

    try {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(docId == null ? 'Cluster toevoegen' : 'Cluster hernoemen'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: naamController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Naam (bijv. Regio Noord)'),
              validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een naam in' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final naam = naamController.text.trim();
                final gelukt = await probeerSchrijfactie(context, 'Cluster opslaan', () async {
                  if (docId == null) {
                    await FirebaseFirestore.instance.collection('clusters').add({'naam': naam, 'bedrijfId': bedrijfId});
                  } else {
                    await FirebaseFirestore.instance.collection('clusters').doc(docId).update({'naam': naam});
                  }
                });
                if (gelukt && dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      );
    } finally {
      naamController.dispose();
    }
  }

  Future<void> _bevestigClusterVerwijderen(BuildContext context, String clusterId, String naam) async {
    // Eerst tellen of er nog depots in dit cluster zitten, zodat er
    // gewaarschuwd kan worden voordat er per ongeluk data "onbereikbaar"
    // wordt (depots zonder geldig cluster blijven wel gewoon bestaan, maar
    // zijn dan nergens meer aan te klikken vanuit de app).
    final int aantalDepots;
    try {
      final depotsInCluster = await FirebaseFirestore.instance
          .collection('depots')
          .where('bedrijfId', isEqualTo: bedrijfId)
          .where('clusterId', isEqualTo: clusterId)
          .get();
      aantalDepots = depotsInCluster.docs.length;
    } catch (fout) {
      // Faalde deze telling, dan gebeurde er voorheen niets zichtbaars en
      // leek de prullenbak-knop kapot.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kan depots van dit cluster niet tellen: $fout'), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    if (!context.mounted) return;
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cluster "$naam" verwijderen?'),
        content: Text(
          aantalDepots > 0
              ? 'Let op: dit cluster heeft nog $aantalDepots ${aantalDepots == 1 ? 'depot' : 'depots'} gekoppeld. '
                    'Die depots (en hun routes) blijven bestaan, maar zijn daarna nergens meer in de app te vinden totdat je ze aan een ander cluster koppelt. Toch verwijderen?'
              : 'Weet je zeker dat je dit cluster wilt verwijderen?',
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
    await probeerSchrijfactie(context, 'Cluster verwijderen', () async {
      await FirebaseFirestore.instance.collection('clusters').doc(clusterId).delete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: const Text('Bedrijf & clusters beheren')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('bedrijven').doc(bedrijfId).snapshots(),
            builder: (context, snapshot) {
              final naam = (snapshot.data?.data() as Map<String, dynamic>?)?['naam']?.toString() ?? '...';
              return Card(
                margin: const EdgeInsets.all(12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _kNavy,
                    child: Icon(Icons.apartment, color: Colors.white),
                  ),
                  title: const Text('Bedrijfsnaam', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(
                    naam,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kNavy),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _hernoemBedrijf(context, naam == '...' ? '' : naam),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Clusters',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('clusters')
                  .where('bedrijfId', isEqualTo: bedrijfId)
                  .orderBy('naam')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Kan clusters niet laden:\n${snapshot.error}', textAlign: TextAlign.center),
                    ),
                  );
                }
                if (!snapshot.hasData) return const Center(child: AppLoader());
                final clusters = snapshot.data!.docs;
                if (clusters.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nog geen clusters. Voeg er hieronder één toe met de + knop.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  itemCount: clusters.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = clusters[index];
                    final naam = (doc.data() as Map<String, dynamic>)['naam']?.toString() ?? 'Onbekend';
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: _kOrange,
                          child: Icon(Icons.location_city, color: Colors.white),
                        ),
                        title: Text(naam, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _toonClusterDialoog(context, docId: doc.id, huidigeNaam: naam),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _bevestigClusterVerwijderen(context, doc.id, naam),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _toonClusterDialoog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
