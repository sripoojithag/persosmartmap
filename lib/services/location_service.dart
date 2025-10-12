import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const String taskKey = 'locationCheckTask';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iOSSettings =
      DarwinInitializationSettings();
  const InitializationSettings settings =
      InitializationSettings(android: androidSettings, iOS: iOSSettings);
  await _notificationsPlugin.initialize(settings);
}

Future<void> showNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'reminder_channel',
    'Reminders',
    channelDescription: 'Notifications for location-based reminders',
    importance: Importance.max,
    priority: Priority.high,
  );
  const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails();
  final NotificationDetails details =
      NotificationDetails(android: androidDetails, iOS: iOSDetails);
  await _notificationsPlugin.show(0, title, body, details);
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBookmarks = prefs.getStringList('saved_locations');
    final savedReminders = prefs.getStringList('saved_reminders');

    if (savedBookmarks == null || savedReminders == null) {
      return Future.value(true);
    }

    final bookmarks = savedBookmarks.map((e) => jsonDecode(e)).toList();
    final reminders = savedReminders.map((e) => jsonDecode(e)).toList();

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    for (var bookmark in bookmarks) {
      final reminder = reminders.firstWhere(
        (r) => r['location'] == bookmark['name'],
        orElse: () => null,
      );
      if (reminder == null) continue;

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        bookmark['lat'],
        bookmark['lng'],
      );

      if (distance <= (reminder['radius'] ?? 2000.0)) {
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_channel',
            'Reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        );
        await _notificationsPlugin.show(
          bookmark.hashCode,
          'Reminder: ${bookmark['name']}',
          reminder['message'],
          details,
        );
      }
    }

    return Future.value(true);
  });
}

Future<void> checkLocationInBackground() async {
  final prefs = await SharedPreferences.getInstance();
  final savedReminders = prefs.getStringList('saved_reminders') ?? [];
  final reminders = savedReminders
      .map((reminder) => jsonDecode(reminder) as Map<String, dynamic>)
      .toList();
  final savedBookmarks = prefs.getStringList('saved_locations') ?? [];
  final bookmarks = savedBookmarks
      .map((bookmark) => jsonDecode(bookmark) as Map<String, dynamic>)
      .toList();

  if (bookmarks.isEmpty) return;

  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;
  }

  final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);

  for (var bookmark in bookmarks) {
    final bookmarkLat = bookmark['lat'] as double;
    final bookmarkLng = bookmark['lng'] as double;
    final bookmarkName = bookmark['name'] as String;
    final distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      bookmarkLat,
      bookmarkLng,
    );
    final reminder = reminders.firstWhere(
      (reminder) => reminder['location'] == bookmarkName,
      orElse: () => {'radius': 2000.0, 'message': 'You’re near $bookmarkName!'},
    );
    final radius = (reminder['radius'] as num?)?.toDouble() ?? 2000.0;
    final message =
        reminder['message'] as String? ?? 'You’re near $bookmarkName!';

    if (distanceInMeters <= radius) {
      await showNotification('Reminder: $bookmarkName', message);
    }
  }
}
