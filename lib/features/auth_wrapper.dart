import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webadmin_sp/pages/admin_dashboard.dart';
import 'package:webadmin_sp/pages/login_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          // User is logged in
          return const AdminDashboardWrapper();
        }
        // User is not logged in
        return const LoginPage();
      },
    );
  }
}

class AdminDashboardWrapper extends StatelessWidget {
  const AdminDashboardWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection('admins').doc(user.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData && snapshot.data!.exists) {
            final adminData = snapshot.data!;
            final adminName = adminData['name'];
            return AdminDashboard(adminName: adminName);
          } else {
            return const LoginPage();
          }
        },
      );
    } else {
      return const LoginPage();
    }
  }
}
