import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Korte animatie die één keer getoond wordt vlak ná het inloggen: een paar
/// pakketjes "springen" in het busje, en het busje rijdt daarna weg. Puur
/// decoratief - zodra de animatie klaar is, wordt onKlaar() aangeroepen en
/// gaat de app gewoon verder naar de hoofdpagina.
class VertrekAnimatiePage extends StatefulWidget {
  final VoidCallback onKlaar;
  const VertrekAnimatiePage({super.key, required this.onKlaar});

  @override
  State<VertrekAnimatiePage> createState() => _VertrekAnimatiePageState();
}

class _VertrekAnimatiePageState extends State<VertrekAnimatiePage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pakketjesVoortgang;
  late final Animation<double> _busjeSchaal;
  late final Animation<double> _busjeSchuift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

    // Eerste helft: pakketjes "springen" in het busje.
    _pakketjesVoortgang = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );

    // Klein "hupje" van het busje vlak voor het wegrijdt.
    _busjeSchaal = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1).chain(CurveTween(curve: Curves.easeOut)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
    ]).animate(_controller);

    // Tweede helft: het busje rijdt naar rechts weg.
    _busjeSchuift = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onKlaar();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schermbreedte = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBlauwGradient),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final busX = _busjeSchuift.value * (schermbreedte * 0.7 + 140);
                final pakketjesZichtbaar = _pakketjesVoortgang.value;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 90,
                      width: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          if (pakketjesZichtbaar > 0 && pakketjesZichtbaar < 1)
                            ...List.generate(3, (i) {
                              final vertraging = i * 0.18;
                              final voortgang = ((pakketjesZichtbaar - vertraging) / (1 - vertraging)).clamp(0.0, 1.0);
                              if (voortgang <= 0) return const SizedBox.shrink();
                              return Positioned(
                                bottom: 8 + (1 - voortgang) * 30,
                                left: 24.0 + i * 24,
                                child: Opacity(
                                  opacity: voortgang,
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 16,
                                  ),
                                ),
                              );
                            }),
                          Transform.translate(
                            offset: Offset(busX, 0),
                            child: Transform.scale(
                              scale: _busjeSchaal.value,
                              child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 64),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _controller.value < 0.5 ? 'Busje wordt geladen...' : 'Onderweg!',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
