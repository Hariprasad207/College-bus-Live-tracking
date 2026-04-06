import 'package:driver_side/firebase_options.dart';
import 'package:driver_side/roleselection.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

// ------------------- APP ROOT -------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Tracker',
      debugShowCheckedModeBanner: false,
      home: const RoleSelectionScreen(),
    );
  }
}
