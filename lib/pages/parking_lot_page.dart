import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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

  // Format Firestore timestamp to readable string
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    var date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp is int ? timestamp : (timestamp as double).toInt()) * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  // Get a stream of parking slots for the selected class
  Stream<DocumentSnapshot> _getParkingSlotStream(String className) {
    return _firestore.collection('parkingSlots').doc(className).snapshots();
  }

  // Filter parking slots based on the selected filter
  List<dynamic> _filterSlots(List<dynamic> slots) {
    if (_filter == 'Filled') {
      return slots.where((slot) => slot['isFilled'] == true).toList();
    } else if (_filter == 'Empty') {
      return slots.where((slot) => slot['isFilled'] == false).toList();
    }
    return slots;
  }

  // Remove duplicate slots from the list
  List<dynamic> _removeDuplicateSlots(List<dynamic> slots) {
    var uniqueSlots = <String, dynamic>{};
    for (var slot in slots) {
      uniqueSlots[slot['id']] = slot;
    }
    return uniqueSlots.values.toList();
  }

  // Sort the slots based on the selected sorting order
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

  // Show details of the selected parking slot
  void _showSlotDetails(Map<String, dynamic> slot) {
    TextEditingController slotIdController = TextEditingController();

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
              TextField(
                controller: slotIdController,
                decoration: InputDecoration(
                  labelText: 'New Slot ID',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Move'),
              onPressed: () {
                _moveSlotData(slot['id'], slotIdController.text);
                Navigator.of(context).pop();
              },
            ),
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

  // Move data from one slot to another
  Future<void> _moveSlotData(String oldSlotId, String newSlotId) async {
    var classDoc = _firestore.collection('parkingSlots').doc(_selectedClass);
    var snapshot = await classDoc.get();

    if (snapshot.exists) {
      var data = snapshot.data() as Map<String, dynamic>;
      var slots = data['slots'] as List<dynamic>;

      var oldSlot = slots.firstWhere((slot) => slot['id'] == oldSlotId,
          orElse: () => null);
      var newSlot = slots.firstWhere((slot) => slot['id'] == newSlotId,
          orElse: () => null);

      if (oldSlot != null && newSlot != null) {
        newSlot['vehicleId'] = oldSlot['vehicleId'];
        newSlot['slotClass'] = oldSlot['slotClass'];
        newSlot['entryTime'] = oldSlot['entryTime'];
        newSlot['isFilled'] = oldSlot['isFilled'];

        oldSlot['vehicleId'] = null;
        oldSlot['slotClass'] = null;
        oldSlot['entryTime'] = null;
        oldSlot['isFilled'] = false;

        await classDoc.update({'slots': slots});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Parking Lot',
        actions: <Widget>[
          // Dropdown menu for class selection
          DropdownButton<String>(
            value: _selectedClass,
            dropdownColor: Colors.blue,
            onChanged: (String? newValue) {
              setState(() {
                _selectedClass = newValue!;
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
          // Icon button for sorting order
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
          // Popup menu for filtering slots
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: _getParkingSlotStream(_selectedClass),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error fetching parking slots'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('No parking slots found'));
          }

          var parkingSlotsData = snapshot.data!.data() as Map<String, dynamic>;
          var slots = parkingSlotsData['slots'] as List<dynamic>;
          slots = _removeDuplicateSlots(_filterSlots(slots));
          slots = _sortSlots(slots);

          return GridView.builder(
            padding: const EdgeInsets.all(8.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
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
