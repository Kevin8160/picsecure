import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:picsecure/services/auth_service.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isCodeSent = false;
  bool _isLoading = false;
  String _statusMessage = "";

  void _verifyPhone() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Sending OTP...";
    });

    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) {
      // Simple fix for India/General if user forgets country code, but better to enforce valid input
      phone = "+91$phone";
    }

    await _authService.verifyPhone(
      phone,
      onCodeSent: (verificationId) {
        setState(() {
          _isCodeSent = true;
          _isLoading = false;
          _statusMessage = "OTP Sent to $phone";
        });
      },
      onVerificationFailed: (e) {
        setState(() {
          _isLoading = false;
          _statusMessage = "Failed: ${e.message}";
        });
        Get.snackbar("Error", e.message ?? "Verification Failed");
      },
    );
  }

  void _signIn() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Verifying OTP...";
    });

    try {
      await _authService.signIn(_otpController.text.trim());

      final isSetup = await _authService.isUserSetup();
      if (isSetup) {
        Get.offAllNamed('/home');
      } else {
        Get.offAllNamed('/face-setup');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Error: $e";
      });
      Get.snackbar("Error", "Invalid Code");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "PicSecure Identity",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 40),
            if (!_isCodeSent) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone Number (e.g., +919876543210)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyPhone,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("Send Verification Code"),
              ),
            ] else ...[
              Text(
                "Enter OTP sent to ${_phoneController.text}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: "000000",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("Verify & Login"),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ),
      ),
    );
  }
}
