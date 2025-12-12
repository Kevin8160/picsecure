import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:picsecure/modules/auth/login_view.dart';
import 'package:picsecure/modules/friends/friends_view.dart';
import 'package:picsecure/modules/home/suggestions_view.dart';
import 'package:picsecure/modules/settings/settings_view.dart';
import 'package:picsecure/modules/friends/friend_detail_view.dart';
import 'package:picsecure/modules/onboarding/face_setup_view.dart';
import 'package:picsecure/services/encryption_service.dart';
import 'package:picsecure/services/face_ml_service.dart';
import 'package:picsecure/services/friend_service.dart';
import 'package:picsecure/services/gallery_service.dart';
import 'package:picsecure/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("Firebase Init Error: $e");
  }

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize Services
  try {
    await EncryptionService().init();
    await GalleryService().init();
    await FaceMLService().init();
    await FriendService().init();
  } catch (e) {
    print("Service Init Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final initialRoute = user != null ? '/home' : '/login';

    return GetMaterialApp(
      title: 'PicSecure',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
        fontFamily: 'Roboto', // Modern look
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: '/login', page: () => const LoginView()),
        GetPage(name: '/face-setup', page: () => const FaceSetupView()),
        GetPage(name: '/home', page: () => const SuggestionsView()),
        GetPage(name: '/friends', page: () => const FriendsView()),
        GetPage(name: '/settings', page: () => const SettingsView()),
        GetPage(name: '/friend-detail', page: () => const FriendDetailView()),
        // Add Upload/Download routes if needed as separate pages
      ],
    );
  }
}
