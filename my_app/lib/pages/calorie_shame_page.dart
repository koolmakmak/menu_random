import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'menu_randomizer_page.dart';

class CalorieShamePage extends StatelessWidget {
  const CalorieShamePage({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติความน่าละอาย'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .collection('meals')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีประวัติการกิน'));
          }

          var docs = snapshot.data!.docs;
          int totalCalories = docs.length * 650;

          return Column(
            children: [
              Container(
                color: Colors.red.shade100,
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'สถิติรวม: กินไปแล้ว ${docs.length} มื้อ',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'พลังงานสะสมประมาณ ~$totalCalories kcal! (ไม่อ้วนแน่นะวิ?)',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.fastfood, color: Colors.deepOrange),
                      title: Text(data['mealName'] ?? 'ไม่ทราบชื่อเมนู'),
                      subtitle: Text(
                        'Lat: ${data['latitude']?.toStringAsFixed(2)}, Long: ${data['longitude']?.toStringAsFixed(2)}',
                      ),
                      trailing: const Text(
                        '+650 kcal',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const MenuRandomizerPage()),
                    );
                  },
                  child: const Text('สุ่มกินใหม่อีกมื้อ'),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}