import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'depot_list_page.dart';
import 'app_drawer.dart';
import 'afwijkingen_page.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class _ClusterInfo {
  final String id;
  final String naam;
  final IconData icon;
  const _ClusterInfo(this.id, this.naam, this.icon);
}

const List<_ClusterInfo> _clusters = [
  _ClusterInfo('cluster_1', 'Cluster 1', Icons.looks_one),
  _ClusterInfo('cluster_2', 'Cluster 2', Icons.looks_two),
  _ClusterInfo('cluster_3', 'Cluster 3', Icons.looks_3),
];

class HomePage extends StatelessWidget {
  final String rol;
  final List<String> toegewezenClusters;
  const HomePage({super.key, required this.rol, required this.toegewezenClusters});

  @override
  Widget build(BuildContext context) {
    final zichtbareClusters =
        rol == 'admin' ? _clusters : _clusters.where((c) => toegewezenClusters.contains(c.id)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      drawer: AppDrawer(rol: rol, toegewezenClusters: toegewezenClusters),
      body: Column(
        children: [
          // Header is nu puur de afbeelding zelf (geen aparte navy strook meer
          // erboven) — hamburger en bel zweven er gewoon bovenop.
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1200 / 575,
                child: Image.asset(
                  'assets/images/clstr_header.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Builder(
                          builder: (innerContext) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(innerContext).openDrawer(),
                          ),
                        ),
                        _AfwijkingenBel(rol: rol, toegewezenClusters: toegewezenClusters),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Stack(
                children: [
                  // Veel kleine, subtiele pakketjes-iconen verspreid over de lichte achtergrond
                  ..._achtergrondPakketjes,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kies een cluster',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _kNavy),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bekijk de depots en routes per cluster',
                          style: TextStyle(fontSize: 14, color: _kNavy.withOpacity(0.65)),
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: zichtbareClusters.isEmpty
                                  ? const _GeenClusterMelding()
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: zichtbareClusters
                                          .map(
                                            (cluster) => Padding(
                                              padding: const EdgeInsets.only(bottom: 18),
                                              child: _ClusterKaart(
                                                cluster: cluster,
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => DepotListPage(
                                                        clusterId: cluster.id,
                                                        clusterNaam: cluster.naam,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AfwijkingenBel extends StatefulWidget {
  final String rol;
  final List<String> toegewezenClusters;
  const _AfwijkingenBel({required this.rol, required this.toegewezenClusters});

  @override
  State<_AfwijkingenBel> createState() => _AfwijkingenBelState();
}

class _AfwijkingenBelState extends State<_AfwijkingenBel> {
  Set<String>? _toegestaneDepotNamen;
  bool _klaar = false;

  @override
  void initState() {
    super.initState();
    _laadToegestaneDepots();
  }

  Future<void> _laadToegestaneDepots() async {
    if (widget.rol == 'admin') {
      setState(() => _klaar = true);
      return;
    }
    if (widget.toegewezenClusters.isEmpty) {
      setState(() {
        _toegestaneDepotNamen = <String>{};
        _klaar = true;
      });
      return;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('depots')
        .where('clusterId', whereIn: widget.toegewezenClusters)
        .get();
    if (!mounted) return;
    setState(() {
      _toegestaneDepotNamen = snapshot.docs.map((d) => (d.data()['naam'] ?? '').toString()).toSet();
      _klaar = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const icoon = Icon(Icons.notifications_outlined);
    if (!_klaar) {
      return const IconButton(icon: icoon, onPressed: null);
    }
    final isAdmin = widget.rol == 'admin';
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance.collection('dagplanning').snapshots()
        : (widget.toegewezenClusters.isEmpty
            ? const Stream<QuerySnapshot>.empty()
            : FirebaseFirestore.instance
                .collection('dagplanning')
                .where('clusterId', whereIn: widget.toegewezenClusters)
                .snapshots());
    return StreamBuilder<QuerySnapshot>(
      stream: dagStream,
      builder: (context, snapshot) {
        int aantal = 0;
        if (snapshot.hasData) {
          aantal = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['eindtijd'] != null) return false;
            if (_toegestaneDepotNamen != null) {
              final depotNaam = (data['depotNaam'] ?? '').toString();
              if (!_toegestaneDepotNamen!.contains(depotNaam)) return false;
            }
            return true;
          }).length;
        }
        return IconButton(
          tooltip: 'Afwijkingen',
          icon: aantal > 0 ? Badge(label: Text('$aantal'), child: icoon) : icoon,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AfwijkingenPage(rol: widget.rol, toegewezenClusters: widget.toegewezenClusters),
              ),
            );
          },
        );
      },
    );
  }
}

class _PakketjeIcoon {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double opacity;
  final double hoek;
  final bool navy;
  const _PakketjeIcoon({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.opacity,
    required this.hoek,
    required this.navy,
  });
}

const List<_PakketjeIcoon> _pakketjes = [
  // Op de lichte achtergrond onder de header-afbeelding (navy pakketjes)
  _PakketjeIcoon(top: 16, right: 24, size: 24, opacity: 0.07, hoek: -0.2, navy: true),
  _PakketjeIcoon(top: 64, left: -10, size: 30, opacity: 0.06, hoek: 0.25, navy: true),
  _PakketjeIcoon(bottom: 180, right: -12, size: 32, opacity: 0.055, hoek: -0.3, navy: true),
  _PakketjeIcoon(bottom: 110, left: 24, size: 20, opacity: 0.06, hoek: 0.35, navy: true),
  _PakketjeIcoon(bottom: 40, right: 60, size: 26, opacity: 0.06, hoek: -0.15, navy: true),
  _PakketjeIcoon(bottom: 250, left: 120, size: 16, opacity: 0.05, hoek: 0.2, navy: true),
  _PakketjeIcoon(bottom: 20, left: -8, size: 22, opacity: 0.055, hoek: -0.4, navy: true),
];

final List<Widget> _achtergrondPakketjes = _pakketjes
    .map(
      (p) => Positioned(
        top: p.top,
        bottom: p.bottom,
        left: p.left,
        right: p.right,
        child: Transform.rotate(
          angle: p.hoek,
          child: Icon(
            Icons.inventory_2_rounded,
            size: p.size,
            color: (p.navy ? _kNavy : Colors.white).withOpacity(p.opacity),
          ),
        ),
      ),
    )
    .toList();

class _GeenClusterMelding extends StatelessWidget {
  const _GeenClusterMelding();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Je hebt nog geen cluster toegewezen gekregen.\nNeem contact op met de beheerder.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ClusterKaart extends StatelessWidget {
  final _ClusterInfo cluster;
  final VoidCallback onTap;

  const _ClusterKaart({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(cluster.icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cluster.naam,
                      style: const TextStyle(
                        color: _kNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Bekijk depots en routes',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kOrange.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_right, color: _kOrange, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}