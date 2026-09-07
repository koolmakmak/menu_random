import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../services/nearby_places_service.dart';
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
  int _cameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _listenAccelerometer();
  }

  void _initCamera() async {
    if (cameras.isNotEmpty) {
      // ตั้งค่าเริ่มต้นเป็นกล้องหน้า
      int frontIdx = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _cameraIndex = frontIdx >= 0 ? frontIdx : 0;
      cameraController = CameraController(cameras[_cameraIndex], ResolutionPreset.medium);
      await cameraController?.initialize();
      if (mounted) setState(() {});
    }
  }

  // สลับกล้องหน้า/หลัง
  Future<void> _switchCamera() async {
    if (cameras.length < 2 || isSaving) return;
    await cameraController?.dispose();
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    cameraController = CameraController(cameras[_cameraIndex], ResolutionPreset.medium);
    try {
      await cameraController?.initialize();
    } catch (e) {
      debugPrint("Switch camera error: $e");
    }
    if (mounted) setState(() {});
  }

  void _listenAccelerometer() {
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gForce = (event.x * event.x + event.y * event.y + event.z * event.z) / 100;
      if (gForce > 2.5 && !isSaving) {
        _accelSubscription?.pause();
        _onShakeSuccess();
      } else if (gForce > 1.5 && !isSaving) {
        // เขย่าเบาไป - แซวผู้ใช้ (มากกว่าแรงโน้มถ่วงตอนนิ่ง ~0.96)
        if (statusMessage != "เขย่าแรงกว่านี้หน่อย ข้าวไม่ได้ลอยมาเอง! 😤") {
          setState(() {
            statusMessage = "เขย่าแรงกว่านี้หน่อย ข้าวไม่ได้ลอยมาเอง! 😤";
          });
        }
      }
    });
  }

  Future<void> _onShakeSuccess() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
      statusMessage = "หาร้านใกล้ตัว & ภาพหน้าคนหิว...";
    });

    double lat = 13.7563;
    double lng = 100.5018;
    bool gpsOk = false;

    // 1. ลองดึง GPS (ถ้าดึงไม่ได้ให้ข้ามไปเลย ไม่ต้องค้าง)
    try {
      // ขอสิทธิ์ตำแหน่งก่อน (Android ต้องขอตอนรันไทม์)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint("GPS: ไม่ได้รับสิทธิ์ตำแหน่ง");
      } else {
        // ใช้พิกัดล่าสุดก่อน (เร็ว) ถ้าไม่มีค่อยรอ GPS ใหม่
        Position? last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          lat = last.latitude;
          lng = last.longitude;
          gpsOk = true;
        } else {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          ).timeout(const Duration(seconds: 10));
          lat = position.latitude;
          lng = position.longitude;
          gpsOk = true;
        }
      }
    } catch (e) {
      debugPrint("GPS Timeout/Error: $e");
    }

    debugPrint('GPS: lat=$lat, lng=$lng');

    // 2. ถ้าไม่มี GPS ให้แจ้งผู้ใช้
    if (!gpsOk && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('📍 ไม่พบสัญญาณ GPS'),
          content: const Text(
              'ไม่สามารถหาตำแหน่งได้ (อาจไม่ได้เปิด GPS หรือไม่ให้สิทธิ์ตำแหน่ง)\n\nจะใช้พิกัดเริ่มต้น (กรุงเทพฯ) ต่อไหม?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ลองใหม่'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ใช้พิกัดเริ่มต้น'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        // ลองใหม่
        isSaving = false;
        if (mounted) {
          setState(() => statusMessage = "เขย่าเครื่องแรงๆ เพื่อสุ่มหาร้าน!");
          _accelSubscription?.resume();
        }
        return;
      }
    }

    NearbyShop? chosen;
    try {
      // 2. ค้นหาร้านจริงใกล้ตำแหน่งผู้ใช้ (Geoapify)
      final shops = await NearbyPlacesService.searchNearbyRestaurants(
        lat: lat,
        lng: lng,
      );
      debugPrint('Found ${shops.length} shops');

      if (shops.isNotEmpty) {
        if (mounted) {
          setState(() => statusMessage = "พบ ${shops.length} ร้านใกล้ตัว! เลือกได้เลย");
        }
        chosen = await _showShopPicker(shops);
      } else {
        // ไม่พบร้านจริง - ยังบันทึกเมนูได้ (กินที่บ้าน/ไม่ระบุร้าน)
        if (mounted) {
          setState(() => statusMessage = "ไม่พบร้านใกล้ตัว แต่บันทึกเมนูนี้ได้เลย");
        }
        chosen = await _showNoShopConfirm(lat, lng);
      }
    } catch (e) {
      debugPrint("Shake handler error: $e");
    } finally {
      isSaving = false;
    }

    if (!mounted) return;

    if (chosen == null) {
      // เขย่าใหม่ - เริ่มนับใหม่
      setState(() => statusMessage = "เขย่าเครื่องแรงๆ เพื่อสุ่มหาร้าน!");
      _accelSubscription?.resume();
      return;
    }

    setState(() => statusMessage = "กำลังบันทึกข้อมูล...");
    final photoPath = await _capturePhoto();
    await _saveMeal(chosen.lat, chosen.lng, chosen.name, photoPath);
  }

  // ประเมินแคลอรี่จากชื่อเมนู (TheMealDB ไม่มีข้อมูลแคลอรี่จริง)
  int _estimateCalories(String mealName) {
    int sum = 0;
    for (final code in mealName.runes) {
      sum += code;
    }
    // ได้ค่าเสถียรต่อเมนู อยู่ในช่วง ~350-950 kcal
    return 350 + (sum % 600);
  }

  // ถ่ายภาพจานว่างตอนเขย่า แล้วบันทึกไว้ในเครื่อง
  Future<String?> _capturePhoto() async {
    try {
      if (cameraController != null && cameraController!.value.isInitialized) {
        final XFile file = await cameraController!.takePicture();
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destPath = '${dir.path}/$fileName';
        await File(file.path).copy(destPath);
        return destPath;
      }
    } catch (e) {
      debugPrint("Capture photo error: $e");
    }
    return null;
  }

  // แสดงรายชื่อร้านจริงให้เลือก
  Future<NearbyShop?> _showShopPicker(List<NearbyShop> shops) {
    return showDialog<NearbyShop>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text('🍽️ ร้านใกล้ตัว'),
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in shops)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(s.address, style: Theme.of(context).textTheme.bodySmall),
                          if (s.rating > 0)
                            Text('⭐ ${s.rating.toStringAsFixed(1)}', style: const TextStyle(color: Colors.orange)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('เขย่าใหม่'),
          ),
        ],
      ),
    );
  }

  // ไม่พบร้านจริง - ยังให้บันทึกเมนูได้
  Future<NearbyShop?> _showNoShopConfirm(double lat, double lng) {
    return showDialog<NearbyShop>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🍽️ ไม่พบร้านใกล้ตัว'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ไม่พบร้านอาหารใกล้ตำแหน่งนี้ (อาจไม่มีข้อมูลในแผนที่)'),
            const SizedBox(height: 8),
            Text('เมนูที่สุ่มได้: ${widget.mealName}'),
            const SizedBox(height: 8),
            const Text('คุณยังบันทึกเมนูนี้ได้'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('เขย่าใหม่'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
                context,
                NearbyShop(
                  name: 'ไม่ระบุร้าน',
                  address: '-',
                  rating: 0,
                  lat: lat,
                  lng: lng,
                )),
            child: const Text('บันทึกเมนูนี้เลย'),
          ),
        ],
      ),
    );
  }

  // บันทึกเมนู + ร้านลง Firestore แล้วไปหน้า Calorie Shame
  Future<void> _saveMeal(double lat, double lng, String shopName, String? photoPath) async {
    setState(() => statusMessage = "กำลังบันทึกข้อมูล...");
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meals')
            .add({
          'mealName': widget.mealName,
          'shopName': shopName,
          'latitude': lat,
          'longitude': lng,
          'photoPath': photoPath,
          'timestamp': FieldValue.serverTimestamp(),
          'calories': _estimateCalories(widget.mealName),
        }).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      debugPrint("Firestore Save Error: $e");
    }

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
        title: const Text('ส่องหน้าคนหิว & เขย่า'),
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
                    if (cameras.length >= 2) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: isSaving ? null : _switchCamera,
                        icon: const Icon(Icons.cameraswitch),
                        label: const Text('สลับกล้องหน้า/หลัง'),
                      ),
                    ],
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