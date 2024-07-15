import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign in with email and password
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
          startListeningForDetections(); // Start listening for detections after successful login
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

  // Sign out the current user
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  // Start listening for detections in Firestore
  void startListeningForDetections() {
    _firestore.collection('detections').snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        _updateParkingSlot(data);
      }
    });
  }

  // Update parking slot based on detection data
  Future<void> _updateParkingSlot(Map<String, dynamic> detection) async {
    try {
      String vehicleId = detection['VehicleID'].toString();
      String slotClass = detection['class'];
      int entryTime = detection['time'];

      print(
          "Updating slot for VehicleID: $vehicleId, Class: $slotClass, Time: $entryTime");

      DocumentSnapshot parkingSlotDoc =
          await _firestore.collection('parkingSlots').doc(slotClass).get();
      if (parkingSlotDoc.exists) {
        var parkingSlotsData = parkingSlotDoc.data() as Map<String, dynamic>;
        List<dynamic> slots = parkingSlotsData['slots'] ?? [];

        for (var slot in slots) {
          if (slot['isFilled'] == false && slot['slotClass'] == slotClass) {
            print("Found available slot: ${slot['id']}");

            // Update slot data
            slot['vehicleId'] = vehicleId;
            slot['entryTime'] = entryTime;
            slot['isFilled'] = true;

            // Update Firestore document
            await _firestore.collection('parkingSlots').doc(slotClass).update({
              'slots': slots,
            });

            print("Slot updated successfully.");
            break;
          }
        }
      } else {
        print("No parking slots found for class $slotClass");
      }
    } catch (e) {
      print("Error updating parking slot: $e");
    }
  }
}
