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

  @override
  void initState() {
    super.initState();
    _startListeningToDetections();
    _startListeningToPayments();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _detectionSubscription.cancel();
    _paymentSubscription.cancel();
    _tabController.dispose();
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
      // After updating payment status, try to park waiting vehicles
      _processWaitingVehicles();
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

          for (var slot in slots) {
            slot['entryTime'] = null;
            slot['isFilled'] = false;
            slot['vehicleId'] = null;
            slot['slotClass'] = className;
          }

          for (var vehicleID in detections.keys) {
            var detection = detections[vehicleID];
            if (detection['class'] == className) {
              bool isParked = false;
              for (var slot in slots) {
                if (slot['isFilled'] == false) {
                  var entryTime = detection['time'] is double
                      ? detection['time'].toInt()
                      : detection['time'];
                  slot['entryTime'] = entryTime;
                  slot['isFilled'] = true;
                  slot['vehicleId'] = vehicleID;
                  slot['slotClass'] = detection['class'];
                  isParked = true;
                  break;
                }
              }
              if (!isParked) {
                // Mark the vehicle as hold if no parking slot is available
                await _firestore
                    .collection('detections')
                    .doc(detection['id'])
                    .update({'status': 'Hold'});
              }
            }
          }

          await _firestore
              .collection('parkingSlots')
              .doc(className)
              .update({'slots': slots});

          // Check if parking is full
          bool isFull = slots.every((slot) => slot['isFilled'] == true);
          if (isFull) {
            // Notify that the parking lot is full
            await _sendFullNotification(className);
          }
        }
      }
    } catch (e) {
      print('Error synchronizing parking slots: $e');
    }
  }

  Future<void> _sendFullNotification(String className) async {
    var notification = {
      'message': 'Parking lot for class $className is full. Please turn back.',
      'timestamp': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('notifications').add(notification);
  }

  Future<void> _processWaitingVehicles() async {
    QuerySnapshot detectionSnapshot = await _firestore
        .collection('detections')
        .where('status', isEqualTo: 'Hold')
        .orderBy('time')
        .limit(1)
        .get();

    if (detectionSnapshot.docs.isNotEmpty) {
      var waitingVehicleDoc = detectionSnapshot.docs.first;
      var waitingVehicleData = waitingVehicleDoc.data() as Map<String, dynamic>;

      String vehicleClass = waitingVehicleData['class'];
      DocumentSnapshot parkingSlotSnapshot =
          await _firestore.collection('parkingSlots').doc(vehicleClass).get();

      if (parkingSlotSnapshot.exists) {
        var parkingSlotsData =
            parkingSlotSnapshot.data() as Map<String, dynamic>;
        List<dynamic> slots = parkingSlotsData['slots'] ?? [];

        var availableSlot = slots.firstWhere(
            (slot) => slot['isFilled'] == false,
            orElse: () => null);

        if (availableSlot != null) {
          var entryTime = waitingVehicleData['time'] is double
              ? waitingVehicleData['time'].toInt()
              : waitingVehicleData['time'];
          availableSlot['entryTime'] = entryTime;
          availableSlot['isFilled'] = true;
          availableSlot['vehicleId'] = waitingVehicleData['VehicleID'];
          availableSlot['slotClass'] = vehicleClass;

          await _firestore
              .collection('parkingSlots')
              .doc(vehicleClass)
              .update({'slots': slots});

          // Remove waiting vehicle from detections
          await _firestore
              .collection('detections')
              .doc(waitingVehicleDoc.id)
              .delete();
        }
      }
    }
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
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('detections')
                      .orderBy('time', descending: _sortOrder == 'desc')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(color: Colors.cyan));
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
                        .where((d) =>
                            !(parkingStatus[d['VehicleID'].toString()] ??
                                false))
                        .toList();
                    var exitedVehicles = detections
                        .where((d) =>
                            parkingStatus[d['VehicleID'].toString()] ?? false)
                        .toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        ListView(
                          children: [
                            ...parkedVehicles.map((detection) {
                              var data =
                                  detection.data() as Map<String, dynamic>;
                              var entryTime = _formatTimestamp(data['time']);
                              var vehicleId = data['VehicleID'].toString();
                              return _buildDetectionCard(
                                  context,
                                  vehicleId,
                                  data,
                                  entryTime,
                                  'Parked',
                                  parkingStatus[vehicleId]);
                            }).toList(),
                          ],
                        ),
                        ListView(
                          children: [
                            ...exitedVehicles.map((detection) {
                              var data =
                                  detection.data() as Map<String, dynamic>;
                              var entryTime = _formatTimestamp(data['time']);
                              var vehicleId = data['VehicleID'].toString();
                              return _buildDetectionCard(
                                  context,
                                  vehicleId,
                                  data,
                                  entryTime,
                                  'Exited',
                                  parkingStatus[vehicleId]);
                            }).toList(),
                          ],
                        ),
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('detections')
                              .where('status', isEqualTo: 'Hold')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.cyan));
                            }
                            if (snapshot.hasError) {
                              return Center(
                                  child: Text('Error fetching hold vehicles',
                                      style: TextStyle(color: Colors.red)));
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return Center(
                                  child: Text('No hold vehicles found',
                                      style: TextStyle(color: Colors.red)));
                            }

                            var holdVehicles = snapshot.data!.docs;
                            holdVehicles.sort((a, b) => _sortOrder == 'desc'
                                ? int.parse(b['VehicleID'].toString())
                                    .compareTo(
                                        int.parse(a['VehicleID'].toString()))
                                : int.parse(a['VehicleID'].toString())
                                    .compareTo(
                                        int.parse(b['VehicleID'].toString())));
                            return ListView(
                              children: [
                                ...holdVehicles.map((detection) {
                                  var data =
                                      detection.data() as Map<String, dynamic>;
                                  var entryTime =
                                      _formatTimestamp(data['time']);
                                  var vehicleId = data['VehicleID'].toString();
                                  return _buildDetectionCard(
                                      context,
                                      vehicleId,
                                      data,
                                      entryTime,
                                      'Hold',
                                      parkingStatus[vehicleId]);
                                }).toList(),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
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
