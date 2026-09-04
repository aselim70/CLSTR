import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

class PersonenPage extends StatefulWidget {
  final String bedrijfId;
  const PersonenPage({super.key, required this.bedrijfId});

  @override
  State<PersonenPage> createState() => _PersonenPageState();
}

class _PersonenPageState extends State<PersonenPage> {
  bool _zoekModusActief = false;
  String _zoekTerm = '';
  final TextEditingController _zoekController = TextEditingController();

  @override
  void dispose() {
    _zoekController.dispose();
    super.dispose();
  }

  Future<void> _toonChauffeurDialoog({String? docId, String? huidigeNaam}) async {
    final naamController = TextEditingController(text: huidigeNaam ?? '');
    final formKey = GlobalKey<FormState>();

    try {
      await toonDialoog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(docId == null ? 'Chauffeur toevoegen' : 'Chauffeur bewerken'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: naamController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Naam'),
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
                  final naam = naamController.text.trim();
                  final gelukt = await probeerSchrijfactie(context, 'Chauffeur opslaan', () async {
                    if (docId == null) {
                      await FirebaseFirestore.instance.collection('chauffeurs').add({
                        'naam': naam,
                        'bedrijfId': widget.bedrijfId,
                      });
                    } else {
                      await FirebaseFirestore.instance.collection('chauffeurs').doc(docId).update({'naam': naam});
                    }
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
      naamController.dispose();
    }
  }

  Future<void> _bevestigVerwijderen(String docId, String naam) async {
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chauffeur verwijderen?'),
        content: Text('Weet je zeker dat je $naam wilt verwijderen?'),
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
    if (bevestigd != true || !mounted) return;
    await probeerSchrijfactie(context, 'Chauffeur verwijderen', () async {
      await FirebaseFirestore.instance.collection('chauffeurs').doc(docId).delete();
    });
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

  @override
  Widget build(BuildContext context) {
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
            : const Text('Chauffeurs'),
        actions: [IconButton(icon: Icon(_zoekModusActief ? Icons.close : Icons.search), onPressed: _zoekModusWisselen)],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chauffeurs')
            .where('bedrijfId', isEqualTo: widget.bedrijfId)
            .orderBy('naam')
            .snapshots(),
        builder: (context, snapshot) {
          // Zonder hasError-tak bleef dit scherm eeuwig laden zodra de query
          // faalde (bijv. ontbrekende index op bedrijfId + naam).
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Kan chauffeurs niet laden:\n${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: AppLoader());
          var chauffeurs = snapshot.data!.docs;

          if (_zoekTerm.isNotEmpty) {
            chauffeurs = chauffeurs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final naam = (data['naam'] ?? '').toString().toLowerCase();
              return naam.contains(_zoekTerm);
            }).toList();
          }

          if (chauffeurs.isEmpty) {
            return Center(
              child: Text(_zoekTerm.isEmpty ? 'Nog geen chauffeurs toegevoegd.' : 'Geen chauffeurs gevonden.'),
            );
          }

          return ListView.separated(
            itemCount: chauffeurs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = chauffeurs[index];
              final data = doc.data() as Map<String, dynamic>;
              final naam = data['naam'] ?? 'Onbekend';
              return ListTile(
                title: Text(naam),
                onTap: () => _toonChauffeurDialoog(docId: doc.id, huidigeNaam: naam),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _bevestigVerwijderen(doc.id, naam),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _toonChauffeurDialoog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
