import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential userCredential =
          await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;
      if (user != null) {
        DocumentSnapshot adminSnapshot =
            await _firestore.collection('admins').doc(user.uid).get();
        if (adminSnapshot.exists) {
          startListeningForDetections();
          return user;
        } else {
          await _firebaseAuth.signOut();
          return null;
        }
      }
      return null;
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  void startListeningForDetections() {
    _firestore.collection('detections').snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        _updateParkingSlot(data);
      }
    });
  }

  Future<void> _updateParkingSlot(Map<String, dynamic> detection) async {
    try {
      String vehicleId = detection['VehicleID'].toString();
      String slotClass = detection['class'];
      int entryTime = detection['time'];

      DocumentSnapshot parkingSlotDoc =
          await _firestore.collection('parkingSlots').doc(slotClass).get();
      if (parkingSlotDoc.exists) {
        var parkingSlotsData = parkingSlotDoc.data() as Map<String, dynamic>;
        List<dynamic> slots = parkingSlotsData['slots'] ?? [];

        for (var slot in slots) {
          if (slot['isFilled'] == false && slot['slotClass'] == slotClass) {
            slot['vehicleId'] = vehicleId;
            slot['entryTime'] = entryTime;
            slot['isFilled'] = true;

            await _firestore.collection('parkingSlots').doc(slotClass).update({
              'slots': slots,
            });

            break;
          }
        }
      }
    } catch (e) {
      print("Error updating parking slot: $e");
    }
  }
}
