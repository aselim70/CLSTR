import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Opstartscherm dat kort te zien is zodra de app opent: het CLSTR-logo
/// verschijnt terwijl een pakketbusje het scherm in "rijdt", op de blauwe
/// achtergrond. Puur decoratief - de eigenlijke inlog-check (StreamBuilder
/// in main.dart) draait gewoon op de achtergrond door, dit scherm zorgt er
/// alleen voor dat de opstart altijd rustig en bewust oogt in plaats van een
/// flits van een wit scherm.
class SplashScreen extends StatefulWidget {
  final Widget volgendeScherm;
  const SplashScreen({super.key, required this.volgendeScherm});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _busjeAnimatie;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoSchaal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    // Busje rijdt tijdens de eerste 65% van de animatie het scherm in.
    _busjeAnimatie = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
    );
    // Logo faded/schaalt pas in vanaf 35%, zodat het net overlapt met het
    // busje dat nog aan het "arriveren" is.
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _logoSchaal = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Minimaal ~2,2 seconden laten zien, ongeacht hoe snel het inloggen
    // achter de schermen al klaar is - zo oogt de opstart altijd bewust,
    // niet als een flits.
    Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (context, animation, secondaryAnimation) => widget.volgendeScherm,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breedte = MediaQuery.of(context).size.width;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBlauwGradient),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoOpacity,
                  child: ScaleTransition(
                    scale: _logoSchaal,
                    child: Image.asset('assets/images/clstr_logo.png', height: 90, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 36),
                AnimatedBuilder(
                  animation: _busjeAnimatie,
                  builder: (context, child) {
                    // Start ver links buiten beeld, rijdt naar het midden.
                    final dx = (_busjeAnimatie.value - 1) * (breedte * 0.4);
                    return Transform.translate(offset: Offset(dx, 0), child: child);
                  },
                  child: const Icon(Icons.local_shipping_rounded, size: 44, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
