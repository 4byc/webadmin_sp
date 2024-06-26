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
      QuerySnapshot detectionSnapshot =
          await _firestore.collection('detections').get();
      QuerySnapshot paymentSnapshot =
          await _firestore.collection('payment').get();
      Map<String, dynamic> detections = {};
      Set<String> processedVehicles = paymentSnapshot.docs
          .map((doc) => doc['vehicleId'].toString())
          .toSet();

      for (var doc in detectionSnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (!processedVehicles.contains(data['VehicleID'].toString())) {
          detections[data['VehicleID'].toString()] = data;
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
              for (var slot in slots) {
                if (slot['isFilled'] == false) {
                  var entryTime = detection['time'] is double
                      ? detection['time'].toInt()
                      : detection['time'];
                  slot['entryTime'] = entryTime;
                  slot['isFilled'] = true;
                  slot['vehicleId'] = int.tryParse(vehicleID) ?? vehicleID;
                  slot['slotClass'] = detection['class'];
                  break;
                }
              }
            }
          }

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

  void _showSlotDetails(Map<String, dynamic> slot) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Slot ID: ${slot['id']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Vehicle ID: ${slot['vehicleId'] ?? 'N/A'}'),
              Text('Class: ${slot['slotClass'] ?? 'N/A'}'),
              Text('Entry Time: ${_formatTimestamp(slot['entryTime'])}'),
              Text('Is Filled: ${slot['isFilled'] ? 'Yes' : 'No'}'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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

          return GridView.builder(
            padding: const EdgeInsets.all(8.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, // Adjust the number of columns as needed
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
            ),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              var slot = slots[index];
              bool isFilled = slot['isFilled'] ?? false;

              return GestureDetector(
                onTap: () => _showSlotDetails(slot),
                child: Container(
                  decoration: BoxDecoration(
                    color: isFilled ? Colors.red[100] : Colors.green[100],
                    borderRadius: BorderRadius.circular(10.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Slot ID: ${slot['id']}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(isFilled ? 'Filled' : 'Empty'),
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
