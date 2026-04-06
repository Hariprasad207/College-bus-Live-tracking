import 'package:flutter/material.dart';
import 'driverlogin.dart';
import 'userscreen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            buildModeButton(context, "Driver Mode"),
            const SizedBox(height: 30),
            buildModeButton(context, "User Mode"),
          ],
        ),
      ),
    );
  }

  Widget buildModeButton(BuildContext context, String mode) {
    return ElevatedButton(
      onPressed: () {
        if (mode == "Driver Mode") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DriverLoginScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UserMapScreen()),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[300],
        foregroundColor: Colors.black,
        minimumSize: const Size(220, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(mode, style: const TextStyle(fontSize: 20)),
    );
  }
}
