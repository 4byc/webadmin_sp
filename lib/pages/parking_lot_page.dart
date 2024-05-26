import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ParkingLotPage extends StatefulWidget {
  const ParkingLotPage({super.key});

  @override
  _ParkingLotPageState createState() => _ParkingLotPageState();
}

class _ParkingLotPageState extends State<ParkingLotPage> {
  String _selectedSection = 'A';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _refreshParkingSlots() async {
    try {
      QuerySnapshot detectionSnapshot =
          await _firestore.collection('detections').get();
      for (var detectionDoc in detectionSnapshot.docs) {
        var detectionData = detectionDoc.data() as Map<String, dynamic>;
        String vehicleId = detectionData['VehicleID'];
        String vehicleClass = detectionData['class'];
        int entryTime = (detectionData['time'] as num).toInt();

        QuerySnapshot parkingSlotSnapshot =
            await _firestore.collection('parkingSlots').get();
        bool slotAssigned = false;

        for (var slotDoc in parkingSlotSnapshot.docs) {
          var slotData = slotDoc.data() as Map<String, dynamic>;
          List<dynamic> slots = slotData['slots'];

          for (var slot in slots) {
            if (slot['slotClass'] == vehicleClass && !slot['isFilled']) {
              slot['isFilled'] = true;
              slot['vehicleId'] = vehicleId;
              slot['entryTime'] = entryTime;

              await _firestore
                  .collection('parkingSlots')
                  .doc(slotDoc.id)
                  .update({
                'slots': slots,
              });

              await _firestore
                  .collection('detections')
                  .doc(detectionDoc.id)
                  .delete();

              slotAssigned = true;
              break;
            }
          }

          if (slotAssigned) {
            break;
          }
        }
      }
      setState(() {});
    } catch (e) {
      print("Error while refreshing parking slots: $e");
    }
  }

  String _formatTimestamp(int timestamp) {
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Lot'),
        actions: [
          DropdownButton<String>(
            value: _selectedSection,
            items: ['A', 'B', 'C'].map((String section) {
              return DropdownMenuItem<String>(
                value: section,
                child: Text('Section $section'),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedSection = newValue!;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshParkingSlots,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('parkingSlots')
            .doc(_selectedSection)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          var slotData = snapshot.data!.data() as Map<String, dynamic>;
          var slots = slotData['slots'] as List<dynamic>;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Slot ID')),
                  DataColumn(label: Text('Class')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Entry Time')),
                ],
                rows: slots.map((slot) {
                  return DataRow(
                    cells: [
                      DataCell(Text(slot['id'])),
                      DataCell(Text(slot['slotClass'])),
                      DataCell(
                        Icon(
                          Icons.local_parking,
                          color: slot['isFilled'] ? Colors.red : Colors.green,
                        ),
                      ),
                      DataCell(
                        slot['isFilled']
                            ? Text(_formatTimestamp(slot['entryTime']))
                            : const Text('-'),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
