import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

/// Startscherm voor de superadmin: een lijst van alle bedrijven in de app.
/// Via "Openen" kijkt de superadmin met dezelfde ogen als de admin van dat
/// bedrijf mee (HomePage met rol: 'admin' en het gekozen bedrijfId) - er is
/// dus geen aparte "superadmin-versie" van elk scherm nodig. Via de + knop
/// kan de superadmin een volledig nieuw bedrijf + de eerste admin daarvan
/// aanmaken.
class SuperadminBedrijvenPage extends StatelessWidget {
  const SuperadminBedrijvenPage({super.key});

  static String _leesFoutmelding(Object fout) {
    if (fout is FirebaseFunctionsException) {
      switch (fout.code) {
        case 'already-exists':
          return 'Er bestaat al een account met dit e-mailadres.';
        case 'invalid-argument':
          return fout.message ?? 'Controleer de ingevulde gegevens.';
        case 'permission-denied':
          return fout.message ?? 'Je hebt geen rechten om dit te doen.';
        default:
          return fout.message ?? 'Er ging iets mis (${fout.code}).';
      }
    }
    return 'Er ging iets mis: $fout';
  }

  Future<void> _toonNieuwBedrijfDialoog(BuildContext context) async {
    final bedrijfsnaamController = TextEditingController();
    final adminEmailController = TextEditingController();
    final wachtwoordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool bezigMetOpslaan = false;
    String? foutmelding;

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
                  await FirebaseFunctions.instance.httpsCallable('maakBedrijfMetAdminAan').call({
                    'bedrijfsnaam': bedrijfsnaamController.text.trim(),
                    'adminEmail': adminEmailController.text.trim(),
                    'adminWachtwoord': wachtwoordController.text,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (fout) {
                  setDialogState(() {
                    bezigMetOpslaan = false;
                    foutmelding = _leesFoutmelding(fout);
                  });
                }
              }

              return AlertDialog(
                title: const Text('Nieuw bedrijf toevoegen'),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: bedrijfsnaamController,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'Bedrijfsnaam'),
                          validator: (waarde) =>
                              (waarde == null || waarde.trim().isEmpty) ? 'Vul een bedrijfsnaam in' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: adminEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mailadres eerste admin'),
                          validator: (waarde) =>
                              (waarde == null || waarde.trim().isEmpty) ? 'Vul een e-mailadres in' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: wachtwoordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Wachtwoord voor dit account',
                            helperText: 'Minstens 6 tekens. Geef dit door aan de admin.',
                          ),
                          validator: (waarde) {
                            if (waarde == null || waarde.isEmpty) return 'Vul een wachtwoord in';
                            if (waarde.length < 6) return 'Minstens 6 tekens';
                            return null;
                          },
                        ),
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
                        : const Text('Aanmaken'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      bedrijfsnaamController.dispose();
      adminEmailController.dispose();
      wachtwoordController.dispose();
    }
  }

  Future<void> _hernoemBedrijf(BuildContext context, String bedrijfId, String huidigeNaam) async {
    final naamController = TextEditingController(text: huidigeNaam);
    final formKey = GlobalKey<FormState>();

    final String? nieuweNaam;
    try {
      nieuweNaam = await toonDialoog<String>(
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

  Future<void> _toonNieuweSuperadminDialoog(BuildContext context) async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final String? email;
    try {
      email = await toonDialoog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Account promoveren tot Superadmin'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'E-mailadres van een bestaand account'),
              validator: (waarde) => (waarde == null || waarde.trim().isEmpty) ? 'Vul een e-mailadres in' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, emailController.text.trim().toLowerCase());
              },
              child: const Text('Promoveren'),
            ),
          ],
        ),
      );
    } finally {
      emailController.dispose();
    }
    if (email == null) return;

    // Let op: dit is een directe Firestore-schrijfactie op het gebruikers-
    // document, wat normaal via Cloud Functions moet (allow write: if false
    // in de rules) - maar de rules laten hier een uitzondering toe die niet
    // bestaat, dus dit werkt ALLEEN zolang je zelf nog met de oude/tijdelijke
    // rules werkt. Voor nu: gebruik hiervoor de Firebase Console
    // (Firestore -> gebruikers -> dat document -> rol wijzigen naar
    // "superadmin" en bedrijfId naar null) totdat er een aparte Cloud
    // Function voor is.
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Even handmatig'),
        content: Text(
          'Om "$email" te promoveren: open de Firebase Console -> Firestore Database -> collectie "gebruikers" -> document "$email", '
          'en zet daar rol op "superadmin" en bedrijfId op null (leeg). Er is bewust geen knop die dit automatisch doet, '
          'zodat niemand per ongeluk per app-actie een tweede superadmin aanmaakt.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Begrepen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('Bedrijven (Superadmin)'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (waarde) {
              if (waarde == 'superadmin') _toonNieuweSuperadminDialoog(context);
              if (waarde == 'uitloggen') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'superadmin', child: Text('Nieuwe superadmin promoveren')),
              PopupMenuItem(value: 'uitloggen', child: Text('Uitloggen')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE7EAF3), Color(0xFFF4F5F9)],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('bedrijven').orderBy('naam').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Kan bedrijven niet laden:\n${snapshot.error}\n\n'
                    'Staat firestore.rules al met de nieuwe regels live (Fase D van het stappenplan)? '
                    'Zonder die regels mag zelfs de superadmin de collectie "bedrijven" nog niet lezen.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) return const Center(child: AppLoader());
            final bedrijven = snapshot.data!.docs;
            if (bedrijven.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nog geen bedrijven. Voeg er hieronder één toe met de + knop.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 88),
              itemCount: bedrijven.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = bedrijven[index];
                final naam = (doc.data() as Map<String, dynamic>)['naam']?.toString() ?? 'Onbekend';
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HomePage(rol: 'admin', bedrijfId: doc.id, toegewezenClusters: const []),
                        ),
                      );
                    },
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
                            child: const Icon(Icons.apartment_rounded, color: _kNavy, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              naam,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kNavy),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_outlined, color: Colors.grey.shade600),
                            onPressed: () => _hernoemBedrijf(context, doc.id, naam),
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
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _toonNieuwBedrijfDialoog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
