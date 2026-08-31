import 'package:flutter/material.dart';

/// Het blauw uit de header-afbeelding / het hamburgermenu — dit is nu de
/// enige plek waar dit kleurverloop gedefinieerd staat, zodat alle schermen
/// er precies hetzelfde uitzien.
const Color kBlauwBoven = Color(0xFF002169);
const Color kBlauwOnder = Color(0xFF023CBF);

const LinearGradient kBlauwGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kBlauwBoven, kBlauwOnder],
);

/// Een AppBar met hetzelfde blauwe kleurverloop als de header-afbeelding,
/// in plaats van een platte kleur. Overal in de app gebruiken in plaats van
/// de gewone Flutter `AppBar`, zodat elk scherm er hetzelfde uitziet.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;

  const GradientAppBar({super.key, required this.title, this.actions, this.leading});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: kBlauwGradient)),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Animatie-vervanger voor de standaard (grijze) CircularProgressIndicator:
/// een klein bestelbusje-icoontje dat zachtjes heen-en-weer "rijdt" terwijl
/// er geladen wordt, in het CLSTR-blauw. Overal gebruiken in plaats van de
/// kale CircularProgressIndicator, voor een consistente merkbeleving.
class AppLoader extends StatefulWidget {
  final double size;
  final Color color;
  const AppLoader({super.key, this.size = 42, this.color = kBlauwBoven});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.6,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final curve = Curves.easeInOut.transform(_controller.value);
          final dx = (curve - 0.5) * widget.size * 0.7;
          return Align(
            child: Transform.translate(offset: Offset(dx, 0), child: child),
          );
        },
        child: Icon(Icons.local_shipping_rounded, size: widget.size, color: widget.color),
      ),
    );
  }
}

/// Een volle-breedte knop met hetzelfde blauwe kleurverloop, voor de
/// belangrijkste acties (bijv. "Opslaan", "Printen / PDF exporteren",
/// "Inloggen"). De kleine knoppen in dialoogvensters (Toevoegen/Annuleren)
/// blijven de gewone, platte knop uit het thema gebruiken.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const GradientButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final actief = onPressed != null;
    return Opacity(
      opacity: actief ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(gradient: kBlauwGradient, borderRadius: BorderRadius.circular(12)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
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
