import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:keah_logistics/screens/login_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String email;
  final String serverOtp;
  final Map<String, dynamic> userData;

  const VerificationScreen({
    super.key,
    required this.email,
    required this.serverOtp,
    required this.userData,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  late String _currentServerOtp;

  Timer? _timer;
  int _start = 30;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _currentServerOtp = widget.serverOtp.toString();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_timer != null) _timer!.cancel();
    setState(() {
      _start = 30;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start == 0) {
        setState(() {
          _timer?.cancel();
          _canResend = true;
        });
      } else {
        setState(() => _start--);
      }
    });
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    setState(() => _isResending = true);
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/resend-otp',
            ),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": widget.email,
              "fullName": widget.userData["fullName"],
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() => _currentServerOtp = data['otpCode'].toString());
        _showSnackBar("A new code has been sent!", isError: false);
        _startTimer();
      } else {
        _showSnackBar(data['error'] ?? "Failed to resend code");
      }
    } catch (e) {
      _showSnackBar("Connection timeout. Try again.");
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _verifyOtp() async {
    final enteredOtp = _otpController.text.trim();

    if (enteredOtp.length < 6) {
      _showSnackBar("Please enter the full 6-digit code");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/verify-otp',
            ),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": widget.email,
              "otp": enteredOtp,
              "serverOtp": _currentServerOtp,
              "userData": widget.userData,
            }),
          )
          .timeout(const Duration(seconds: 25));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (!mounted) return;

        // --- SUCCESS DIALOG ---
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text("Success!"),
            content: const Text(
              "Your account has been verified. Please log in to continue.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Redirect to Login instead of Home
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text(
                  "GO TO LOGIN",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      } else {
        _showSnackBar(data['error'] ?? "Verification failed. Incorrect code?");
      }
    } catch (e) {
      _showSnackBar("Server taking too long. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                children: [
                  const Icon(
                    Icons.mark_email_read_rounded,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Verify Email",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Enter the 6-digit code sent to",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  Text(
                    widget.email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Wrong email? Change it",
                      style: TextStyle(color: Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      letterSpacing: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      hintText: "000000",
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        letterSpacing: 15,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _isLoading
                      ? const Column(
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 10),
                            Text(
                              "Finalizing your account...",
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E3C72),
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _verifyOtp,
                          child: const Text(
                            "VERIFY & CONTINUE",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                  const SizedBox(height: 25),
                  if (_isResending)
                    const CircularProgressIndicator(color: Colors.white70)
                  else
                    TextButton(
                      onPressed: _canResend ? _resendOtp : null,
                      child: Text(
                        _canResend
                            ? "Resend Verification Code"
                            : "Resend code in ${_start}s",
                        style: TextStyle(
                          color: _canResend ? Colors.white : Colors.white30,
                          fontWeight: _canResend
                              ? FontWeight.bold
                              : FontWeight.normal,
                          decoration: _canResend
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
