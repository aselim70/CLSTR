import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_list_page.dart';
import 'app_theme.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class DepotListPage extends StatelessWidget {
  final String bedrijfId;
  final String clusterId;
  final String clusterNaam;

  const DepotListPage({super.key, required this.bedrijfId, required this.clusterId, required this.clusterNaam});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: Text(clusterNaam)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE7EAF3), Color(0xFFF4F5F9)],
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('depots')
              .where('bedrijfId', isEqualTo: bedrijfId)
              .where('clusterId', isEqualTo: clusterId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Fout: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: AppLoader());
            }
            final depots = snapshot.data!.docs;
            if (depots.isEmpty) {
              return const Center(child: Text('Nog geen depots in dit cluster.'));
            }

            final gesorteerd = depots.toList()
              ..sort((a, b) {
                final naamA = (a.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                final naamB = (b.data() as Map<String, dynamic>)['naam']?.toString() ?? '';
                return naamA.compareTo(naamB);
              });

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              itemCount: gesorteerd.length,
              itemBuilder: (context, index) {
                final data = gesorteerd[index].data() as Map<String, dynamic>;
                final naam = data['naam']?.toString() ?? 'Onbekend';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DepotKaart(
                    naam: naam,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              RouteListPage(depotNaam: naam, clusterId: clusterId, bedrijfId: bedrijfId),
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
