import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'depot_list_page.dart';
import 'app_drawer.dart';
import 'afwijkingen_page.dart';
import 'app_theme.dart';
import 'app_helpers.dart';

const Color _kNavy = Color(0xFF002169);
const Color _kOrange = Color(0xFFFF8500);

class _ClusterInfo {
  final String id;
  final String naam;
  final IconData icon;
  const _ClusterInfo(this.id, this.naam, this.icon);
}

// Vaste iconen-rotatie voor clusters - er zit geen icoon-veld in Firestore
// (clusters zijn nu dynamisch, per bedrijf aan te maken), dus hier gewoon op
// volgorde een icoon toekennen. Na de eerste drie (met cijfer-iconen) komt er
// gewoon een neutraal gebouw-icoon voor elk volgend cluster.
IconData _clusterIcoonVoorIndex(int index) {
  const eersteDrie = [Icons.looks_one, Icons.looks_two, Icons.looks_3];
  return index < eersteDrie.length ? eersteDrie[index] : Icons.apartment_rounded;
}

class HomePage extends StatefulWidget {
  final String rol;
  final String bedrijfId;
  final List<String> toegewezenClusters;
  const HomePage({super.key, required this.rol, required this.bedrijfId, required this.toegewezenClusters});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // Eén controller die eindeloos van 0 naar 1 loopt voor het zachte
  // op-en-neer zweven van de pakketjes-iconen (elk icoon krijgt zijn eigen
  // fase-verschil zodat ze niet allemaal gelijk bewegen).
  late final AnimationController _zweefController;
  // Aparte controller die continu doorloopt voor het busje dat rustig van
  // links naar rechts over de achtergrond "rijdt".
  late final AnimationController _busjeController;

  @override
  void initState() {
    super.initState();
    _zweefController = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _busjeController = AnimationController(vsync: this, duration: const Duration(seconds: 11))..repeat();
  }

  @override
  void dispose() {
    _zweefController.dispose();
    _busjeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      drawer: AppDrawer(rol: widget.rol, bedrijfId: widget.bedrijfId, toegewezenClusters: widget.toegewezenClusters),
      body: Column(
        children: [
          // Header is nu een zelfgemaakte geanimeerde achtergrond (geen losse
          // afbeelding meer) — hamburger en bel zweven er gewoon bovenop.
          Stack(
            children: [
              const AspectRatio(aspectRatio: 1200 / 575, child: _ClstrHeaderAchtergrond()),
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
                        _AfwijkingenBel(
                          rol: widget.rol,
                          bedrijfId: widget.bedrijfId,
                          toegewezenClusters: widget.toegewezenClusters,
                        ),
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
                  // Zachtjes zwevende pakketjes/busje-iconen verspreid over de
                  // lichte achtergrond, plus één busje dat continu van links
                  // naar rechts rijdt — allemaal heel subtiel (lage
                  // opacity), puur voor een beetje leven op deze pagina.
                  ..._pakketjes.asMap().entries.map(
                    (entry) => _ZwevendPakketje(
                      animatie: _zweefController,
                      pakketje: entry.value,
                      faseVerschil: entry.key * 0.85,
                    ),
                  ),
                  _RijdendBusje(animatie: _busjeController),
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
                          style: TextStyle(fontSize: 14, color: _kNavy.withValues(alpha: 0.65)),
                        ),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('clusters')
                                .where('bedrijfId', isEqualTo: widget.bedrijfId)
                                .orderBy('naam')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Kan clusters niet laden:\n${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                );
                              }
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: AppLoader());
                              }
                              final alleClusters = (snapshot.data?.docs ?? []).asMap().entries.map((entry) {
                                final data = entry.value.data() as Map<String, dynamic>;
                                return _ClusterInfo(
                                  entry.value.id,
                                  data['naam']?.toString() ?? 'Onbekend cluster',
                                  _clusterIcoonVoorIndex(entry.key),
                                );
                              }).toList();
                              final zichtbareClusters = widget.rol == 'admin'
                                  ? alleClusters
                                  : alleClusters.where((c) => widget.toegewezenClusters.contains(c.id)).toList();

                              return Center(
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
                                                            bedrijfId: widget.bedrijfId,
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
                              );
                            },
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
  final String bedrijfId;
  final List<String> toegewezenClusters;
  const _AfwijkingenBel({required this.rol, required this.bedrijfId, required this.toegewezenClusters});

  @override
  State<_AfwijkingenBel> createState() => _AfwijkingenBelState();
}

class _AfwijkingenBelState extends State<_AfwijkingenBel> {
  DepotToegang? _toegang;

  @override
  void initState() {
    super.initState();
    _laadToegestaneDepots();
  }

  Future<void> _laadToegestaneDepots() async {
    final toegang = await laadToegestaneDepotNamen(
      rol: widget.rol,
      bedrijfId: widget.bedrijfId,
      toegewezenClusters: widget.toegewezenClusters,
    );
    if (!mounted) return;
    setState(() => _toegang = toegang);
  }

  @override
  Widget build(BuildContext context) {
    const icoon = Icon(Icons.notifications_outlined);
    final toegang = _toegang;
    // Nog aan het laden, of het ophalen van de depots is mislukt: de bel
    // blijft dan gewoon staan zonder telling, in plaats van een foutmelding
    // over de header te gooien. De Afwijkingen-pagina zelf legt wél uit wat
    // er misging.
    if (toegang == null) {
      return const IconButton(icon: icoon, onPressed: null);
    }
    final isAdmin = widget.rol == 'admin';
    final Stream<QuerySnapshot> dagStream = isAdmin
        ? FirebaseFirestore.instance
              .collection('dagplanning')
              .where('bedrijfId', isEqualTo: widget.bedrijfId)
              .snapshots()
        : (widget.toegewezenClusters.isEmpty
              ? const Stream<QuerySnapshot>.empty()
              : FirebaseFirestore.instance
                    .collection('dagplanning')
                    .where('bedrijfId', isEqualTo: widget.bedrijfId)
                    .where('clusterId', whereIn: beperkVoorWhereIn(widget.toegewezenClusters))
                    .snapshots());
    return StreamBuilder<QuerySnapshot>(
      stream: dagStream,
      builder: (context, snapshot) {
        int aantal = 0;
        if (snapshot.hasData && toegang.isGelukt) {
          aantal = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['eindtijd'] != null) return false;
            return toegang.magZien((data['depotNaam'] ?? '').toString());
          }).length;
        }
        return IconButton(
          tooltip: 'Afwijkingen',
          icon: aantal > 0 ? Badge(label: Text('$aantal'), child: icoon) : icoon,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AfwijkingenPage(
                  rol: widget.rol,
                  bedrijfId: widget.bedrijfId,
                  toegewezenClusters: widget.toegewezenClusters,
                ),
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
  final IconData icon;
  const _PakketjeIcoon({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.opacity,
    required this.hoek,
    required this.navy,
    this.icon = Icons.inventory_2_rounded,
  });
}

const List<_PakketjeIcoon> _pakketjes = [
  // Op de lichte achtergrond onder de header-afbeelding, verspreid over de
  // hele hoogte van het scherm (niet alleen bovenin/onderin) zodat het echt
  // als een paginawijde achtergrond aanvoelt.
  _PakketjeIcoon(top: 16, right: 24, size: 24, opacity: 0.07, hoek: -0.2, navy: true),
  _PakketjeIcoon(top: 64, left: -10, size: 30, opacity: 0.06, hoek: 0.25, navy: true),
  _PakketjeIcoon(
    top: 150,
    right: 40,
    size: 18,
    opacity: 0.05,
    hoek: 0.4,
    navy: true,
    icon: Icons.local_shipping_outlined,
  ),
  _PakketjeIcoon(top: 220, left: 8, size: 22, opacity: 0.05, hoek: -0.25, navy: true),
  _PakketjeIcoon(top: 300, right: -6, size: 26, opacity: 0.05, hoek: 0.15, navy: true),
  _PakketjeIcoon(bottom: 320, left: 140, size: 18, opacity: 0.05, hoek: -0.35, navy: true),
  _PakketjeIcoon(
    bottom: 250,
    right: 16,
    size: 20,
    opacity: 0.055,
    hoek: 0.3,
    navy: true,
    icon: Icons.local_shipping_outlined,
  ),
  _PakketjeIcoon(bottom: 180, right: -12, size: 32, opacity: 0.055, hoek: -0.3, navy: true),
  _PakketjeIcoon(bottom: 110, left: 24, size: 20, opacity: 0.06, hoek: 0.35, navy: true),
  _PakketjeIcoon(bottom: 40, right: 60, size: 26, opacity: 0.06, hoek: -0.15, navy: true),
  _PakketjeIcoon(bottom: 250, left: 120, size: 16, opacity: 0.05, hoek: 0.2, navy: true),
  _PakketjeIcoon(bottom: 20, left: -8, size: 22, opacity: 0.055, hoek: -0.4, navy: true),
];

/// Eén pakketje-icoon dat continu zachtjes op en neer zweeft. Gebruikt
/// sin() over een controller die eindeloos van 0 naar 1 loopt, zodat de
/// beweging soepel doorloopt zonder sprongetje bij het herhalen. Elk icoon
/// heeft een eigen faseVerschil zodat ze niet synchroon bewegen.
class _ZwevendPakketje extends StatelessWidget {
  final Animation<double> animatie;
  final _PakketjeIcoon pakketje;
  final double faseVerschil;

  const _ZwevendPakketje({required this.animatie, required this.pakketje, required this.faseVerschil});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animatie,
      builder: (context, child) {
        final zweefOffset = math.sin((animatie.value * 2 * math.pi) + faseVerschil) * 7;
        return Positioned(
          top: pakketje.top != null ? pakketje.top! + zweefOffset : null,
          bottom: pakketje.bottom != null ? pakketje.bottom! - zweefOffset : null,
          left: pakketje.left,
          right: pakketje.right,
          child: Transform.rotate(
            angle: pakketje.hoek,
            child: Icon(
              pakketje.icon,
              size: pakketje.size,
              color: (pakketje.navy ? _kNavy : Colors.white).withValues(alpha: pakketje.opacity),
            ),
          ),
        );
      },
    );
  }
}

/// Een busje dat heel subtiel en continu van links naar rechts over de
/// achtergrond "rijdt" (en daarna gewoon weer opnieuw begint), voor wat
/// leven op de pagina zonder dat het afleidt van de clusters-lijst erboven.
class _RijdendBusje extends StatelessWidget {
  final Animation<double> animatie;
  const _RijdendBusje({required this.animatie});

  @override
  Widget build(BuildContext context) {
    // Let op: bewust GEEN LayoutBuilder hier - die heeft zelf een render
    // object en zou dan tussen de Stack en Positioned in komen te zitten,
    // wat de "Incorrect use of ParentDataWidget"-fout veroorzaakt. MediaQuery
    // is een gewone InheritedWidget-lookup en breekt die keten niet.
    final breedte = MediaQuery.of(context).size.width;
    return AnimatedBuilder(
      animation: animatie,
      builder: (context, child) {
        final x = -50 + animatie.value * (breedte + 100);
        return Positioned(
          top: 118,
          left: x,
          child: Opacity(opacity: 0.06, child: Icon(Icons.local_shipping_rounded, size: 30, color: _kNavy)),
        );
      },
    );
  }
}

/// Vervangt de vroegere statische header-foto: een zelfgemaakte, geanimeerde
/// achtergrond in het CLSTR-blauw, met een ronde onderrand, subtiele
/// diagonale strepen, een paar zwevende pakketjes-iconen en het logo met een
/// zachtjes heen-en-weer "rijdend" bestelbusje erboven.
class _ClstrHeaderAchtergrond extends StatefulWidget {
  const _ClstrHeaderAchtergrond();

  @override
  State<_ClstrHeaderAchtergrond> createState() => _ClstrHeaderAchtergrondState();
}

class _ClstrHeaderAchtergrondState extends State<_ClstrHeaderAchtergrond> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _HeaderBoogClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: kBlauwGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _DiagonaleStrepenPainter()),
            ..._headerIconen,
            Align(
              alignment: const Alignment(0, -0.1),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final curve = Curves.easeInOut.transform(_controller.value);
                  final dx = (curve - 0.5) * 24;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(dx, 0),
                        child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 46),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'CLSTR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 5,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ronde onderrand voor de header, zodat het blauwe vlak niet gewoon
/// rechthoekig stopt maar in een brede boog naar beneden "bolt" - dezelfde
/// vormtaal als de vorige header-afbeelding.
class _HeaderBoogClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.78);
    path.quadraticBezierTo(size.width * 0.5, size.height * 1.1, size.width, size.height * 0.78);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Heel subtiele diagonale strepen over de header, voor wat textuur in het
/// blauwe vlak in plaats van een vlakke kleur.
class _DiagonaleStrepenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 22;
    const stap = 48.0;
    for (double x = -size.height; x < size.width; x += stap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Een handvol vaste, halfdoorzichtige pakketjes/busjes-iconen als decoratie
/// bovenop de header-achtergrond.
final List<Widget> _headerIconen = [
  Positioned(
    top: 14,
    left: 22,
    child: Icon(Icons.inventory_2_rounded, size: 20, color: Colors.white.withValues(alpha: 0.16)),
  ),
  Positioned(
    top: 26,
    right: 40,
    child: Transform.rotate(
      angle: 0.3,
      child: Icon(Icons.inventory_2_rounded, size: 16, color: Colors.white.withValues(alpha: 0.14)),
    ),
  ),
  Positioned(
    bottom: 50,
    left: 46,
    child: Icon(Icons.inventory_2_rounded, size: 18, color: Colors.white.withValues(alpha: 0.12)),
  ),
  Positioned(
    bottom: 34,
    right: 64,
    child: Transform.rotate(
      angle: -0.25,
      child: Icon(Icons.inventory_2_rounded, size: 22, color: Colors.white.withValues(alpha: 0.14)),
    ),
  ),
  Positioned(
    top: 58,
    right: 96,
    child: Icon(Icons.local_shipping_outlined, size: 16, color: Colors.white.withValues(alpha: 0.1)),
  ),
];

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
      shadowColor: Colors.black.withValues(alpha: 0.15),
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
                decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(18)),
                child: Icon(cluster.icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cluster.naam,
                      style: const TextStyle(color: _kNavy, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text('Bekijk depots en routes', style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right, color: _kOrange, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
