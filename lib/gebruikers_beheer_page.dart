import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

const List<Map<String, String>> _clusterOpties = [
  {'id': 'cluster_1', 'naam': 'Cluster 1'},
  {'id': 'cluster_2', 'naam': 'Cluster 2'},
  {'id': 'cluster_3', 'naam': 'Cluster 3'},
];

class GebruikersBeheerPage extends StatelessWidget {
  const GebruikersBeheerPage({super.key});

  Future<void> _toonGebruikerDialoog(
    BuildContext context, {
    String? bestaandeEmail,
    String? huidigeRol,
    List<String>? huidigeClusters,
  }) async {
    final emailController = TextEditingController(text: bestaandeEmail ?? '');
    final formKey = GlobalKey<FormState>();
    String rol = huidigeRol ?? 'subaccount';
    final geselecteerdeClusters = <String>{...?huidigeClusters};

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(bestaandeEmail == null ? 'Account koppelen' : 'Account bewerken'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: emailController,
                        enabled: bestaandeEmail == null,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mailadres (waarmee diegene inlogt)'),
                        validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een e-mailadres in' : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Let op: het account zelf (e-mail + wachtwoord) maak je apart aan via Firebase Console → Authentication. Hier koppel je alleen de rol en clusters.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: rol,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Hoofdaccount (ziet alle clusters)', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'subaccount',
                            child: Text('Sub-account (alleen gekoppelde clusters)', overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        onChanged: (waarde) {
                          if (waarde != null) setDialogState(() => rol = waarde);
                        },
                      ),
                      if (rol == 'subaccount') ...[
                        const SizedBox(height: 14),
                        const Text('Toegewezen clusters:', style: TextStyle(fontWeight: FontWeight.w600)),
                        ..._clusterOpties.map((cluster) {
                          final id = cluster['id']!;
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(cluster['naam']!),
                            value: geselecteerdeClusters.contains(id),
                            onChanged: (aangevinkt) {
                              setDialogState(() {
                                if (aangevinkt == true) {
                                  geselecteerdeClusters.add(id);
                                } else {
                                  geselecteerdeClusters.remove(id);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final email = emailController.text.trim().toLowerCase();
                    await FirebaseFirestore.instance.collection('gebruikers').doc(email).set({
                      'email': email,
                      'rol': rol,
                      'clusters': rol == 'admin' ? <String>[] : geselecteerdeClusters.toList(),
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

  /// Eenmalige migratie: voegt het juiste `clusterId` toe aan alle bestaande
  /// `routes`- en `dagplanning`-documenten, op basis van hun depot. Dit is
  /// nodig voordat de Firestore Security Rules aangezet kunnen worden — die
  /// rules moeten per document snel kunnen zien bij welk cluster het hoort.
  /// Mag gerust meerdere keren uitgevoerd worden, dat is onschadelijk.
  Future<void> _voerMigratieUit(BuildContext context) async {
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cluster-ID migratie uitvoeren?'),
        content: const Text(
          'Dit voegt het cluster-ID toe aan alle bestaande routes en dagplanningen, op basis van hun depot. '
          'Dit is een eenmalige voorbereiding voor de beveiligingsregels. Je kunt dit gerust meerdere keren uitvoeren, dat doet geen kwaad.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Uitvoeren')),
        ],
      ),
    );
    if (bevestigd != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            AppLoader(),
            SizedBox(width: 16),
            Expanded(child: Text('Bezig met migreren...')),
          ],
        ),
      ),
    );

    final depotsSnapshot = await FirebaseFirestore.instance.collection('depots').get();
    final depotNaarCluster = <String, String>{};
    for (final doc in depotsSnapshot.docs) {
      final data = doc.data();
      final naam = data['naam']?.toString();
      final clusterId = data['clusterId']?.toString();
      if (naam != null && clusterId != null) depotNaarCluster[naam] = clusterId;
    }

    int routesBijgewerkt = 0;
    int dagplanningBijgewerkt = 0;
    int nietGevonden = 0;

    var batch = FirebaseFirestore.instance.batch();
    int teller = 0;

    Future<void> voegToeAanBatch(DocumentReference ref, String? depotNaam, void Function() opTeller) async {
      final clusterId = depotNaarCluster[depotNaam];
      if (clusterId == null) {
        nietGevonden++;
        return;
      }
      batch.update(ref, {'clusterId': clusterId});
      opTeller();
      teller++;
      if (teller >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        teller = 0;
      }
    }

    final routesSnapshot = await FirebaseFirestore.instance.collection('routes').get();
    for (final doc in routesSnapshot.docs) {
      await voegToeAanBatch(doc.reference, doc.data()['depotNaam']?.toString(), () => routesBijgewerkt++);
    }

    final dagplanningSnapshot = await FirebaseFirestore.instance.collection('dagplanning').get();
    for (final doc in dagplanningSnapshot.docs) {
      await voegToeAanBatch(doc.reference, doc.data()['depotNaam']?.toString(), () => dagplanningBijgewerkt++);
    }

    if (teller > 0) {
      await batch.commit();
    }

    if (!context.mounted) return;
    Navigator.pop(context); // sluit de laad-dialoog

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Migratie voltooid'),
        content: Text(
          '$routesBijgewerkt routes en $dagplanningBijgewerkt dagplanningen bijgewerkt met een cluster-ID.'
          '${nietGevonden > 0 ? '\n\n$nietGevonden documenten konden niet gekoppeld worden (depot niet gevonden, bijv. omdat het depot inmiddels verwijderd is) — controleer deze zo nodig handmatig.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten')),
        ],
      ),
    );
  }

  Future<void> _bevestigVerwijderen(BuildContext context, String email) async {
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Toegang intrekken?'),
        content: Text('Weet je zeker dat je de toegang van "$email" wilt intrekken? Dit account kan dan niet meer inloggen in de app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Intrekken'),
          ),
        ],
      ),
    );
    if (bevestigd == true) {
      await FirebaseFirestore.instance.collection('gebruikers').doc(email).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: const Text('Sub-accounts beheren')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: _kOrange.withOpacity(0.12),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Nieuw account? Maak eerst de inlog (e-mail + wachtwoord) aan via Firebase Console → Authentication. Koppel hier daarna de rol en clusters.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: OutlinedButton.icon(
              onPressed: () => _voerMigratieUit(context),
              icon: const Icon(Icons.sync),
              label: const Text('Eenmalige migratie: cluster-ID toevoegen aan routes/dagplanning'),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('gebruikers').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: AppLoader());
                final docs = snapshot.data!.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
                if (docs.isEmpty) {
                  return const Center(child: Text('Nog geen accounts gekoppeld.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final email = doc.id;
                    final rol = (data['rol'] as String?) ?? 'subaccount';
                    final clusters = (data['clusters'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [];
                    final clusterNamen = clusters
                        .map((id) => _clusterOpties.firstWhere(
                              (c) => c['id'] == id,
                              orElse: () => {'naam': id},
                            )['naam'])
                        .join(', ');
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade300)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: rol == 'admin' ? _kNavy : _kOrange,
                          child: Icon(rol == 'admin' ? Icons.shield : Icons.person, color: Colors.white, size: 20),
                        ),
                        title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          rol == 'admin'
                              ? 'Hoofdaccount — ziet alle clusters'
                              : (clusterNamen.isEmpty ? 'Nog geen cluster toegewezen' : clusterNamen),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _toonGebruikerDialoog(
                                context,
                                bestaandeEmail: email,
                                huidigeRol: rol,
                                huidigeClusters: clusters,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _bevestigVerwijderen(context, email),
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
        onPressed: () => _toonGebruikerDialoog(context),
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }
}