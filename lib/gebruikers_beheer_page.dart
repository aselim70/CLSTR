import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

/// Zet de foutcode van een Cloud Function-aanroep om naar een begrijpelijke
/// Nederlandse melding. Cloud Functions geven altijd een `code` mee (zie
/// functions/index.js) — hier vertalen we de bekende codes, met een
/// nette terugval op de ruwe foutmelding voor onbekende gevallen.
String _leesFoutmelding(Object fout) {
  if (fout is FirebaseFunctionsException) {
    switch (fout.code) {
      case 'already-exists':
        return 'Er bestaat al een account met dit e-mailadres.';
      case 'invalid-argument':
        return fout.message ?? 'Controleer de ingevulde gegevens.';
      case 'permission-denied':
        // De eigen melding van de functie is specifieker ("Alleen de
        // superadmin kan een hoofdaccount wijzigen") dan een algemeen
        // "geen rechten", dus die krijgt voorrang.
        return fout.message ?? 'Je hebt geen rechten om dit te doen.';
      case 'unauthenticated':
        return 'Je bent niet (meer) ingelogd. Log opnieuw in en probeer het nogmaals.';
      case 'failed-precondition':
        return fout.message ?? 'Deze actie kan niet worden uitgevoerd.';
      case 'unavailable':
        return 'Geen verbinding. Controleer je internetverbinding en probeer het opnieuw.';
      default:
        return fout.message ?? 'Er ging iets mis (${fout.code}).';
    }
  }
  return 'Er ging iets mis: $fout';
}

class GebruikersBeheerPage extends StatelessWidget {
  final String bedrijfId;
  const GebruikersBeheerPage({super.key, required this.bedrijfId});

  Future<void> _toonGebruikerDialoog(
    BuildContext context, {
    String? bestaandeEmail,
    String? huidigeRol,
    List<String>? huidigeClusters,
  }) async {
    // Clusters van dit bedrijf ophalen voor de checkbox-lijst - niet meer
    // hardcoded, want elk bedrijf heeft nu zijn eigen clusters.
    List<Map<String, String>> clusterOpties;
    try {
      final clustersSnapshot = await FirebaseFirestore.instance
          .collection('clusters')
          .where('bedrijfId', isEqualTo: bedrijfId)
          .orderBy('naam')
          .get();
      clusterOpties = clustersSnapshot.docs
          .map((doc) => {'id': doc.id, 'naam': (doc.data()['naam'] ?? doc.id).toString()})
          .toList();
    } catch (fout) {
      // Zonder deze try/catch gebeurde er letterlijk niets zichtbaars als
      // deze opvraging faalde (bijv. door een ontbrekende Firestore-index) -
      // de knop leek dan "kapot" terwijl er alleen een fout onderin verstopt
      // zat. Nu tonen we in elk geval duidelijk wat er misging.
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kan clusters niet ophalen'),
          content: Text(
            'Er ging iets mis bij het ophalen van de clusters:\n\n$fout\n\n'
            'Controleer of de bijbehorende Firestore-index al is aangemaakt en de status "Enabled" heeft.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sluiten'))],
        ),
      );
      return;
    }

    final emailController = TextEditingController(text: bestaandeEmail ?? '');
    final wachtwoordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final nieuwAccount = bestaandeEmail == null;
    String rol = huidigeRol ?? 'subaccount';
    final geselecteerdeClusters = <String>{...?huidigeClusters};
    bool wachtwoordZichtbaar = false;
    bool bezigMetOpslaan = false;
    String? foutmelding;

    if (!context.mounted) return;
    try {
      await toonDialoog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> opslaan() async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() {
                  bezigMetOpslaan = true;
                  foutmelding = null;
                });

                try {
                  if (nieuwAccount) {
                    final email = emailController.text.trim().toLowerCase();
                    await FirebaseFunctions.instance.httpsCallable('maakAccountAan').call({
                      'email': email,
                      'wachtwoord': wachtwoordController.text,
                      'rol': rol,
                      'clusters': rol == 'admin' ? <String>[] : geselecteerdeClusters.toList(),
                      'bedrijfId': bedrijfId,
                    });
                  } else {
                    final email = bestaandeEmail;
                    await FirebaseFunctions.instance.httpsCallable('bijwerkenAccount').call({
                      'email': email,
                      'rol': rol,
                      'clusters': rol == 'admin' ? <String>[] : geselecteerdeClusters.toList(),
                    });
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (fout) {
                  setDialogState(() {
                    bezigMetOpslaan = false;
                    foutmelding = _leesFoutmelding(fout);
                  });
                }
              }

              return AlertDialog(
                title: Text(nieuwAccount ? 'Account aanmaken' : 'Account bewerken'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: emailController,
                          enabled: nieuwAccount,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mailadres (waarmee diegene inlogt)'),
                          validator: (waarde) =>
                              (waarde == null || waarde.trim().isEmpty) ? 'Vul een e-mailadres in' : null,
                        ),
                        if (nieuwAccount) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: wachtwoordController,
                            obscureText: !wachtwoordZichtbaar,
                            decoration: InputDecoration(
                              labelText: 'Wachtwoord',
                              helperText: 'Minstens 6 tekens. Geef dit door aan de persoon.',
                              suffixIcon: IconButton(
                                icon: Icon(wachtwoordZichtbaar ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setDialogState(() => wachtwoordZichtbaar = !wachtwoordZichtbaar),
                              ),
                            ),
                            validator: (waarde) {
                              if (waarde == null || waarde.isEmpty) return 'Vul een wachtwoord in';
                              if (waarde.length < 6) return 'Minstens 6 tekens';
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: rol,
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
                          if (clusterOpties.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Nog geen clusters aangemaakt. Maak er eerst één aan via "Bedrijf & clusters beheren".',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                              ),
                            ),
                          ...clusterOpties.map((cluster) {
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
                        if (foutmelding != null) ...[
                          const SizedBox(height: 14),
                          Text(foutmelding!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: bezigMetOpslaan ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annuleren'),
                  ),
                  ElevatedButton(
                    onPressed: bezigMetOpslaan ? null : opslaan,
                    child: bezigMetOpslaan
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Opslaan'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailController.dispose();
      wachtwoordController.dispose();
    }
  }

  Future<void> _bevestigVerwijderen(BuildContext context, String email) async {
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account verwijderen?'),
        content: Text(
          'Weet je zeker dat je "$email" wilt verwijderen? De inlog wordt volledig verwijderd — dit account kan dan niet meer inloggen in de app.',
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            AppLoader(),
            SizedBox(width: 16),
            Expanded(child: Text('Bezig met verwijderen...')),
          ],
        ),
      ),
    );

    try {
      await FirebaseFunctions.instance.httpsCallable('verwijderAccount').call({'email': email});
      if (context.mounted) Navigator.pop(context); // sluit de laad-dialoog
    } catch (fout) {
      if (!context.mounted) return;
      Navigator.pop(context); // sluit de laad-dialoog
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Verwijderen mislukt'),
          content: Text(_leesFoutmelding(fout)),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sluiten'))],
        ),
      );
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
            color: _kOrange.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Nieuwe accounts maak je hieronder direct aan (inlog + rol + clusters in één keer) — dit hoeft niet meer apart via Firebase Console.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Clusters van dit bedrijf ophalen om ID's in de lijst hieronder
              // naar leesbare namen te vertalen (niet meer hardcoded).
              stream: FirebaseFirestore.instance
                  .collection('clusters')
                  .where('bedrijfId', isEqualTo: bedrijfId)
                  .snapshots(),
              builder: (context, clustersSnapshot) {
                final clusterNaamPerId = <String, String>{
                  for (final doc in clustersSnapshot.data?.docs ?? <QueryDocumentSnapshot>[])
                    doc.id: ((doc.data() as Map<String, dynamic>)['naam'] ?? doc.id).toString(),
                };
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('gebruikers')
                      .where('bedrijfId', isEqualTo: bedrijfId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // Zonder hasError-tak bleef dit scherm eeuwig laden als de
                    // opvraging faalde in plaats van uit te leggen waarom.
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Kan accounts niet laden:\n${snapshot.error}', textAlign: TextAlign.center),
                        ),
                      );
                    }
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
                        final clusterNamen = clusters.map((id) => clusterNaamPerId[id] ?? id).join(', ');
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
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
