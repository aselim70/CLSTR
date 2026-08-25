import 'home_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'app_theme.dart';
import 'splash_screen.dart';

const Color kNavy = Color(0xFF002169);
const Color kOrange = Color(0xFFFF8500);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kNavy,
      brightness: Brightness.light,
    ).copyWith(
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
      home: SplashScreen(
        volgendeScherm: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: AppLoader()),
              );
            }
            if (snapshot.hasData) {
              return _GebruikerGate(gebruiker: snapshot.data!);
            }
            return const LoginScreen();
          },
        ),
      ),
    );
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
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('gebruikers').doc(email).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: AppLoader()));
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return _GeenToegangScherm(email: email);
        }
        final data = snapshot.data!.data()!;
        final rol = (data['rol'] as String?) ?? 'subaccount';
        final clusters = (data['clusters'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [];
        return HomePage(rol: rol, toegewezenClusters: clusters);
      },
    );
  }
}

class _GeenToegangScherm extends StatelessWidget {
  final String email;
  const _GeenToegangScherm({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Dit account ($email) is nog niet gekoppeld aan een rol.\nNeem contact op met de beheerder.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Uitloggen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}