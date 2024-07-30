import 'package:flutter/material.dart';
import 'package:webadmin_sp/services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  Future<bool> signIn(String email, String password) async {
    var user = await _authService.signIn(email, password);
    if (user != null) {
      _authService.startListeningForDetections();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    notifyListeners();
  }
}
