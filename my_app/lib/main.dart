import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';

// 1. Import ไฟล์ firebase_options.dart เข้ามา
import 'firebase_options.dart'; 

// Import หน้าแรกของคุณ (ตัวอย่างคือ login_page.dart)
import 'pages/login_page.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. ส่งค่า DefaultFirebaseOptions เข้าไปด้วยแบบนี้
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Camera init error: $e");
  }

  runApp(const CheapShakerApp());
}

class CheapShakerApp extends StatelessWidget {
  const CheapShakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheapShaker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}