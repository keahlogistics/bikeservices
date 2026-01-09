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

  double _serviceCommission = 0.0;
  double _totalAmount = 0.0;
  Timer? _timer;
  Map<String, dynamic>? _replyingTo;

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
      if (timestamp == null) {
        return DateFormat('hh:mm a').format(DateTime.now());
      }
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
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _messages = data;
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

          // --- FLOATING ACTIONS ---
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isMenuExpanded) ...[
                  // Payment Button
                  _buildFloatingMenuItem(
                    label: "Payment Description",
                    icon: Icons.payment,
                    onTap: () {
                      setState(() {
                        _showPaymentPanel = true;
                        _showOrderConfirmPanel = false;
                        _isMenuExpanded = false;
                      });
                    },
                  ),
                  // Order Confirmation Button
                  _buildFloatingMenuItem(
                    label: "Order Confirmation",
                    icon: Icons.assignment_turned_in,
                    onTap: () {
                      setState(() {
                        _showOrderConfirmPanel = true;
                        _showPaymentPanel = false;
                        _isMenuExpanded = false;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    backgroundColor: goldYellow,
                    elevation: 4,
                    onPressed: () {
                      setState(() {
                        if (_showPaymentPanel || _showOrderConfirmPanel) {
                          _showPaymentPanel = false;
                          _showOrderConfirmPanel = false;
                        } else {
                          _isMenuExpanded = !_isMenuExpanded;
                        }
                      });
                    },
                    child: Icon(
                      (_showPaymentPanel ||
                              _showOrderConfirmPanel ||
                              _isMenuExpanded)
                          ? Icons.close
                          : Icons.add,
                      color: darkBlue,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showPaymentPanel) _buildPaymentDescriptionPanel(),
          if (_showOrderConfirmPanel) _buildOrderConfirmationPanel(),
        ],
      ),
    );
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
          boxShadow: [
            BoxShadow(color: Colors.black87, blurRadius: 15, spreadRadius: 2),
          ],
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      _postMessage(
                        "✅ ORDER ACCEPTED \n\nYOUR DELIVERY FEE IS NOW CONFIRMED. A RIDER WILL BE ASSIGNED TO YOU SHORTLY TO PROCEED WITH YOUR ORDER. THANKS FOR CHOOSING KEAH LOGISTICS.",
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      _postMessage(
                        "❌ ORDER CANCELLED\n\nWE ARE UNABLE TO PROCEED WITH THE ORDER DUE TO DELIVERY NOT CONFIRMED.",
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: deepPanelColor,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black87, blurRadius: 15, spreadRadius: 2),
          ],
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
            const SizedBox(height: 8),
            _rowInfo(
              "Service Commission (5%):",
              "₦${_serviceCommission.toStringAsFixed(2)}",
            ),
            _rowInfo(
              "TOTAL AMOUNT:",
              "₦${_totalAmount.toStringAsFixed(2)}",
              isBold: true,
            ),
            const SizedBox(height: 15),
            const Text(
              "BANK DETAILS",
              style: TextStyle(
                color: goldYellow,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              "Bank: MONIEPOINT MFB",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const Text(
              "Acct No: 8149747864",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const Text(
              "Name: KEAH LOGISTICS",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                "ONCE YOU MAKE THE PAYMENT TAKE A PICTURE OF THE RECEIPT AND UPLOAD THE RECEIPT IMAGE TO US FOR PAYMENT CONFIRMATION. THANK YOU FOR CHOOSING KEAH LOGISTICS.",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () {
                  String summary =
                      "💳 PAYMENT INVOICE\n\n"
                      "• Delivery: ₦${_deliveryFeeController.text}\n"
                      "• Commission: ₦${_serviceCommission.toStringAsFixed(2)}\n"
                      "• TOTAL: ₦${_totalAmount.toStringAsFixed(2)}\n\n"
                      "--- BANK DETAILS ---\n"
                      "Bank: MONIEPOINT MFB\n"
                      "Acct No: 8149747864\n"
                      "Name: KEAH LOGISTICS\n\n"
                      "⚠️ INSTRUCTION:\n"
                      "ONCE YOU MAKE THE PAYMENT TAKE A PICTURE OF THE RECEIPT AND UPLOAD THE RECEIPT IMAGE FOR PAYMENT CONFIRMATION. THANK YOU FOR CHOOSING KEAH LOGISTICS.";

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
            const SizedBox(height: 4),
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
}
