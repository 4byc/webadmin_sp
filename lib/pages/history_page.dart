import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _formatTimestamp(double timestamp) {
    var date = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Exit History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('exits').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          var exitDocs = snapshot.data!.docs;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('ID')),
                DataColumn(label: Text('Class')),
                DataColumn(label: Text('Exit Time')),
                DataColumn(label: Text('Parking Duration')),
                DataColumn(label: Text('Parking Fee')),
                DataColumn(label: Text('Vehicle ID')),
              ],
              rows: exitDocs.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                return DataRow(
                  cells: [
                    DataCell(Text(data['id'] ?? '')),
                    DataCell(Text(data['class'] ?? '')),
                    DataCell(Text(_formatTimestamp(data['exitTime']))),
                    DataCell(Text(data['parkingDuration'].toString())),
                    DataCell(Text(data['parkingFee'].toString())),
                    DataCell(Text(data['vehicleId'] ?? '')),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
