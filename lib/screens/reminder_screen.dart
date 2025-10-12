import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({Key? key}) : super(key: key);

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isCheckingLocation = false;
  final Map<String, bool> _inRangeStatus = {};

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _loadBookmarks();
    _startLocationTracking();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final savedReminders = prefs.getStringList('saved_reminders');
    print('Loaded reminders: $savedReminders');
    if (savedReminders != null) {
      setState(() {
        _reminders = savedReminders
            .map((reminder) => jsonDecode(reminder) as Map<String, dynamic>)
            .toList();
        print('Parsed reminders: $_reminders');
      });
    }
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBookmarks = prefs.getStringList('saved_locations');
    print('Loaded bookmarks: $savedBookmarks');
    if (savedBookmarks != null) {
      setState(() {
        _bookmarks = savedBookmarks
            .map((bookmark) => jsonDecode(bookmark) as Map<String, dynamic>)
            .toList();
        _inRangeStatus.clear();
        for (var bookmark in _bookmarks) {
          _inRangeStatus[bookmark['name']] = false;
        }
        print('Parsed bookmarks: $_bookmarks');
      });
    }
  }

  void _startLocationTracking() async {
    _isCheckingLocation = true;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _isCheckingLocation = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _isCheckingLocation = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions denied')),
          );
        }
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _isCheckingLocation = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location permissions permanently denied')),
        );
      }
      return;
    }

    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isCheckingLocation) {
        timer.cancel();
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        print('Current position: ${position.latitude}, ${position.longitude}');
        _checkProximity(position);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error getting location: $e')),
          );
        }
      }
    });
  }

  void _checkProximity(Position currentPosition) {
    if (!_isCheckingLocation) return;
    print(
        'Checking proximity with position: ${currentPosition.latitude}, ${currentPosition.longitude}');
    for (var bookmark in _bookmarks) {
      final bookmarkLat = bookmark['lat'] as double;
      final bookmarkLng = bookmark['lng'] as double;
      final bookmarkName = bookmark['name'] as String;
      final distanceInMeters = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        bookmarkLat,
        bookmarkLng,
      );
      final reminder = _reminders.firstWhere(
        (reminder) => reminder['location'] == bookmarkName,
        orElse: () => {
          'radius': 2000.0,
          'message': 'You’re near $bookmarkName!',
        },
      );
      final radius = (reminder['radius'] as num?)?.toDouble() ?? 2000.0;
      final message = (reminder['message'] as String?)?.isNotEmpty ?? false
          ? reminder['message'] as String
          : 'You’re near $bookmarkName!';
      print(
          'Bookmark: $bookmarkName, Lat: $bookmarkLat, Lng: $bookmarkLng, Distance: $distanceInMeters meters, Radius: $radius, Message: $message');
      final isInRange = distanceInMeters <= radius;
      final wasInRange = _inRangeStatus[bookmarkName] ?? false;
      if (isInRange && !wasInRange) {
        showNotification('Reminder: $bookmarkName', message);
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Reminder: $bookmarkName'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        _inRangeStatus[bookmarkName] = true;
      } else if (!isInRange && wasInRange) {
        _inRangeStatus[bookmarkName] = false;
      }
    }
  }

  Future<void> _addReminder(
      String locationName, String message, double radius) async {
    final reminder = {
      'location': locationName,
      'message': message,
      'radius': radius,
    };
    print('Adding reminder: $reminder');
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _reminders.add(reminder);
    });
    final updatedReminders =
        _reminders.map((reminder) => jsonEncode(reminder)).toList();
    print('Saving reminders: $updatedReminders');
    await prefs.setStringList('saved_reminders', updatedReminders);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reminder added for $locationName')),
      );
    }
  }

  Future<void> _deleteReminder(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _reminders.removeAt(index);
    });
    final updatedReminders =
        _reminders.map((reminder) => jsonEncode(reminder)).toList();
    print('Deleting reminder, new reminders: $updatedReminders');
    await prefs.setStringList('saved_reminders', updatedReminders);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder deleted')),
      );
    }
  }

  void _showAddReminderDialog() {
    final messageController = TextEditingController();
    final radiusController = TextEditingController(text: '2000');
    String? selectedLocation;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Reminder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              hint: const Text('Select a location'),
              items: _bookmarks
                  .map((bookmark) => DropdownMenuItem<String>(
                        value: bookmark['name'],
                        child: Text(bookmark['name']),
                      ))
                  .toList(),
              onChanged: (value) {
                selectedLocation = value;
              },
            ),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(hintText: 'E.g., Buy milk'),
            ),
            TextField(
              controller: radiusController,
              decoration: const InputDecoration(
                  hintText: 'Radius in meters (e.g., 2000)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final message = messageController.text.trim();
              final radius =
                  double.tryParse(radiusController.text.trim()) ?? 2000.0;
              if (selectedLocation != null &&
                  message.isNotEmpty &&
                  radius > 0) {
                print(
                    'Saving reminder: location=$selectedLocation, message=$message, radius=$radius');
                _addReminder(selectedLocation!, message, radius);
                Navigator.pop(context);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Pick a location, add a message, and set a valid radius!'),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isCheckingLocation = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _reminders.isEmpty
          ? const Center(child: Text('No reminders yet. Add one!'))
          : ListView.builder(
              itemCount: _reminders.length,
              itemBuilder: (context, index) {
                final data = _reminders[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 4,
                  margin:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  child: ListTile(
                    leading: const Icon(Icons.alarm, color: Colors.orange),
                    title: Text(
                      data['location'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle:
                        Text('${data['message']} (Radius: ${data['radius']}m)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteReminder(index),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddReminderDialog,
        child: const Icon(Icons.add_alarm),
        tooltip: 'Add Reminder',
      ),
    );
  }
}
