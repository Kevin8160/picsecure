import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:picsecure/services/auth_service.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          const ListTile(
            title: Text(
              "Security",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.face_retouching_natural,
              color: Colors.orange,
            ),
            title: const Text("Reset Face Identity"),
            subtitle: const Text(
              "Fixes 'Security Mismatch' errors after reinstall",
            ),
            onTap: () {
              // Confirm Dialog
              Get.defaultDialog(
                title: "Reset Identity?",
                middleText:
                    "This will overwrite your existing face data on the server with a new encryption key. Only do this if you cannot add friends due to key mismatch.",
                textConfirm: "Reset",
                textCancel: "Cancel",
                confirmTextColor: Colors.white,
                onConfirm: () {
                  Get.back(); // Close Dialog
                  Get.toNamed('/face-setup');
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout"),
            onTap: () async {
              await AuthService().signOut();
              Get.offAllNamed('/login');
            },
          ),
        ],
      ),
    );
  }
}
