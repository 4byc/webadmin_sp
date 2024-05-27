import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:webadmin_sp/widgets/common_drawer.dart';
import 'package:webadmin_sp/widgets/gradient_app_bar.dart';

class HistoryPage extends StatefulWidget {
  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _sortOrder = 'desc'; // Default sorting order

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    var date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp is int ? timestamp : (timestamp as double).toInt()) * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'History',
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.sort, color: Colors.white),
            onPressed: () {
              setState(() {
                _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
              });
            },
          ),
        ],
      ),
      drawer: CommonDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('payment')
            .orderBy('exitTime', descending: _sortOrder == 'desc')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error fetching payment data'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No payment records found'));
          }

          var payments = snapshot.data!.docs;
          return ListView.builder(
            itemCount: payments.length,
            itemBuilder: (context, index) {
              var payment = payments[index].data() as Map<String, dynamic>;

              var vehicleId = payment['vehicleId'] ?? 'N/A';
              var slotClass = payment['slotClass'] ?? 'N/A';
              var exitTime = _formatTimestamp(payment['exitTime']);
              var parkingDuration = payment['duration'] is int
                  ? payment['duration']
                  : (payment['duration'] is double
                      ? (payment['duration'] as double).toInt()
                      : 'N/A');
              var parkingFee = payment['totalCost'] is int
                  ? payment['totalCost']
                  : (payment['totalCost'] is double
                      ? (payment['totalCost'] as double).toInt()
                      : 'N/A');

              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Card(
                  elevation: 5,
                  color: Colors.white,
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
                        Text('Class: $slotClass',
                            style: TextStyle(fontSize: 16, color: Colors.cyan)),
                        SizedBox(height: 8),
                        Text('Exit Time: $exitTime',
                            style: TextStyle(fontSize: 16)),
                        SizedBox(height: 8),
                        Text('Parking Duration: $parkingDuration seconds',
                            style: TextStyle(fontSize: 16)),
                        SizedBox(height: 8),
                        Text('Parking Fee: \$${parkingFee}',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
