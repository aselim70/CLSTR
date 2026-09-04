import 'dart:async';
import 'home_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'app_theme.dart';
import 'splash_screen.dart';
import 'versie_check.dart';
import 'vertrek_animatie_page.dart';
import 'superadmin_bedrijven_page.dart';

const Color kNavy = Color(0xFF002169);
const Color kOrange = Color(0xFFFF8500);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Bewust hier gestart en NIET afgewacht: de opvraging loopt zo parallel aan
  // de splash-animatie, die toch al ~2,2 seconden duurt. Het splash-scherm
  // wacht verderop alsnog op deze Future voordat het doorschakelt, dus de
  // controle kost in de praktijk geen extra opstarttijd.
  final versieControle = controleerAppVersie();

  runApp(MyApp(versieControle: versieControle));
}

class MyApp extends StatelessWidget {
  /// Zie [controleerAppVersie]. Wordt in `main()` gestart en hier alleen
  /// doorgegeven — nooit in `build()` aanmaken, want die draait vaker.
  final Future<VersieControle> versieControle;

  const MyApp({super.key, required this.versieControle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: kNavy, brightness: Brightness.light).copyWith(
      primary: kNavy,
      secondary: kOrange,
      onSecondary: Colors.white,
      tertiary: kOrange,
      onTertiary: Colors.white,
    );

    return MaterialApp(
      title: 'CLSTR',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kOrange,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kNavy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kNavy, width: 2),
          ),
        ),
      ),
      builder: (context, child) {
        return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!);
      },
      home: SplashScreen(volgendeScherm: const _AuthGate(), versieControle: versieControle),
    );
  }
}

/// Zit tussen de login-status en de rest van de app in: onthoudt of de
/// "busje vertrekt"-animatie al getoond is voor de huidige sessie, zodat die
/// maar één keer per keer-inloggen verschijnt (en niet steeds opnieuw als er
/// ergens anders in de boom een setState gebeurt).
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  // Bewust een eigen abonnement in plaats van een StreamBuilder: bij het
  // uitloggen moest de "animatie al getoond"-vlag weer op false, en dat
  // gebeurde eerder middenin build(). State aanpassen tijdens het bouwen van
  // het scherm is in Flutter niet toegestaan (de wijziging telt pas mee bij
  // de volgende build, dus het resultaat hing af van toeval). Hier gebeurt
  // het netjes in de listener, buiten de build om.
  late final StreamSubscription<User?> _authAbonnement;
  User? _gebruiker;
  bool _eersteStatusBinnen = false;
  bool _vertrekAnimatieGetoond = false;

  @override
  void initState() {
    super.initState();
    _authAbonnement = FirebaseAuth.instance.authStateChanges().listen((gebruiker) {
      if (!mounted) return;
      setState(() {
        _gebruiker = gebruiker;
        _eersteStatusBinnen = true;
        // Niet (meer) ingelogd - bij de volgende keer inloggen mag de
        // vertrek-animatie weer getoond worden.
        if (gebruiker == null) _vertrekAnimatieGetoond = false;
      });
    });
  }

  @override
  void dispose() {
    _authAbonnement.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_eersteStatusBinnen) {
      return const Scaffold(body: Center(child: AppLoader()));
    }
    final gebruiker = _gebruiker;
    if (gebruiker == null) return const LoginScreen();
    if (!_vertrekAnimatieGetoond) {
      return VertrekAnimatiePage(
        onKlaar: () {
          if (mounted) setState(() => _vertrekAnimatieGetoond = true);
        },
      );
    }
    return _GebruikerGate(gebruiker: gebruiker);
  }
}

/// Haalt, ná het inloggen, de rol + toegewezen clusters van de gebruiker op
/// uit Firestore (collectie 'gebruikers', document-ID = het e-mailadres
/// waarmee is ingelogd) en toont pas dán de HomePage. Zo krijgt niemand
/// per ongeluk toegang tot clusters die niet voor hem/haar bedoeld zijn.
class _GebruikerGate extends StatelessWidget {
  final User gebruiker;
  const _GebruikerGate({required this.gebruiker});

  @override
  Widget build(BuildContext context) {
    final email = (gebruiker.email ?? '').toLowerCase().trim();
    if (email.isEmpty) return const _GeenToegangScherm(email: '(geen e-mailadres)');

    // Een stream in plaats van een eenmalige .get(): een FutureBuilder met de
    // future rechtstreeks in build() start de opvraging bij ELKE rebuild
    // opnieuw. Bovendien werd de rol/clusters zo maar één keer per app-start
    // gelezen — wees een beheerder je zojuist een cluster toe, dan zag je dat
    // pas na het volledig afsluiten en heropenen van de app. Nu komt zo'n
    // wijziging meteen door.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('gebruikers').doc(email).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: AppLoader()));
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return _GeenToegangScherm(email: email, fout: snapshot.error?.toString());
        }
        final data = snapshot.data!.data() ?? const <String, dynamic>{};
        final rol = (data['rol'] as String?) ?? 'subaccount';
        final bedrijfId = data['bedrijfId'] as String?;
        final clusters = (data['clusters'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [];

        // Superadmin hoort bij geen enkel bedrijf specifiek (bedrijfId is
        // null) en krijgt een eigen startscherm: de lijst van alle bedrijven,
        // in plaats van de gewone HomePage.
        if (rol == 'superadmin') {
          return const SuperadminBedrijvenPage();
        }

        if (bedrijfId == null || bedrijfId.isEmpty) {
          // Nog niet gemigreerd naar het nieuwe multi-bedrijf-systeem (of per
          // ongeluk een account zonder bedrijfId) - dan kan dit account nog
          // nergens bij, i.p.v. de app te laten crashen op een ontbrekend veld.
          return _GeenToegangScherm(email: email);
        }

        return HomePage(rol: rol, bedrijfId: bedrijfId, toegewezenClusters: clusters);
      },
    );
  }
}

class _GeenToegangScherm extends StatelessWidget {
  final String email;

  /// Als het ophalen zelf misging (geen verbinding, geen rechten) is dat iets
  /// anders dan "je hebt geen rol" — dat onderscheid was er niet, waardoor een
  /// netwerkfout er uitzag als een geblokkeerd account.
  final String? fout;
  const _GeenToegangScherm({required this.email, this.fout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fout == null ? Icons.lock_outline : Icons.cloud_off, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                fout == null
                    ? 'Dit account ($email) is nog niet gekoppeld aan een rol.\nNeem contact op met de beheerder.'
                    : 'Je gegevens konden niet worden opgehaald.\nControleer je internetverbinding.\n\n$fout',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Uitloggen')),
            ],
          ),
        ),
      ),
    );
  }
}
