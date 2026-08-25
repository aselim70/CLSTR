import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_detail_page.dart';
import 'app_theme.dart';

class AlleRoutesPage extends StatelessWidget {
  const AlleRoutesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: const Text('Routes')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('routes').orderBy('naam').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: AppLoader());
          final routes = snapshot.data!.docs;
          if (routes.isEmpty) {
            return const Center(child: Text('Nog geen routes toegevoegd.'));
          }
          return ListView.separated(
            itemCount: routes.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = routes[index].data() as Map<String, dynamic>;
              final naam = data['naam'] ?? 'Onbekend';
              final depotNaam = data['depotNaam'] ?? '';
              final clusterId = data['clusterId']?.toString();
              return ListTile(
                title: Text(naam),
                subtitle: Text(depotNaam),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RouteDetailPage(routeNaam: naam, depotNaam: depotNaam, clusterId: clusterId),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}