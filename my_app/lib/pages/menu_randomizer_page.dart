import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'shake_page.dart';

class MenuRandomizerPage extends StatefulWidget {
  const MenuRandomizerPage({super.key});

  @override
  State<MenuRandomizerPage> createState() => _MenuRandomizerPageState();
}

class _MenuRandomizerPageState extends State<MenuRandomizerPage> {
  Map<String, dynamic>? mealData;
  bool isLoading = false;

  Future<void> getRandomMeal() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('https://www.themealdb.com/api/json/v1/1/random.php'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          mealData = data['meals'][0];
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    getRandomMeal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เมนูตามดวงชะตา'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : mealData == null
                ? const Text('ดึงข้อมูลล้มเหลว ลองใหม่อีกครั้ง')
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            mealData!['strMealThumb'],
                            height: 200,
                            width: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          mealData!['strMeal'],
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text('Category: ${mealData!['strCategory']}'),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: getRandomMeal,
                          child: const Text('สุ่มเมนูใหม่'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ShakePage(mealName: mealData!['strMeal']),
                              ),
                            );
                          },
                          icon: const Icon(Icons.vibration),
                          label: const Text('ตกลง! ไปเขย่าหาร้าน'),
                        )
                      ],
                    ),
                  ),
      ),
    );
  }
}