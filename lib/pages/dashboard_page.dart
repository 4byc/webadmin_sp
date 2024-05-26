import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:webadmin_sp/widgets/common_drawer.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard', style: TextStyle(color: Colors.blue)),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.sort, color: Colors.blue),
            onPressed: () {
              setState(() {
                _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
              });
            },
          ),
        ],
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
                child: Text('Welcome, ${adminData['name']}',
                    style: TextStyle(color: Colors.blue, fontSize: 18)),
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
                    return ListView.builder(
                      itemCount: detections.length,
                      itemBuilder: (context, index) {
                        var detection =
                            detections[index].data() as Map<String, dynamic>;
                        var entryTime = _formatTimestamp(detection['time']);
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
                                  Text('Vehicle ID: ${detection['VehicleID']}',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                  SizedBox(height: 8),
                                  Text('Class: ${detection['class']}',
                                      style: TextStyle(
                                          fontSize: 16, color: Colors.cyan)),
                                  SizedBox(height: 8),
                                  Text('Entry Time: $entryTime',
                                      style: TextStyle(
                                          fontSize: 16, color: Colors.cyan)),
                                ],
                              ),
                            ),
                          ),
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
}
