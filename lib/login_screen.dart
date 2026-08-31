import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _bezigMetInloggen = false;
  String? _foutmelding;

  // Zelfde soort zwevende-pakketjes-animatie als op de homepage, plus een
  // busje dat continu over het scherm rijdt - dit vervangt de vroegere
  // foto-achtergrond, dus zonder dat er een afbeelding geüpload hoeft te
  // worden.
  late final AnimationController _zweefController;
  late final AnimationController _busjeController;

  @override
  void initState() {
    super.initState();
    _zweefController = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _busjeController = AnimationController(vsync: this, duration: const Duration(seconds: 13))..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _zweefController.dispose();
    _busjeController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Het wachtwoord bewust NIET trimmen: spaties aan begin of eind zijn
    // geldige tekens in een wachtwoord, en ze er stilletjes afhalen betekent
    // dat zo'n wachtwoord nooit werkt zonder dat iemand begrijpt waarom.
    final email = _emailController.text.trim();
    final wachtwoord = _passwordController.text;

    if (email.isEmpty || wachtwoord.isEmpty) {
      setState(() => _foutmelding = 'Vul je e-mailadres en wachtwoord in.');
      return;
    }

    setState(() {
      _bezigMetInloggen = true;
      _foutmelding = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: wachtwoord);
      // Bij succes stuurt main.dart je automatisch door (met een korte
      // vertrek-animatie) naar de hoofdpagina. Dit scherm wordt dan meteen
      // afgebroken - vandaar de mounted-controle hieronder: zonder die
      // controle riep het oude `finally`-blok setState() aan op een al
      // verwijderd scherm, wat een uitzondering opleverde.
      if (!mounted) return;
      setState(() => _bezigMetInloggen = false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _bezigMetInloggen = false;
        _foutmelding = _leesAuthFout(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bezigMetInloggen = false;
        _foutmelding = 'Onverwachte fout bij inloggen: $e';
      });
    }
  }

  /// Firebase-foutcodes omzetten naar begrijpelijke tekst. De ruwe melding
  /// ("Inloggen mislukt (invalid-credential): The supplied auth credential
  /// is incorrect...") zei een chauffeur niets.
  String _leesAuthFout(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'E-mailadres of wachtwoord klopt niet.';
      case 'invalid-email':
        return 'Dit is geen geldig e-mailadres.';
      case 'user-disabled':
        return 'Dit account is geblokkeerd. Neem contact op met de beheerder.';
      case 'too-many-requests':
        return 'Te vaak achter elkaar geprobeerd. Wacht even en probeer het opnieuw.';
      case 'network-request-failed':
        return 'Geen verbinding. Controleer je internet en probeer het opnieuw.';
      default:
        return 'Inloggen mislukt (${e.code}): ${e.message ?? 'geen verdere details'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final schermbreedte = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(decoration: const BoxDecoration(gradient: kBlauwGradient)),
          CustomPaint(painter: _LoginStrepenSchilder()),
          ..._loginPakketjes.asMap().entries.map(
            (entry) =>
                _ZwevendLoginPakketje(animatie: _zweefController, pakketje: entry.value, faseVerschil: entry.key * 0.8),
          ),
          AnimatedBuilder(
            animation: _busjeController,
            builder: (context, child) {
              final x = -60 + _busjeController.value * (schermbreedte + 120);
              return Positioned(
                top: 108,
                left: x,
                child: Opacity(
                  opacity: 0.08,
                  child: const Icon(Icons.local_shipping_rounded, size: 32, color: Colors.white),
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 50),
                    const SizedBox(height: 10),
                    const Text(
                      'CLSTR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 5,
                      ),
                    ),
                    const SizedBox(height: 44),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'E-mail',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      // Enter op het toetsenbord logt nu ook in, in plaats van
                      // alleen de knop.
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_bezigMetInloggen) _login();
                      },
                      decoration: InputDecoration(
                        labelText: 'Wachtwoord',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_foutmelding != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _foutmelding!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    _InlogKnop(
                      onPressed: _bezigMetInloggen ? null : _login,
                      child: _bezigMetInloggen
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Inloggen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eigen inlog-knop in het CLSTR-oranje in plaats van de gewone navy
/// GradientButton - die navy-knop viel bijna weg tegen de nieuwe blauwe
/// achtergrond. Oranje is verder ook al de vaste accentkleur in de app
/// (bijv. de cluster-kaarten), dus dit knoopt daarbij aan.
class _InlogKnop extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const _InlogKnop({required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final actief = onPressed != null;
    return Opacity(
      opacity: actief ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFF8500), Color(0xFFFFA640)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 5)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginPakketjeIcoon {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double opacity;
  final double hoek;
  final IconData icon;
  const _LoginPakketjeIcoon({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.opacity,
    required this.hoek,
    this.icon = Icons.inventory_2_rounded,
  });
}

const List<_LoginPakketjeIcoon> _loginPakketjes = [
  _LoginPakketjeIcoon(top: 60, left: 24, size: 26, opacity: 0.12, hoek: -0.2),
  _LoginPakketjeIcoon(top: 40, right: 30, size: 20, opacity: 0.1, hoek: 0.3),
  _LoginPakketjeIcoon(top: 160, right: -10, size: 30, opacity: 0.09, hoek: -0.25),
  _LoginPakketjeIcoon(top: 220, left: -8, size: 22, opacity: 0.1, hoek: 0.35, icon: Icons.local_shipping_outlined),
  _LoginPakketjeIcoon(bottom: 260, left: 30, size: 18, opacity: 0.1, hoek: 0.2),
  _LoginPakketjeIcoon(bottom: 200, right: 26, size: 24, opacity: 0.09, hoek: -0.3),
  _LoginPakketjeIcoon(bottom: 120, left: 60, size: 16, opacity: 0.11, hoek: 0.15, icon: Icons.local_shipping_outlined),
  _LoginPakketjeIcoon(bottom: 70, right: 50, size: 26, opacity: 0.1, hoek: -0.2),
  _LoginPakketjeIcoon(bottom: 30, left: 20, size: 20, opacity: 0.09, hoek: 0.25),
];

/// Zelfde idee als de zwevende pakketjes op de homepage: continu zachtjes
/// op-en-neer bewegen, elk met een eigen faseverschil.
class _ZwevendLoginPakketje extends StatelessWidget {
  final Animation<double> animatie;
  final _LoginPakketjeIcoon pakketje;
  final double faseVerschil;

  const _ZwevendLoginPakketje({required this.animatie, required this.pakketje, required this.faseVerschil});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animatie,
      builder: (context, child) {
        final zweefOffset = math.sin((animatie.value * 2 * math.pi) + faseVerschil) * 6;
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
              color: Colors.white.withValues(alpha: pakketje.opacity),
            ),
          ),
        );
      },
    );
  }
}

/// Heel subtiele diagonale strepen over de volledige inlog-achtergrond,
/// dezelfde textuur als op de homepage-header.
class _LoginStrepenSchilder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 24;
    const stap = 52.0;
    for (double x = -size.height; x < size.width; x += stap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
