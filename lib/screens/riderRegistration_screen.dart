import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class RiderRegistrationScreen extends StatefulWidget {
  const RiderRegistrationScreen({super.key});

  @override
  State<RiderRegistrationScreen> createState() =>
      _RiderRegistrationScreenState();
}

class _RiderRegistrationScreenState extends State<RiderRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // --- FILES ---
  File? _profileImage;
  File? _bikeFrontImage;
  File? _bikeBackImage;
  File? _verificationVideo;
  File? _utilityBillImage;

  // --- CONTROLLERS ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _bikeColorController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _ninController = TextEditingController();

  final TextEditingController _gNameController = TextEditingController();
  final TextEditingController _gPhoneController = TextEditingController();

  static const Color goldYellow = Color(0xFFFFD700);
  static const Color navyDark = Color(0xFF0D1B2A);

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasAgreedToTerms = false; // Consent State

  // --- HELPER METHODS ---

  Future<void> _pickFile(String type) async {
    XFile? picked;
    if (type == 'video') {
      picked = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 15),
      );
    } else {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
    }

    if (picked != null) {
      setState(() {
        if (type == 'profile') _profileImage = File(picked!.path);
        if (type == 'front') _bikeFrontImage = File(picked!.path);
        if (type == 'back') _bikeBackImage = File(picked!.path);
        if (type == 'video') _verificationVideo = File(picked!.path);
        if (type == 'bill') _utilityBillImage = File(picked!.path);
      });
    }
  }

  Future<String> _toBase64(File? file) async {
    if (file == null) return "";
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  Future<void> _handleSendOTP() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter email first")));
      return;
    }
    setState(() => _isLoading = true);
    // Simulating API call
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("OTP Sent to Email")));
  }

  void _showTermsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: navyDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: goldYellow,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "TERMS & AGREEMENT",
              style: TextStyle(
                color: goldYellow,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            const Expanded(
              child: SingleChildScrollView(
                child: Text(
                  "1. Identity Verification: You agree to provide valid government identification (NIN) and a live video for background checks.\n\n"
                  "2. Asset Management: Riders must maintain their bikes in safe working conditions. KEAH Logistics is not liable for personal vehicle maintenance.\n\n"
                  "3. Code of Conduct: You agree to represent KEAH Logistics professionally. Any form of harassment or theft will lead to immediate termination.\n\n"
                  "4. Data Usage: We use your data strictly for verification and operational purposes. We do not sell your data to third parties.\n\n"
                  "5. Payment Terms: Payout schedules and commission structures are subject to the Rider Handbook agreement.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: goldYellow,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CLOSE",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCreateRider() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasAgreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must agree to the Terms & Conditions"),
        ),
      );
      return;
    }
    if (_profileImage == null ||
        _bikeFrontImage == null ||
        _verificationVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing required media verification")),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final body = {
        "fullName": _nameController.text.trim(),
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
        "password": _passwordController.text.trim(),
        "images": {
          "profile": await _toBase64(_profileImage),
          "bikeFront": await _toBase64(_bikeFrontImage),
          "bikeBack": await _toBase64(_bikeBackImage),
          "utilityBill": await _toBase64(_utilityBillImage),
        },
        "videoVerification": await _toBase64(_verificationVideo),
        "kyc": {
          "nin": _ninController.text.trim(),
          "guarantorName": _gNameController.text.trim(),
          "guarantorPhone": _gPhoneController.text.trim(),
        },
        "bikeDetails": {
          "plate": _plateController.text.trim(),
          "color": _bikeColorController.text.trim(),
          "license": _licenseController.text.trim(),
        },
      };

      final response = await http.post(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/create-rider',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: navyDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Icon(
              Icons.hourglass_empty,
              color: goldYellow,
              size: 50,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "APPLICATION UNDER REVIEW",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: goldYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  "Your documents and video verification have been submitted successfully.\n\n"
                  "Please note that approval takes 3 to 7 business working days as our team manually verifies your identity and assets.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: goldYellow),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "I UNDERSTAND",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Registration Failed")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error. Please try again.")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "RIDER ONBOARDING",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: navyDark,
        iconTheme: const IconThemeData(color: goldYellow),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Photo
              Center(
                child: GestureDetector(
                  onTap: () => _pickFile('profile'),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: navyDark,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : null,
                    child: _profileImage == null
                        ? const Icon(
                            Icons.camera_alt,
                            color: goldYellow,
                            size: 30,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _buildSectionTitle("PERSONAL INFORMATION"),
              _buildField(_nameController, "Full Name", Icons.person),

              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _emailController,
                      "Email Address",
                      Icons.email,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: TextButton(
                      onPressed: _handleSendOTP,
                      child: const Text(
                        "SEND OTP",
                        style: TextStyle(
                          color: goldYellow,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _buildField(
                _otpController,
                "Verification Code",
                Icons.verified_user,
              ),
              _buildField(
                _phoneController,
                "Phone Number",
                Icons.phone,
                type: TextInputType.phone,
              ),

              _buildSectionTitle("IDENTITY & KYC"),
              _buildField(
                _ninController,
                "NIN (National Identity Number)",
                Icons.fingerprint,
                type: TextInputType.number,
              ),
              _buildField(_gNameController, "Guarantor Name", Icons.person_pin),
              _buildField(
                _gPhoneController,
                "Guarantor Phone",
                Icons.phone_android,
                type: TextInputType.phone,
              ),
              _buildUploadTile(
                "Residential Proof (Utility Bill)",
                _utilityBillImage != null,
                () => _pickFile('bill'),
              ),

              _buildSectionTitle("BIKE & VISUAL VERIFICATION"),
              Row(
                children: [
                  Expanded(
                    child: _buildUploadTile(
                      "Bike Front",
                      _bikeFrontImage != null,
                      () => _pickFile('front'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildUploadTile(
                      "Bike Back",
                      _bikeBackImage != null,
                      () => _pickFile('back'),
                    ),
                  ),
                ],
              ),
              _buildUploadTile(
                "15s Face & ID Verification Video",
                _verificationVideo != null,
                () => _pickFile('video'),
                icon: Icons.videocam,
              ),

              _buildSectionTitle("SECURITY"),
              _buildField(
                _passwordController,
                "Create Rider Password",
                Icons.lock_outline,
                isSecure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: goldYellow,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),

              const SizedBox(height: 20),

              // --- CONSENT SECTION ---
              _buildConsentSection(),

              const SizedBox(height: 30),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: goldYellow),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasAgreedToTerms
                            ? goldYellow
                            : Colors.grey,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _handleCreateRider,
                      child: const Text(
                        "SUBMIT REGISTRATION",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentSection() {
    return Row(
      children: [
        Checkbox(
          value: _hasAgreedToTerms,
          activeColor: goldYellow,
          checkColor: Colors.black,
          side: const BorderSide(color: goldYellow),
          onChanged: (val) => setState(() => _hasAgreedToTerms = val ?? false),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _showTermsModal,
            child: RichText(
              text: const TextSpan(
                text: "I agree to the ",
                style: TextStyle(color: Colors.white70, fontSize: 12),
                children: [
                  TextSpan(
                    text: "KEAH Logistics Terms & Conditions",
                    style: TextStyle(
                      color: goldYellow,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Text(
        title,
        style: const TextStyle(
          color: goldYellow,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildUploadTile(
    String label,
    bool isDone,
    VoidCallback onTap, {
    IconData icon = Icons.image,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDone ? Colors.green : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDone ? Colors.green : goldYellow, size: 20),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (isDone)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool isSecure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: isSecure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          prefixIcon: Icon(icon, color: goldYellow, size: 18),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: goldYellow),
          ),
        ),
        validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
      ),
    );
  }
}
