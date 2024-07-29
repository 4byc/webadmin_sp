import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:webadmin_sp/widgets/common_drawer.dart';
import 'dart:async';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _sortOrder = 'desc';
  late StreamSubscription<QuerySnapshot> _detectionSubscription;
  late StreamSubscription<QuerySnapshot> _paymentSubscription;
  Map<String, bool> parkingStatus = {};
  late TabController _tabController;
  Map<String, bool> fullSlotsStatus = {'A': false, 'B': false, 'C': false};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _startListeningToDetections();
    _startListeningToPayments();
    _processPendingVehicles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _detectionSubscription.cancel();
    _paymentSubscription.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchAdminData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('admins').doc(user.uid).get();
      return doc.data() ?? {};
    }
    return {};
  }

  String _formatTimestamp(dynamic timestamp) {
    var date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp is int ? timestamp : (timestamp as double).toInt()) * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  void _startListeningToDetections() {
    _detectionSubscription =
        _firestore.collection('detections').snapshots().listen((snapshot) {
      _synchronizeParkingSlots(snapshot.docs);
    });
  }

  void _startListeningToPayments() {
    _paymentSubscription =
        _firestore.collection('payment').snapshots().listen((snapshot) {
      setState(() {
        parkingStatus = {};
        for (var doc in snapshot.docs) {
          var data = doc.data() as Map<String, dynamic>;
          parkingStatus[data['vehicleId'].toString()] = true;
        }
      });
    });
  }

  Future<void> _synchronizeParkingSlots(
      List<QueryDocumentSnapshot> detectionDocs) async {
    try {
      QuerySnapshot paymentSnapshot =
          await _firestore.collection('payment').get();
      Map<int, dynamic> detections = {};
      Set<int> exitedVehicles =
          paymentSnapshot.docs.map((doc) => doc['vehicleId'] as int).toSet();

      for (var doc in detectionDocs) {
        var data = doc.data() as Map<String, dynamic>;
        int vehicleID = int.parse(data['VehicleID'].toString());
        if (!exitedVehicles.contains(vehicleID)) {
          detections[vehicleID] = data;
        }
      }

      for (var className in ['A', 'B', 'C']) {
        DocumentSnapshot parkingSlotSnapshot =
            await _firestore.collection('parkingSlots').doc(className).get();
        if (parkingSlotSnapshot.exists) {
          var parkingSlotsData =
              parkingSlotSnapshot.data() as Map<String, dynamic>;
          List<dynamic> slots = parkingSlotsData['slots'] ?? [];
          bool isFull = true;

          for (var slot in slots) {
            slot['entryTime'] = null;
            slot['isFilled'] = false;
            slot['vehicleId'] = null;
            slot['slotClass'] = className;
          }

          for (var vehicleID in detections.keys) {
            var detection = detections[vehicleID];
            if (detection['class'] == className) {
              bool parked = false;
              for (var slot in slots) {
                if (slot['isFilled'] == false) {
                  var entryTime = detection['time'] is double
                      ? detection['time'].toInt()
                      : detection['time'];
                  slot['entryTime'] = entryTime;
                  slot['isFilled'] = true;
                  slot['vehicleId'] = vehicleID;
                  slot['slotClass'] = detection['class'];
                  parked = true;
                  break;
                }
              }
              if (!parked) {
                await _handleVehicleFull(
                    className, vehicleID, detection['time']);
              }
            }
          }

          isFull = slots.every((slot) => slot['isFilled'] == true);
          fullSlotsStatus[className] = isFull;
          await _firestore.collection('parkingSlots').doc(className).update({
            'slots': slots,
            'isFull': isFull,
          });
        }
      }

      _processPendingVehicles();
    } catch (e) {
      print('Error synchronizing parking slots: $e');
    }
  }

  Future<void> _handleVehicleFull(
      String slotClass, int vehicleId, int entryTime) async {
    var exitTime = DateTime.now().millisecondsSinceEpoch;
    await _firestore.collection('canceledVehicles').add({
      'vehicleId': vehicleId,
      'class': slotClass,
      'time': entryTime,
    });
    await _firestore.collection('payment').add({
      'vehicleId': vehicleId,
      'slotClass': slotClass,
      'entryTime': entryTime,
      'exitTime': exitTime,
      'duration': 0,
      'totalCost': 0,
      'fine': 0,
      'finalAmount': 0,
      'status': 'Canceled'
    });

    // Notify user to turn back
    _notifyUserVehicleFull(slotClass);
  }

  Future<void> _processPendingVehicles() async {
    final QuerySnapshot pendingSnapshot =
        await _firestore.collection('pendingVehicles').get();
    for (final doc in pendingSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final vehicleId = data['vehicleId'];
      final slotClass = data['class'];
      final entryTime = data['time'];

      final DocumentSnapshot slotSnapshot =
          await _firestore.collection('parkingSlots').doc(slotClass).get();
      if (slotSnapshot.exists) {
        final slotData = slotSnapshot.data() as Map<String, dynamic>;
        final slots = slotData['slots'] as List<dynamic>;

        final availableSlot = slots.firstWhere(
          (slot) => slot['isFilled'] == false,
          orElse: () => null,
        );

        if (availableSlot != null) {
          availableSlot['vehicleId'] = vehicleId;
          availableSlot['entryTime'] = entryTime;
          availableSlot['isFilled'] = true;

          await _firestore
              .collection('parkingSlots')
              .doc(slotClass)
              .update({'slots': slots});
          await _firestore.collection('pendingVehicles').doc(doc.id).delete();
        } else {
          await _handleVehicleFull(slotClass, vehicleId, entryTime);
        }
      } else {
        await _handleVehicleFull(slotClass, vehicleId, entryTime);
      }
    }
  }

  void _notifyUserVehicleFull(String slotClass) {
    // Logic to send notification to the user
    print("Slot $slotClass is full. Please turn back.");
    // Add notification logic here
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard', style: TextStyle(color: Colors.blue)),
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.blue),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          indicatorColor: Colors.cyan,
          tabs: [
            Tab(text: 'Parked Vehicles'),
            Tab(text: 'Exited Vehicles'),
            Tab(text: 'Canceled Vehicles'),
          ],
        ),
      ),
      drawer: CommonDrawer(),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchAdminData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: Colors.cyan));
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Error fetching admin data',
                    style: TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
                child: Text('No admin data found',
                    style: TextStyle(color: Colors.red)));
          }

          final adminData = snapshot.data!;
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Welcome Admin, ${adminData['name']}',
                            style: TextStyle(color: Colors.blue, fontSize: 18)),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: RealTimeClock(),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: Icon(Icons.sort, color: Colors.blue),
                          onPressed: () {
                            setState(() {
                              _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildParkedVehiclesTab(),
                    _buildExitedVehiclesTab(),
                    _buildCanceledVehiclesTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildParkedVehiclesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('detections')
          .orderBy('time', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: Colors.cyan));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error fetching detections',
                  style: TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No detections found',
                  style: TextStyle(color: Colors.red)));
        }

        var detections = snapshot.data!.docs;
        detections.sort((a, b) => _sortOrder == 'desc'
            ? int.parse(b['VehicleID'].toString())
                .compareTo(int.parse(a['VehicleID'].toString()))
            : int.parse(a['VehicleID'].toString())
                .compareTo(int.parse(b['VehicleID'].toString())));
        var parkedVehicles = detections
            .where((d) => !(parkingStatus[d['VehicleID'].toString()] ?? false))
            .toList();

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Parked Vehicles',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
            ),
            if (fullSlotsStatus['A']!) ...[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Class A is Full',
                    style: TextStyle(fontSize: 16, color: Colors.red)),
              ),
            ],
            if (fullSlotsStatus['B']!) ...[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Class B is Full',
                    style: TextStyle(fontSize: 16, color: Colors.red)),
              ),
            ],
            if (fullSlotsStatus['C']!) ...[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Class C is Full',
                    style: TextStyle(fontSize: 16, color: Colors.red)),
              ),
            ],
            ...parkedVehicles.map((detection) {
              var data = detection.data() as Map<String, dynamic>;
              var entryTime = _formatTimestamp(data['time']);
              var vehicleId = data['VehicleID'].toString();
              return _buildDetectionCard(context, vehicleId, data, entryTime,
                  'Parked', parkingStatus[vehicleId]);
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildExitedVehiclesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('detections')
          .orderBy('time', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: Colors.cyan));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error fetching detections',
                  style: TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No detections found',
                  style: TextStyle(color: Colors.red)));
        }

        var detections = snapshot.data!.docs;
        detections.sort((a, b) => _sortOrder == 'desc'
            ? int.parse(b['VehicleID'].toString())
                .compareTo(int.parse(a['VehicleID'].toString()))
            : int.parse(a['VehicleID'].toString())
                .compareTo(int.parse(b['VehicleID'].toString())));
        var exitedVehicles = detections
            .where((d) => parkingStatus[d['VehicleID'].toString()] ?? false)
            .toList();

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Exited Vehicles',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
            ),
            ...exitedVehicles.map((detection) {
              var data = detection.data() as Map<String, dynamic>;
              var entryTime = _formatTimestamp(data['time']);
              var vehicleId = data['VehicleID'].toString();
              return _buildDetectionCard(context, vehicleId, data, entryTime,
                  'Exited', parkingStatus[vehicleId]);
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildCanceledVehiclesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('canceledVehicles')
          .orderBy('time', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: Colors.cyan));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error fetching cancellations',
                  style: TextStyle(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No cancellations found',
                  style: TextStyle(color: Colors.red)));
        }

        var canceledVehicles = snapshot.data!.docs;
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Canceled Vehicles',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
            ),
            ...canceledVehicles.map((detection) {
              var data = detection.data() as Map<String, dynamic>;
              var entryTime = _formatTimestamp(data['time']);
              var vehicleId = data['vehicleId'].toString();
              return _buildDetectionCard(context, vehicleId, data, entryTime,
                  'Canceled', parkingStatus[vehicleId]);
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildDetectionCard(
      BuildContext context,
      String vehicleId,
      Map<String, dynamic> data,
      String entryTime,
      String status,
      bool? isExited) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        elevation: 5,
        color: Colors.blue[50],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Vehicle ID: $vehicleId',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
              SizedBox(height: 8),
              Text('Class: ${data['class']}',
                  style: TextStyle(fontSize: 16, color: Colors.cyan)),
              SizedBox(height: 8),
              Text('Entry Time: $entryTime',
                  style: TextStyle(fontSize: 16, color: Colors.cyan)),
              SizedBox(height: 8),
              Text('Status: $status',
                  style: TextStyle(fontSize: 16, color: Colors.cyan)),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class RealTimeClock extends StatefulWidget {
  @override
  _RealTimeClockState createState() => _RealTimeClockState();
}

class _RealTimeClockState extends State<RealTimeClock> {
  late Timer _timer;
  String _currentTime = '';
  String _currentDate = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    setState(() {
      _currentTime = _formatCurrentTime();
      _currentDate = _formatCurrentDate();
    });
  }

  String _formatCurrentTime() {
    return DateFormat('HH:mm:ss').format(DateTime.now());
  }

  String _formatCurrentDate() {
    return DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(_currentDate, style: TextStyle(color: Colors.blue, fontSize: 18)),
        Text(_currentTime, style: TextStyle(color: Colors.blue, fontSize: 18)),
      ],
    );
  }
}
