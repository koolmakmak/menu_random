import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'menu_randomizer_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  // 1. ล็อกอินด้วย Email & Password
  Future<void> loginWithEmail() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอก Email และ Password')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _navigateToNextPage();
    } on FirebaseAuthException catch (e) {
      // ถ้าไม่มีบัญชีหรือข้อมูลผิด ให้สมัครอัตโนมัติ
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        _registerUser();
      } else {
        _showError(e.message ?? 'เกิดข้อผิดพลาด');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. สมัครสมาชิกอัตโนมัติหากไม่พบบัญชี
  Future<void> _registerUser() async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _navigateToNextPage();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showError('มีบัญชีนี้แล้ว กรุณากรอกรหัสผ่านให้ถูกต้อง');
      } else {
        _showError('สมัครสมาชิกไม่สำเร็จ: ${e.message}');
      }
    } catch (e) {
      _showError('สมัครสมาชิกไม่สำเร็จ: $e');
    }
  }

  // 3. ล็อกอินแบบ Anonymous (ปุ่มสำรอง)
  Future<void> loginAsGuest() async {
    setState(() => isLoading = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      _navigateToNextPage();
    } catch (e) {
      _showError('Guest Login Error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _navigateToNextPage() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MenuRandomizerPage()),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.restaurant_menu, size: 80, color: Colors.deepOrange),
              const SizedBox(height: 10),
              const Text(
                'CheapShaker',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.deepOrange),
              ),
              const Text('เข้าสู่ระบบเพื่อสุ่มเมนูตามดวงชะตา'),
              const SizedBox(height: 30),
              
              // ช่องกรอก Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email ผู้หิวโหย',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              
              // ช่องกรอก Password
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        // ปุ่ม Login ด้วย Email
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: loginWithEmail,
                            child: const Text('เข้าสู่ระบบ / สมัครสมาชิก'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        
                        // ปุ่ม Login แบบ Guest
                        TextButton(
                          onPressed: loginAsGuest,
                          child: const Text('เข้าใช้งานแบบไม่ลงทะเบียน (Guest)'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}