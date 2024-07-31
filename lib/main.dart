import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:webadmin_sp/pages/dashboard_page.dart';
import 'package:webadmin_sp/pages/login_page.dart';
import 'package:webadmin_sp/pages/history_page.dart';
import 'package:webadmin_sp/pages/parking_lot_page.dart';
import 'package:webadmin_sp/providers/auth_provider.dart'
    as local_auth_provider;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => local_auth_provider.AuthProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Smart Parking Admin',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.black),
            bodyMedium: TextStyle(color: Colors.black),
          ),
        ),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
        routes: {
          '/': (context) => LoginPage(),
          '/dashboard': (context) => DashboardPage(),
          '/history': (context) => HistoryPage(),
          '/parking-lot': (context) => ParkingLotPage(),
        },
      ),
    );
  }
}
