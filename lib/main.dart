import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'services/location_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNotifications();

  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // set to false in production
    );

    await Workmanager().registerPeriodicTask(
      "reminder_check_task",
      "checkLocationProximity",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  runApp(const SmartMapApp());
}

class SmartMapApp extends StatelessWidget {
  const SmartMapApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartMap Navigator',
      theme: ThemeData.light(),
      debugShowCheckedModeBanner: false, // Disable the debug banner
      home: const LoginScreen(),
    );
  }
}
