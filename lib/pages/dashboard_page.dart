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

class _DashboardPageState extends State<DashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _sortOrder = 'desc';

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

  Future<Map<String, bool>> _fetchParkingStatus() async {
    QuerySnapshot paymentSnapshot =
        await _firestore.collection('payment').get();
    Map<String, bool> parkingStatus = {};

    for (var doc in paymentSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      parkingStatus[data['vehicleId'].toString()] = true; // Mark as exited
    }

    return parkingStatus;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard', style: TextStyle(color: Colors.blue)),
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.blue),
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
                child: FutureBuilder<Map<String, bool>>(
                  future: _fetchParkingStatus(),
                  builder: (context, statusSnapshot) {
                    if (statusSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(color: Colors.cyan));
                    }
                    if (statusSnapshot.hasError) {
                      return Center(
                          child: Text('Error fetching parking status',
                              style: TextStyle(color: Colors.red)));
                    }

                    var parkingStatus = statusSnapshot.data ?? {};

                    return StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('detections')
                          .orderBy('time', descending: _sortOrder == 'desc')
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
                              child: Text('Error fetching detections',
                                  style: TextStyle(color: Colors.red)));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                              child: Text('No detections found',
                                  style: TextStyle(color: Colors.red)));
                        }

                        var detections = snapshot.data!.docs;
                        var parkedVehicles = detections
                            .where((d) =>
                                !(parkingStatus[d['VehicleID'].toString()] ??
                                    false))
                            .toList();
                        var exitedVehicles = detections
                            .where((d) =>
                                parkingStatus[d['VehicleID'].toString()] ??
                                false)
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
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Exited Vehicles',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                            ),
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
                        );
                      },
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
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _showEditDialog(context, vehicleId, data),
                  ),
                  if (status == 'Parked')
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () => _confirmDelete(context, vehicleId),
                    ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, String vehicleId, Map<String, dynamic> data) {
    TextEditingController vehicleIdController =
        TextEditingController(text: vehicleId);
    TextEditingController classController =
        TextEditingController(text: data['class']);
    TextEditingController timeController =
        TextEditingController(text: _formatTimestamp(data['time']));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Detection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: vehicleIdController,
                decoration: InputDecoration(labelText: 'Vehicle ID'),
              ),
              TextField(
                controller: classController,
                decoration: InputDecoration(labelText: 'Class'),
              ),
              TextField(
                controller: timeController,
                decoration: InputDecoration(labelText: 'Time'),
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Save'),
              onPressed: () async {
                var updatedData = {
                  'VehicleID': int.tryParse(vehicleIdController.text) ??
                      vehicleIdController.text,
                  'class': classController.text,
                  'time': DateTime.parse(timeController.text)
                      .millisecondsSinceEpoch,
                };

                await _firestore
                    .collection('detections')
                    .doc(vehicleId)
                    .update(updatedData);

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, String vehicleId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Confirm Delete'),
          content: Text('Are you sure you want to delete this detection?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Delete'),
              onPressed: () async {
                await _firestore
                    .collection('detections')
                    .doc(vehicleId)
                    .delete();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
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
