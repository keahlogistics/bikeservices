import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

// --- SHARED CONFIG ---
const Color goldYellow = Color(0xFFFFD700);
const Color darkBlue = Color(0xFF0D1B2A);
const Color deepPanelColor = Color(0xFF16213E);
const String baseApiUrl =
    'https://keahlogistics.netlify.app/.netlify/functions/api';

class AdminLiveChatSystem extends StatefulWidget {
  const AdminLiveChatSystem({super.key});

  @override
  State<AdminLiveChatSystem> createState() => _AdminLiveChatSystemState();
}

class _AdminLiveChatSystemState extends State<AdminLiveChatSystem> {
  bool _isViewingChat = false;
  String? _selectedUserEmail;
  String? _selectedUserName;
  String? _selectedUserProfile;

  List<dynamic> _chatThreads = [];
  bool _isLoadingThreads = true;
  bool _isFetchingInbox = false;
  Timer? _inboxTimer;

  @override
  void initState() {
    super.initState();
    _fetchChatThreads();
    _inboxTimer = Timer.periodic(
      const Duration(seconds: 15),
      (t) => _fetchChatThreads(),
    );
  }

  @override
  void dispose() {
    _inboxTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('adminToken') ?? '';
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  Future<void> _fetchChatThreads() async {
    if (_isFetchingInbox) return;
    if (mounted) setState(() => _isFetchingInbox = true);

    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseApiUrl/get-all-messages'), headers: headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        data.sort((a, b) {
          bool aPriority =
              (a['unreadCount'] ?? 0) > 0 ||
              (a['lastMessage'] ?? "").toString().contains("NEW ORDER LOGGED");
          bool bPriority =
              (b['unreadCount'] ?? 0) > 0 ||
              (b['lastMessage'] ?? "").toString().contains("NEW ORDER LOGGED");
          if (aPriority && !bPriority) return -1;
          if (!aPriority && bPriority) return 1;
          return 0;
        });
        setState(() {
          _chatThreads = data;
          _isLoadingThreads = false;
        });
      }
    } catch (e) {
      debugPrint("Inbox Fetch Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingInbox = false;
          _isLoadingThreads = false;
        });
      }
    }
  }

  void _openChat(dynamic thread) {
    setState(() {
      _selectedUserEmail = thread['userEmail'];
      _selectedUserName = thread['userName'] ?? "Customer";
      _selectedUserProfile = thread['profileImage'];
      _isViewingChat = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewingChat && _selectedUserEmail != null) {
      return LiveChatOrderScreen(
        userEmail: _selectedUserEmail!,
        userName: _selectedUserName!,
        profileImage: _selectedUserProfile,
        onBack: () {
          setState(() => _isViewingChat = false);
          _fetchChatThreads();
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: darkBlue,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: goldYellow),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "ADMIN INBOX",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _fetchChatThreads,
            icon: _isFetchingInbox
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: goldYellow,
                    ),
                  )
                : const Icon(Icons.refresh, color: goldYellow),
          ),
        ],
      ),
      body: _isLoadingThreads
          ? const Center(child: CircularProgressIndicator(color: goldYellow))
          : RefreshIndicator(
              color: goldYellow,
              onRefresh: _fetchChatThreads,
              child: _chatThreads.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 200),
                        Center(
                          child: Text(
                            "No active chats",
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: _chatThreads.length,
                      itemBuilder: (context, index) => _buildThreadTile(
                        _chatThreads[index],
                        (_chatThreads[index]['unreadCount'] ?? 0) > 0,
                      ),
                    ),
            ),
    );
  }

  Widget _buildThreadTile(dynamic thread, bool hasUnread) {
    final String? imgUrl = thread['profileImage'];
    final bool isOrder =
        thread['lastMessage']?.toString().contains("📦 NEW ORDER LOGGED") ??
        false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: darkBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOrder
              ? goldYellow
              : (hasUnread ? goldYellow.withOpacity(0.5) : Colors.white10),
        ),
      ),
      child: ListTile(
        onTap: () => _openChat(thread),
        leading: CircleAvatar(
          backgroundColor: Colors.white10,
          backgroundImage: (imgUrl != null && imgUrl.startsWith('http'))
              ? CachedNetworkImageProvider(imgUrl)
              : null,
          child: (imgUrl == null || !imgUrl.startsWith('http'))
              ? const Icon(Icons.person, color: goldYellow)
              : null,
        ),
        title: Text(
          thread['userName'] ?? "User",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          isOrder
              ? "📦 New Order Received"
              : (thread['lastMessage'] ?? "No messages"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isOrder
                ? goldYellow
                : (hasUnread ? Colors.white : Colors.white38),
            fontSize: 12,
          ),
        ),
        trailing: hasUnread
            ? CircleAvatar(
                radius: 10,
                backgroundColor: goldYellow,
                child: Text(
                  "${thread['unreadCount']}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right, color: Colors.white24),
      ),
    );
  }
}

class LiveChatOrderScreen extends StatefulWidget {
  final String userEmail;
  final String userName;
  final String? profileImage;
  final VoidCallback onBack;

  const LiveChatOrderScreen({
    super.key,
    required this.userEmail,
    required this.userName,
    this.profileImage,
    required this.onBack,
  });

  @override
  State<LiveChatOrderScreen> createState() => _LiveChatOrderScreenState();
}

class _LiveChatOrderScreenState extends State<LiveChatOrderScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _deliveryFeeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isFetching = false;

  bool _isMenuExpanded = false;
  bool _showPaymentPanel = false;
  bool _showOrderConfirmPanel = false;
  bool _showRiderPanel = false;

  double _serviceCommission = 0.0;
  double _totalAmount = 0.0;
  Timer? _timer;
  Map<String, dynamic>? _replyingTo;

  List<dynamic> _availableRiders = [];
  List<dynamic> _filteredRiders = [];
  bool _isFetchingRiders = false;

  @override
  void initState() {
    super.initState();
    _fetchChat();
    _timer = Timer.periodic(const Duration(seconds: 5), (t) => _fetchChat());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messageController.dispose();
    _deliveryFeeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _generateTrackingNumber() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return "KEAH${random.substring(random.length - 8)}";
  }

  Future<void> _fetchRiders() async {
    setState(() => _isFetchingRiders = true);
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseApiUrl/get-all-riders'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> riders = jsonDecode(response.body);
        setState(() {
          _availableRiders = riders;
          _filteredRiders = riders;
        });
      }
    } catch (e) {
      debugPrint("Rider Fetch Error: $e");
    } finally {
      setState(() => _isFetchingRiders = false);
    }
  }

  void _filterRiders(String query) {
    setState(() {
      _filteredRiders = _availableRiders
          .where(
            (r) =>
                (r['fullName'] ?? '').toLowerCase().contains(
                  query.toLowerCase(),
                ) ||
                (r['plateNo'] ?? '').toLowerCase().contains(
                  query.toLowerCase(),
                ),
          )
          .toList();
    });
  }

  void _calculateTotal(String value) {
    double fee = double.tryParse(value) ?? 0.0;
    setState(() {
      _serviceCommission = fee * 0.05;
      _totalAmount = fee + _serviceCommission;
    });
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('adminToken') ?? '';
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp == null)
        return DateFormat('hh:mm a').format(DateTime.now());
      DateTime dt = DateTime.parse(timestamp.toString()).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return "";
    }
  }

  Future<void> _fetchChat() async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseApiUrl/get-messages?email=${widget.userEmail}'),
        headers: headers,
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _messages = jsonDecode(response.body);
          _isLoading = false;
        });
        _markAsRead();
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _markAsRead() async {
    try {
      final headers = await _getAuthHeaders();
      await http.post(
        Uri.parse('$baseApiUrl/mark-read'),
        headers: headers,
        body: jsonEncode({"email": widget.userEmail, "isAdminSide": true}),
      );
    } catch (e) {}
  }

  Future<void> _postMessage(String text, {String? imageBase64}) async {
    if (text.trim().isEmpty && imageBase64 == null) return;
    String cleanText = text.trim();
    String finalMsg = _replyingTo != null
        ? "RE: \"${_replyingTo!['text']}\"\n\n$cleanText"
        : cleanText;

    if (imageBase64 == null) _messageController.clear();
    setState(() => _replyingTo = null);

    final String tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final Map<String, dynamic> localMsg = {
      "text": finalMsg,
      "isAdmin": true,
      "isSending": true,
      "status": "sent",
      "timestamp": DateTime.now().toIso8601String(),
      "packageImage": imageBase64 ?? "",
      "localId": tempId,
    };

    setState(() => _messages.add(localMsg));
    _scrollToBottom();

    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseApiUrl/send-message'),
            headers: headers,
            body: jsonEncode({
              "email": widget.userEmail,
              "text": finalMsg,
              "packageImage": imageBase64 ?? "",
            }),
          )
          .timeout(const Duration(seconds: 15));

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m['localId'] == tempId);
          if (index != -1) _messages[index]['isSending'] = false;
        });
      }
    } catch (e) {
      _showErrorSnackBar("Delivery failed.");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 70,
    );
    if (file != null) {
      String base64Image =
          "data:image/jpeg;base64,${base64Encode(await File(file.path).readAsBytes())}";
      _postMessage("Sent an image", imageBase64: base64Image);
    }
  }

  Widget _buildFloatingMenuItem({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: goldYellow,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: darkBlue),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: darkBlue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignRiderPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: darkBlue,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 15)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "ASSIGN LOGISTICS RIDER",
              style: TextStyle(
                color: goldYellow,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Divider(color: Colors.white10),
            TextField(
              onChanged: _filterRiders,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search by Name or Plate...",
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(
                  Icons.search,
                  color: goldYellow,
                  size: 18,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.black26,
              ),
            ),
            const SizedBox(height: 10),
            if (_isFetchingRiders)
              const LinearProgressIndicator(
                color: goldYellow,
                backgroundColor: Colors.transparent,
              )
            else
              Expanded(
                child: _filteredRiders.isEmpty
                    ? const Center(
                        child: Text(
                          "No riders found",
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredRiders.length,
                        itemBuilder: (context, index) {
                          final rider = _filteredRiders[index];
                          final String? riderImg = rider['profileImage'];

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: goldYellow,
                              // Handles both Web URLs and Base64 encoded strings
                              backgroundImage:
                                  (riderImg != null &&
                                      riderImg.startsWith('http'))
                                  ? NetworkImage(riderImg)
                                  : (riderImg != null &&
                                        riderImg.startsWith('data:image'))
                                  ? MemoryImage(
                                      base64Decode(riderImg.split(',').last),
                                    )
                                  : null,
                              child: riderImg == null
                                  ? const Icon(Icons.person, color: darkBlue)
                                  : null,
                            ),
                            title: Text(
                              rider['fullName'] ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "${rider['plateNo'] ?? 'No Plate'} • ${rider['riderType'] ?? 'Rider'}",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: goldYellow,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              onPressed: () {
                                String tracking = _generateTrackingNumber();

                                // UPDATED MESSAGE STYLE
                                String riderMsg =
                                    "🚚 RIDER ASSIGNED SUCCESSFULLY\n\n"
                                    "--- RIDER PROFILE ---\n"
                                    "• Name: ${rider['fullName'] ?? 'N/A'}\n"
                                    "• Gender: ${rider['gender'] ?? 'N/A'}\n"
                                    "• Contact: ${rider['phoneNumber'] ?? 'N/A'}\n"
                                    "• Rider Type: ${rider['riderType'] ?? 'Standard'}\n\n"
                                    "--- RIDER & LEGAL ---\n"
                                    "• License No: ${rider['licenseNo'] ?? 'N/A'}\n"
                                    "• Plate No: ${rider['plateNo'] ?? 'N/A'}\n"
                                    "• Bike Color: ${rider['bikeColor'] ?? 'N/A'}\n\n"
                                    "🆔 TRACKING NUMBER: $tracking\n\n"
                                    "The rider is on their way. Thank you for choosing KEAH LOGISTICS.";

                                // Post message including the profile image
                                _postMessage(
                                  riderMsg,
                                  imageBase64:
                                      (riderImg != null &&
                                          riderImg.startsWith('data:image'))
                                      ? riderImg
                                      : null,
                                );

                                setState(() => _showRiderPanel = false);
                              },
                              child: const Text(
                                "ASSIGN",
                                style: TextStyle(
                                  color: darkBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            TextButton(
              onPressed: () => setState(() => _showRiderPanel = false),
              child: const Text(
                "CLOSE",
                style: TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderConfirmationPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: deepPanelColor,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 15)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "ORDER STATUS UPDATE",
              style: TextStyle(
                color: goldYellow,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Divider(color: Colors.white10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.8),
                    ),
                    onPressed: () {
                      _postMessage(
                        "✅ ORDER ACCEPTED \n\nYOUR DELIVERY FEE IS NOW CONFIRMED. A RIDER WILL BE ASSIGNED TO YOU SHORTLY.",
                      );
                      setState(() => _showOrderConfirmPanel = false);
                    },
                    child: const Text(
                      "CONFIRM ORDER",
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.8),
                    ),
                    onPressed: () {
                      _postMessage(
                        "❌ ORDER CANCELLED\n\nWE ARE UNABLE TO PROCEED DUE TO DELIVERY NOT CONFIRMED.",
                      );
                      setState(() => _showOrderConfirmPanel = false);
                    },
                    child: const Text(
                      "CANCEL ORDER",
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDescriptionPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: deepPanelColor,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 15)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "PAYMENT DESCRIPTION",
              style: TextStyle(
                color: goldYellow,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Divider(color: Colors.white10),
            Row(
              children: [
                const Text(
                  "Delivery Fee: ",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _deliveryFeeController,
                    keyboardType: TextInputType.number,
                    onChanged: _calculateTotal,
                    style: const TextStyle(color: goldYellow, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: "0.00",
                      hintStyle: TextStyle(color: Colors.white24),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            _rowInfo(
              "Service Commission (5%):",
              "₦${_serviceCommission.toStringAsFixed(2)}",
            ),
            _rowInfo(
              "TOTAL AMOUNT:",
              "₦${_totalAmount.toStringAsFixed(2)}",
              isBold: true,
            ),
            const SizedBox(height: 10),
            const Text(
              "Bank: MONIEPOINT MFB\nAcct No: 8149747864\nName: KEAH LOGISTICS",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Center(
              child: TextButton(
                onPressed: () {
                  String summary =
                      "💳 PAYMENT INVOICE\n\n"
                      "• Delivery: ₦${_deliveryFeeController.text}\n"
                      "• TOTAL: ₦${_totalAmount.toStringAsFixed(2)}\n\n"
                      "--- BANK DETAILS ---\n"
                      "Bank: MONIEPOINT MFB\nAcct No: 8149747864\n"
                      "UPLOAD RECEIPT FOR CONFIRMATION.";
                  _postMessage(summary);
                  setState(() => _showPaymentPanel = false);
                },
                child: const Text(
                  "SEND INVOICE",
                  style: TextStyle(
                    color: goldYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowInfo(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: isBold ? goldYellow : Colors.white,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      color: Colors.white.withOpacity(0.05),
      child: Row(
        children: [
          const Icon(Icons.reply, color: goldYellow, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyingTo!['isAdmin'] == true
                      ? "Replying to yourself"
                      : "Replying to ${widget.userName}",
                  style: const TextStyle(
                    color: goldYellow,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _replyingTo!['text'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(dynamic msg) {
    bool isMe = msg['isAdmin'] == true;
    bool isSending = msg['isSending'] ?? false;
    String img = msg['packageImage'] ?? "";
    String status = msg['status'] ?? 'sent';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF262626),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isMe ? 15 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: img.startsWith('http')
                    ? CachedNetworkImage(imageUrl: img)
                    : Image.memory(base64Decode(img.split(',').last)),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              msg['text'],
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimestamp(msg['timestamp']),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                if (isMe) ...[
                  const SizedBox(width: 5),
                  isSending
                      ? const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1,
                            color: goldYellow,
                          ),
                        )
                      : _buildStatusIcon(status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'read':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Colors.lightBlueAccent,
        );
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.white60);
      default:
        return const Icon(Icons.done, size: 16, color: Colors.white38);
    }
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: darkBlue,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () => _pickAndSendImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, color: goldYellow),
            ),
            IconButton(
              onPressed: () => _pickAndSendImage(ImageSource.gallery),
              icon: const Icon(Icons.image, color: goldYellow),
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Type a reply...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: goldYellow,
              child: IconButton(
                icon: const Icon(Icons.send, color: darkBlue),
                onPressed: () => _postMessage(_messageController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: darkBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: goldYellow),
          onPressed: widget.onBack,
        ),
        title: Text(
          widget.userName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: goldYellow),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(15),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return Dismissible(
                            key: Key(msg['timestamp'] + index.toString()),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (_) async {
                              setState(() => _replyingTo = msg);
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(
                                Icons.reply,
                                color: goldYellow,
                                size: 24,
                              ),
                            ),
                            child: _buildChatBubble(msg),
                          );
                        },
                      ),
              ),
              if (_replyingTo != null) _buildReplyPreview(),
              _buildInputSection(),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isMenuExpanded) ...[
                  _buildFloatingMenuItem(
                    label: "Payment Description",
                    icon: Icons.payment,
                    onTap: () => setState(() {
                      _showPaymentPanel = true;
                      _isMenuExpanded = false;
                    }),
                  ),
                  _buildFloatingMenuItem(
                    label: "Order Confirmation",
                    icon: Icons.assignment_turned_in,
                    onTap: () => setState(() {
                      _showOrderConfirmPanel = true;
                      _isMenuExpanded = false;
                    }),
                  ),
                  _buildFloatingMenuItem(
                    label: "Assign Rider",
                    icon: Icons.delivery_dining,
                    onTap: () {
                      setState(() {
                        _showRiderPanel = true;
                        _isMenuExpanded = false;
                      });
                      _fetchRiders();
                    },
                  ),
                ],
                const SizedBox(height: 8),
                FloatingActionButton(
                  backgroundColor: goldYellow,
                  onPressed: () => setState(() {
                    if (_showPaymentPanel ||
                        _showOrderConfirmPanel ||
                        _showRiderPanel) {
                      _showPaymentPanel = _showOrderConfirmPanel =
                          _showRiderPanel = false;
                    } else {
                      _isMenuExpanded = !_isMenuExpanded;
                    }
                  }),
                  child: Icon(
                    (_showPaymentPanel ||
                            _showOrderConfirmPanel ||
                            _showRiderPanel ||
                            _isMenuExpanded)
                        ? Icons.close
                        : Icons.add,
                    color: darkBlue,
                  ),
                ),
              ],
            ),
          ),
          if (_showPaymentPanel) _buildPaymentDescriptionPanel(),
          if (_showOrderConfirmPanel) _buildOrderConfirmationPanel(),
          if (_showRiderPanel) _buildAssignRiderPanel(),
        ],
      ),
    );
  }
}
