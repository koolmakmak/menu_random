import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import 'calorie_shame_page.dart';

class ShakePage extends StatefulWidget {
  final String mealName;
  const ShakePage({super.key, required this.mealName});

  @override
  State<ShakePage> createState() => _ShakePageState();
}

class _ShakePageState extends State<ShakePage> {
  CameraController? cameraController;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  String statusMessage = "เขย่าเครื่องแรงๆ เพื่อสุ่มหาร้าน!";
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _listenAccelerometer();
  }

  void _initCamera() async {
    if (cameras.isNotEmpty) {
      cameraController = CameraController(cameras[0], ResolutionPreset.medium);
      await cameraController?.initialize();
      if (mounted) setState(() {});
    }
  }

  void _listenAccelerometer() {
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gForce = (event.x * event.x + event.y * event.y + event.z * event.z) / 100;
      if (gForce > 2.5 && !isSaving) {
        _accelSubscription?.pause();
        _onShakeSuccess();
      }
    });
  }

  Future<void> _onShakeSuccess() async {
    if (isSaving) return;
    
    setState(() {
      isSaving = true;
      statusMessage = "กำลังบันทึกข้อมูล...";
    });

    double lat = 13.7563;
    double lng = 100.5018;

    // 1. ลองดึง GPS (ถ้าดึงไม่ได้ให้ข้ามไปเลย ไม่ต้องค้าง)
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 2));
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      debugPrint("GPS Timeout/Error: $e");
    }

    // 2. บันทึกลง Firestore (ถ้าค้างเกิน 3 วิ จะข้ามไปหน้าถัดไปทันที)
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meals')
            .add({
          'mealName': widget.mealName,
          'latitude': lat,
          'longitude': lng,
          'timestamp': FieldValue.serverTimestamp(),
          'calories': 650,
        }).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      debugPrint("Firestore Save Error: $e");
    }

    // 3. ย้ายไปหน้า Calorie Shame ทันที ไม่ว่า Firestore จะบันทึกสำเร็จหรือไม่
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CalorieShamePage()),
      );
    }
  }

  @override
  void dispose() {
    cameraController?.dispose();
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ส่องจานว่าง & เขย่า'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          cameraController != null && cameraController!.value.isInitialized
              ? CameraPreview(cameraController!)
              : Container(
                  color: Colors.black12,
                  child: const Center(child: Text('โหมดจำลองกล้อง (บนคอมพิวเตอร์)')),
                ),
          
          Positioned(
            top: 30,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.white.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text('🖥️ แผงควบคุมการทดสอบบนคอมพิวเตอร์', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                      ),
                      onPressed: isSaving ? null : _onShakeSuccess,
                      icon: const Icon(Icons.vibration),
                      label: const Text('จำลองการเขย่า (Simulate Shake)'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              child: Text(
                statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          )
        ],
      ),
    );
  }
}