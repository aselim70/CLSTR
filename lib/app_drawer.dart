import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'alle_depots_page.dart';
import 'personen_page.dart';
import 'rapportage_page.dart';
import 'afwijkingen_page.dart';
import 'overzicht_page.dart';
import 'gebruikers_beheer_page.dart';

// Zelfde blauw als de header-afbeelding op het Home-scherm, zodat de kop van
// het menu er hetzelfde uitziet.
const Color _kHeaderBlauwBoven = Color(0xFF002169);
const Color _kHeaderBlauwOnder = Color(0xFF023CBF);

class AppDrawer extends StatelessWidget {
  final String rol;
  final List<String> toegewezenClusters;
  const AppDrawer({super.key, required this.rol, required this.toegewezenClusters});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              alignment: Alignment.centerLeft,
              width: double.infinity,
              height: 110,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kHeaderBlauwBoven, _kHeaderBlauwOnder],
                ),
              ),
              child: Image.asset(
                'assets/images/clstr_logo.png',
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.list_alt_rounded),
                    title: const Text('Overzicht'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OverzichtPage(rol: rol, toegewezenClusters: toegewezenClusters),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.warehouse),
                    title: const Text('Depots'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AlleDepotsPage(rol: rol, toegewezenClusters: toegewezenClusters),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('Chauffeurs'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const PersonenPage()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.flag),
                    title: const Text('Afwijkingen'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AfwijkingenPage(rol: rol, toegewezenClusters: toegewezenClusters),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('Rapportage'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RapportagePage(rol: rol, toegewezenClusters: toegewezenClusters),
                        ),
                      );
                    },
                  ),
                  if (rol == 'admin') ...[
                    const Divider(height: 24),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Sub-accounts beheren'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const GebruikersBeheerPage()));
                      },
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red.shade400),
              title: Text('Uitloggen', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                FirebaseAuth.instance.signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}