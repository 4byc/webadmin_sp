import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:webadmin_sp/widgets/common_drawer.dart';
import 'package:webadmin_sp/widgets/gradient_app_bar.dart';

class ParkingLotPage extends StatefulWidget {
  @override
  _ParkingLotPageState createState() => _ParkingLotPageState();
}

class _ParkingLotPageState extends State<ParkingLotPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedClass = 'A'; // Default class selection
  String _sortOrder = 'asc'; // Default sorting order
  String _filter = 'All'; // Default filter

  @override
  void initState() {
    super.initState();
    _synchronizeParkingSlots();
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    var date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp is int ? timestamp : (timestamp as double).toInt()) * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  Future<void> _synchronizeParkingSlots() async {
    try {
      // Fetch all detections
      QuerySnapshot detectionSnapshot =
          await _firestore.collection('detections').get();
      Map<String, dynamic> detections = {};

      // Collect all detections
      for (var doc in detectionSnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        print('Detection data: $data');
        detections[data['VehicleID'].toString()] = data;
      }

      // Iterate over each class
      for (var className in ['A', 'B', 'C']) {
        DocumentSnapshot parkingSlotSnapshot =
            await _firestore.collection('parkingSlots').doc(className).get();
        if (parkingSlotSnapshot.exists) {
          var parkingSlotsData =
              parkingSlotSnapshot.data() as Map<String, dynamic>;
          List<dynamic> slots = parkingSlotsData['slots'] ?? [];

          // Clear previous allocations
          for (var slot in slots) {
            slot['entryTime'] = null;
            slot['isFilled'] = false;
            slot['vehicleId'] = null;
            slot['slotClass'] = className;
          }

          // Allocate slots to vehicles
          for (var vehicleID in detections.keys) {
            var detection = detections[vehicleID];
            if (detection['class'] == className) {
              for (var slot in slots) {
                if (slot['isFilled'] == false) {
                  slot['entryTime'] = detection['time'];
                  slot['isFilled'] = true;
                  slot['vehicleId'] = vehicleID;
                  slot['slotClass'] = detection['class'];
                  break;
                }
              }
            }
          }

          // Update the slots in Firestore
          await _firestore.collection('parkingSlots').doc(className).update({
            'slots': slots,
          });
        }
      }
    } catch (e) {
      print('Error synchronizing parking slots: $e');
    }
  }

  Future<List<dynamic>> _fetchParkingSlots(String parkingClass) async {
    DocumentSnapshot snapshot =
        await _firestore.collection('parkingSlots').doc(parkingClass).get();
    if (snapshot.exists) {
      var data = snapshot.data() as Map<String, dynamic>;
      return data['slots'] as List<dynamic>? ?? [];
    }
    return [];
  }

  List<dynamic> _filterSlots(List<dynamic> slots) {
    if (_filter == 'Filled') {
      return slots.where((slot) => slot['isFilled'] == true).toList();
    } else if (_filter == 'Empty') {
      return slots.where((slot) => slot['isFilled'] == false).toList();
    }
    return slots;
  }

  List<dynamic> _removeDuplicateSlots(List<dynamic> slots) {
    var uniqueSlots = <String, dynamic>{};
    for (var slot in slots) {
      uniqueSlots[slot['id']] = slot;
    }
    return uniqueSlots.values.toList();
  }

  List<dynamic> _sortSlots(List<dynamic> slots) {
    slots.sort((a, b) {
      var idA =
          int.tryParse((a['id'] ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
      var idB =
          int.tryParse((b['id'] ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
      return _sortOrder == 'asc' ? idA.compareTo(idB) : idB.compareTo(idA);
    });
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Parking Lot',
        actions: <Widget>[
          DropdownButton<String>(
            value: _selectedClass,
            dropdownColor: Colors.blue,
            onChanged: (String? newValue) {
              setState(() {
                _selectedClass = newValue!;
                _synchronizeParkingSlots();
              });
            },
            items: <String>['A', 'B', 'C']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(
                  'Class $value',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: Icon(
              _sortOrder == 'asc' ? Icons.arrow_upward : Icons.arrow_downward,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {
                _synchronizeParkingSlots();
              });
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: Colors.white),
            onSelected: (String result) {
              setState(() {
                _filter = result;
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'All',
                child: Text('Show All'),
              ),
              const PopupMenuItem<String>(
                value: 'Filled',
                child: Text('Show Filled'),
              ),
              const PopupMenuItem<String>(
                value: 'Empty',
                child: Text('Show Empty'),
              ),
            ],
          ),
        ],
      ),
      drawer: CommonDrawer(),
      body: FutureBuilder<List<dynamic>>(
        future: _fetchParkingSlots(_selectedClass),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error fetching parking slots'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No parking slots found'));
          }

          var slots = _removeDuplicateSlots(_filterSlots(snapshot.data!));
          slots = _sortSlots(slots);

          return ListView.builder(
            itemCount: slots.length,
            itemBuilder: (context, index) {
              var slot = slots[index];
              var entryTime = _formatTimestamp(slot['entryTime']);
              bool isFilled = slot['isFilled'] ?? false;

              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Card(
                  elevation: 5,
                  color: isFilled ? Colors.red[100] : Colors.green[100],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Slot ID: ${slot['id'] ?? 'N/A'}',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Vehicle ID: ${slot['vehicleId'] ?? 'N/A'}'),
                        Text('Class: ${slot['slotClass'] ?? 'N/A'}'),
                        Text('Entry Time: $entryTime'),
                        Text('Is Filled: ${isFilled ? 'Yes' : 'No'}'),
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
