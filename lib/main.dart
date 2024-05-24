import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:webadmin_sp/features/auth_wrapper.dart';
import 'package:webadmin_sp/pages/login_page.dart';
import 'package:webadmin_sp/pages/history_page.dart';
import 'firebase_options.dart';

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
    return MaterialApp(
      title: 'Admin Dashboard',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/history': (context) => const HistoryPage(), // Add the new route here
      },
    );
  }
}
