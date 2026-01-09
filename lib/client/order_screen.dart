import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with WidgetsBindingObserver {
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);

  // Controllers
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _deliveryController = TextEditingController();
  final TextEditingController _receiverNameController = TextEditingController();
  final TextEditingController _receiverPhoneController =
      TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  DateTime? _pickupDate;
  TimeOfDay? _pickupTime;
  DateTime? _deliveryDate;
  TimeOfDay? _deliveryTime;

  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isButtonVisible = false;
  bool _isSubmitting = false;
  bool _isPolling = false;

  // Chat State
  Timer? _pollingTimer;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    List<TextEditingController> controllers = [
      _pickupController,
      _deliveryController,
      _receiverNameController,
      _receiverPhoneController,
      _weightController,
      _descriptionController,
    ];
    for (var c in controllers) {
      c.addListener(_validateForm);
    }

    _loadCachedMessages();
    _startAdminReplyListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _pickupController.dispose();
    _deliveryController.dispose();
    _receiverNameController.dispose();
    _receiverPhoneController.dispose();
    _weightController.dispose();
    _descriptionController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- AUTH HELPER ---

  Future<Map<String, String>> _getAuthHeaders() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token =
        prefs.getString('jwt_token') ?? prefs.getString('token');

    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Authorization": "Bearer ${token ?? ''}",
    };
  }

  // --- LOGIC & API ---

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _validateForm() {
    bool isFormValid =
        _pickupController.text.trim().isNotEmpty &&
        _deliveryController.text.trim().isNotEmpty &&
        _receiverNameController.text.trim().isNotEmpty &&
        _receiverPhoneController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        _pickupDate != null &&
        _pickupTime != null &&
        _deliveryDate != null &&
        _deliveryTime != null &&
        _image != null;

    if (isFormValid != _isButtonVisible) {
      setState(() => _isButtonVisible = isFormValid);
    }
  }

  void _clearForm() {
    _pickupController.clear();
    _deliveryController.clear();
    _receiverNameController.clear();
    _receiverPhoneController.clear();
    _weightController.clear();
    _descriptionController.clear();
    setState(() {
      _image = null;
      _pickupDate = null;
      _pickupTime = null;
      _deliveryDate = null;
      _deliveryTime = null;
      _isButtonVisible = false;
    });
  }

  Future<void> _handleOrderSubmission() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');

    if (email == null) {
      _showSnackBar("User session not found. Please log in.", Colors.red);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? base64Image;
      if (_image != null) {
        List<int> imageBytes = await _image!.readAsBytes();
        base64Image = base64Encode(imageBytes);
      }

      final orderPayload = {
        "email": email.trim(),
        "pickupLocation": _pickupController.text.trim(),
        "deliveryLocation": _deliveryController.text.trim(),
        "pickupDate": DateFormat('yyyy-MM-dd').format(_pickupDate!),
        "pickupTime": _pickupTime!.format(context),
        "deliveryDate": DateFormat('yyyy-MM-dd').format(_deliveryDate!),
        "deliveryTime": _deliveryTime!.format(context),
        "receiverName": _receiverNameController.text.trim(),
        "receiverPhone": _receiverPhoneController.text.trim(),
        "weight": _weightController.text.trim().isEmpty
            ? "Not Specified"
            : _weightController.text.trim(),
        "packageDescription": _descriptionController.text.trim(),
        "packageImage": base64Image,
      };

      final headers = await _getAuthHeaders();
      final response = await http
          .post(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/create-order',
            ),
            headers: headers,
            body: jsonEncode(orderPayload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSuccessDialog();
        _clearForm();
        _checkForNewMessages();
      } else {
        _showSnackBar("Submission failed: ${response.statusCode}", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Connection error. Please try again.", Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- CHAT LOGIC ---

  void _startAdminReplyListener() {
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (t) => _checkForNewMessages(),
    );
  }

  Future<void> _checkForNewMessages() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email == null || _isPolling) return;

    _isPolling = true;
    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .get(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/get-messages?email=${email.trim()}',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> newMessages = jsonDecode(response.body);

        if (jsonEncode(newMessages) != jsonEncode(_messages)) {
          if (mounted) {
            setState(() => _messages = newMessages);
            await prefs.setString('chat_cache_${email.trim()}', response.body);
            _scrollToBottom();

            if (newMessages.isNotEmpty && newMessages.last['isAdmin'] == true) {
              _markMessagesAsRead(email.trim());
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Polling error: $e");
    } finally {
      _isPolling = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _markMessagesAsRead(String userEmail) async {
    try {
      final headers = await _getAuthHeaders();
      await http.post(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/mark-read',
        ),
        headers: headers,
        body: jsonEncode({"email": userEmail}),
      );
    } catch (e) {
      debugPrint("Failed to mark as read: $e");
    }
  }

  Future<void> _loadCachedMessages() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    if (email != null) {
      final String? cachedData = prefs.getString('chat_cache_${email.trim()}');
      if (cachedData != null) {
        setState(() => _messages = jsonDecode(cachedData));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
    _checkForNewMessages();
  }

  Future<void> _sendChatMessage({String? base64Image}) async {
    final msg = _chatController.text.trim();
    if (msg.isEmpty && base64Image == null) return;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('userEmail');
    if (email == null) return;

    _chatController.clear();

    final Map<String, dynamic> tempMsg = {
      "text": msg.isEmpty ? "Sent an image/file" : msg,
      "isAdmin": false,
      "status": "sending",
      "packageImage": base64Image,
      "timestamp": DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .post(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/send-message',
            ),
            headers: headers,
            body: jsonEncode({
              "email": email,
              "text": msg,
              "packageImage": base64Image,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _checkForNewMessages();
      } else {
        _handleSendError();
      }
    } catch (_) {
      _handleSendError();
    }
  }

  void _handleSendError() {
    setState(() {
      if (_messages.isNotEmpty) _messages.last['status'] = 'error';
    });
    _showSnackBar("Network failure. Message not sent.", Colors.red);
  }

  // --- UI RENDERING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: goldYellow),
        title: const Text(
          "LOGISTICS PORTAL",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_isPolling && _messages.isEmpty)
            const LinearProgressIndicator(
              backgroundColor: Colors.black,
              color: goldYellow,
              minHeight: 1,
            ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildOrderForm(),
                  const SizedBox(height: 40),
                  const Divider(color: Colors.white10, thickness: 1),
                  const SizedBox(height: 20),
                  _buildSectionHeader("LIVE UPDATES & HISTORY"),
                  const SizedBox(height: 20),
                  if (_messages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        "No messages yet. Logs will appear here.",
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ),
                  ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildChatBubble(_messages[index]),
                  ),
                ],
              ),
            ),
          ),
          _buildChatInput(),
        ],
      ),
    );
  }

  Widget _buildOrderForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("LOGISTICS DETAILS"),
        const SizedBox(height: 15),
        _buildTextField(
          "Pickup Location",
          _pickupController,
          Icons.location_on,
        ),
        _buildScheduleRow("Pickup", _pickupDate, _pickupTime, true),
        _buildTextField(
          "Delivery Location",
          _deliveryController,
          Icons.local_shipping,
        ),
        _buildScheduleRow("Delivery", _deliveryDate, _deliveryTime, false),
        const SizedBox(height: 20),
        _buildSectionHeader("RECEIVER & PACKAGE"),
        const SizedBox(height: 15),
        _buildTextField("Receiver Name", _receiverNameController, Icons.person),
        _buildTextField(
          "Receiver Phone",
          _receiverPhoneController,
          Icons.phone,
          isPhone: true,
        ),
        _buildTextField(
          "Weight (kg) - OPTIONAL",
          _weightController,
          Icons.scale,
          isNumber: true,
        ),
        _buildTextField(
          "Package Description",
          _descriptionController,
          Icons.inventory_2,
        ),
        const SizedBox(height: 15),
        _buildActionOutlineButton(
          label: _image == null ? "UPLOAD PACKAGE IMAGE" : "CHANGE IMAGE",
          icon: Icons.camera_alt,
          onTap: _showImagePickerOptions,
        ),
        if (_image != null) _buildImagePreview(),
        const SizedBox(height: 30),
        if (_isSubmitting)
          const Center(child: CircularProgressIndicator(color: goldYellow))
        else
          GestureDetector(
            onTap: () {
              if (_isButtonVisible) {
                _showOrderSummaryModal();
              } else {
                _showSnackBar(
                  "Please complete all required fields.",
                  Colors.orange,
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: _isButtonVisible ? goldYellow : Colors.white10,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  "CONFIRM & REQUEST RIDER",
                  style: TextStyle(
                    color: _isButtonVisible ? darkBlue : Colors.white24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatBubble(dynamic msg) {
    final bool isAdmin = msg['isAdmin'] ?? false;
    final String text = msg['text'] ?? "";
    final String? imageSource = msg['packageImage'];
    final String status = msg['status'] ?? "sent";
    final String timestampStr =
        msg['timestamp'] ?? DateTime.now().toIso8601String();

    DateTime dt = DateTime.parse(timestampStr).toLocal();
    String displayTime = DateFormat('jm').format(dt);

    bool isOrderNote =
        text.contains("ORDER LOGGED") || text.contains("RIDER ASSIGNED");

    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isAdmin
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isOrderNote
                  ? Colors.green.withOpacity(0.1)
                  : (isAdmin ? darkBlue : Colors.white.withOpacity(0.08)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(15),
                topRight: const Radius.circular(15),
                bottomLeft: Radius.circular(isAdmin ? 0 : 15),
                bottomRight: Radius.circular(isAdmin ? 15 : 0),
              ),
              border: Border.all(
                color: isOrderNote
                    ? Colors.green.withOpacity(0.4)
                    : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (text.isNotEmpty)
                  Text(
                    text,
                    style: TextStyle(
                      color: isOrderNote ? Colors.greenAccent : Colors.white,
                      fontSize: 13,
                    ),
                  ),
                if (imageSource != null && imageSource.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildImageInBubble(imageSource),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayTime,
                  style: const TextStyle(color: Colors.white24, fontSize: 9),
                ),
                if (!isAdmin) ...[
                  const SizedBox(width: 4),
                  _buildStatusIndicator(status),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // UPDATED Status Indicator with Delivered Support
  Widget _buildStatusIndicator(String status) {
    if (status == "sending") {
      return const SizedBox(
        width: 8,
        height: 8,
        child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white24),
      );
    }

    IconData icon;
    Color color = Colors.white24;

    if (status == "read") {
      icon = Icons.done_all_rounded;
      color = goldYellow;
    } else if (status == "delivered") {
      icon = Icons.done_all_rounded;
      color = Colors.white24; // Grey double ticks
    } else {
      icon = Icons.check_rounded; // Sent (Single Tick)
      color = Colors.white24;
    }

    return Icon(icon, size: 13, color: color);
  }

  // UPDATED with split/last logic for Image.memory
  Widget _buildImageInBubble(String source) {
    return InkWell(
      onTap: () => _showImagePreviewModal(source),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: source.startsWith('http')
            ? Image.network(
                source,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Image.memory(
                base64Decode(
                  source.contains(',') ? source.split(',').last : source,
                ),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, color: Colors.white24),
              ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: const BoxDecoration(
        color: darkBlue,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_a_photo_rounded, color: goldYellow),
              onPressed: _pickChatImage,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Type a message...",
                    hintStyle: TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendChatMessage(),
              child: const CircleAvatar(
                backgroundColor: goldYellow,
                radius: 22,
                child: Icon(Icons.send_rounded, color: darkBlue, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isPhone = false,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isPhone
            ? TextInputType.phone
            : (isNumber ? TextInputType.number : TextInputType.text),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          prefixIcon: Icon(icon, color: goldYellow, size: 18),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: goldYellow),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleRow(
    String title,
    DateTime? date,
    TimeOfDay? time,
    bool isPickup,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white10),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () => _selectDate(context, isPickup),
              child: Text(
                date == null
                    ? "Set $title Date"
                    : DateFormat('yMMMd').format(date),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white10),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () => _selectTime(context, isPickup),
              child: Text(
                time == null ? "Set Time" : time.format(context),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: goldYellow, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() => Padding(
    padding: const EdgeInsets.only(top: 15),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        _image!,
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    ),
  );

  Widget _buildSectionHeader(String title) => Text(
    title,
    style: const TextStyle(
      color: goldYellow,
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
    ),
  );

  void _showOrderSummaryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: darkBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "VERIFY LOGISTICS DETAILS",
                style: TextStyle(
                  color: goldYellow,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 25),
              if (_image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.file(
                    _image!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              _buildSummaryRow("Package Content", _descriptionController.text),
              _buildSummaryRow(
                "Weight",
                _weightController.text.isEmpty
                    ? "Not Specified"
                    : "${_weightController.text} kg",
              ),
              _buildSummaryRow("Pickup Location", _pickupController.text),
              _buildSummaryRow(
                "Pickup Schedule",
                "${DateFormat('yMMMd').format(_pickupDate!)} @ ${_pickupTime!.format(context)}",
              ),
              const Divider(color: Colors.white10, height: 30),
              _buildSummaryRow("Delivery Location", _deliveryController.text),
              _buildSummaryRow(
                "Expected Delivery",
                "${DateFormat('yMMMd').format(_deliveryDate!)} @ ${_deliveryTime!.format(context)}",
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldYellow,
                    foregroundColor: darkBlue,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _handleOrderSubmission();
                  },
                  child: const Text(
                    "CONFIRM & REQUEST RIDER",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePreviewModal(String imageSource) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      pageBuilder: (context, _, __) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            child: imageSource.startsWith('http')
                ? Image.network(imageSource, fit: BoxFit.contain)
                : Image.memory(
                    base64Decode(
                      imageSource.contains(',')
                          ? imageSource.split(',').last
                          : imageSource,
                    ),
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isPickup) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      setState(() => isPickup ? _pickupDate = picked : _deliveryDate = picked);
      _validateForm();
    }
  }

  Future<void> _selectTime(BuildContext context, bool isPickup) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => isPickup ? _pickupTime = picked : _deliveryTime = picked);
      _validateForm();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 40,
    );
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
      _validateForm();
    }
  }

  Future<void> _pickChatImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: darkBlue,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: goldYellow),
              title: const Text(
                "Capture from Camera",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final photo = await _picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 40,
                );
                if (photo != null) {
                  _sendChatMessage(
                    base64Image: base64Encode(await photo.readAsBytes()),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: goldYellow),
              title: const Text(
                "Upload from Gallery",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 40,
                );
                if (image != null) {
                  _sendChatMessage(
                    base64Image: base64Encode(await image.readAsBytes()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: goldYellow,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: darkBlue,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera, color: goldYellow),
              title: const Text(
                "Camera",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: goldYellow),
              title: const Text(
                "Gallery",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkBlue,
        title: const Text("Order Logged", style: TextStyle(color: goldYellow)),
        content: const Text(
          "Your rider agent request has been successfully logged. Thanks for choosing Keah Logistics!",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: goldYellow)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
