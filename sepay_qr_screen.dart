import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SepayQrScreen extends StatefulWidget {
  final String bank; // Ngân hàng nhận
  final String acc; // STK nhận tiền SePay
  final String template; // 'compact', 'qronly'
  final String checkStatusUrl; // URL webhook/status

  const SepayQrScreen({
    super.key,
    this.bank = 'Vietcombank',
    this.acc = 'SBSEPAYPFJHZ4SXKYXH',
    this.template = 'compact',
    this.checkStatusUrl =
        'https://seminar-impatient-muck.ngrok-free.dev/api/webhooks/sepay',
  });

  @override
  State<SepayQrScreen> createState() => _SepayQrScreenState();
}

class _SepayQrScreenState extends State<SepayQrScreen> {
  // Controller nhập số tiền
  final TextEditingController _amountController =
      TextEditingController(text: '10000');

  late String _currentDes; // Nội dung chuyển khoản tự sinh
  int _currentAmount = 10000; // Số tiền hiện tại
  bool _hasCreatedQr = true; // Trạng thái đã tạo QR

  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _isPaid = false;
  String _statusMessage = 'Đang chờ thanh toán (Tự động kiểm tra mỗi 3s)...';
  String? _errorMessage;

  // Hàm tự sinh nội dung chuyển khoản duy nhất (VD: SMA4821)
  String _generateOrderCode() {
    final randomNum = Random().nextInt(9000) + 1000;
    return 'SMA$randomNum';
  }

  @override
  void initState() {
    super.initState();
    _currentDes = _generateOrderCode();
    _startPolling();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  // URL VietQR tạo theo số tiền và mã đơn hiện tại
  String get qrUrl {
    final uri = Uri.https('vietqr.app', '/img', {
      'bank': widget.bank,
      'acc': widget.acc,
      'template': widget.template,
      'amount': _currentAmount.toString(),
      'des': _currentDes,
    });
    return uri.toString();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isChecking && !_isPaid && _hasCreatedQr) {
        _checkPaymentStatus();
      }
    });
  }

  // Tạo hoặc cập nhật mã QR với số tiền và nội dung mới
  void _createNewQr() {
    final enteredAmount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );

    if (enteredAmount == null || enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số tiền hợp lệ (> 0đ)!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _currentAmount = enteredAmount;
      _currentDes = _generateOrderCode(); // Tự động tạo mã đơn mới
      _isPaid = false;
      _hasCreatedQr = true;
      _errorMessage = null;
      _statusMessage = 'Đang chờ thanh toán cho đơn $_currentDes...';
    });

    FocusScope.of(context).unfocus(); // Đóng bàn phím
    _startPolling(); // Bắt đầu lắng nghe cho mã đơn mới

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã tạo mã QR mới: $_currentDes - ${_formatMoney(_currentAmount)} đ'),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Chọn nhanh số tiền mẫu
  void _selectQuickAmount(int amount) {
    setState(() {
      _amountController.text = amount.toString();
    });
    _createNewQr();
  }

  String _formatMoney(int amount) {
    return amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  // Gọi API kiểm tra thanh toán
  Future<void> _checkPaymentStatus() async {
    if (_isChecking || _isPaid) return;
    setState(() => _isChecking = true);

    try {
      final client = HttpClient();
      final parsedUri = Uri.parse(widget.checkStatusUrl);
      final checkUri = parsedUri.replace(
        queryParameters: {
          ...parsedUri.queryParameters,
          'des': _currentDes,
          'amount': _currentAmount.toString(),
        },
      );

      final request = await client.getUrl(checkUri);
      request.headers.set('ngrok-skip-browser-warning', 'true');
      request.headers.set('Accept', 'application/json');

      final response =
          await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);

        bool isSuccess = data['status'] == 'PAID' ||
            data['status'] == 'success' ||
            data['isPaid'] == true ||
            data['success'] == true;

        if (mounted) {
          setState(() {
            _errorMessage = null;
            _statusMessage = isSuccess
                ? 'Đã nhận được thanh toán!'
                : 'Chưa thấy giao dịch tiền về (Đang chờ khách CK)...';
          });
        }

        if (isSuccess && mounted) {
          _handlePaymentSuccess();
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          setState(() {
            _errorMessage =
                '⚠️ Lỗi 404: Endpoint chưa hỗ trợ GET hoặc sai URL ngrok.\n(Chạy node server_webhook.js để kích hoạt)';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = '⚠️ Server phản hồi mã lỗi: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '⚠️ Không thể kết nối tới server: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _handlePaymentSuccess() {
    _pollingTimer?.cancel();
    setState(() {
      _isPaid = true;
      _errorMessage = null;
      _statusMessage = 'Thanh toán thành công!';
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
        title: const Text('Thanh toán thành công!'),
        content: Text(
          'Đơn hàng $_currentDes đã được thanh toán thành công số tiền ${_formatMoney(_currentAmount)} đ.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Đóng'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createNewQr(); // Tạo mã mới cho giao dịch tiếp theo
            },
            child: const Text('Tạo giao dịch mới'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $value'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo mã QR thanh toán SePay'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ================= KHU VỰC NHẬP GIÁ TIỀN & MÃ TỰ SINH =================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. Nhập thông tin thanh toán',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Ô nhập số tiền
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Số tiền thanh toán (VND)',
                        hintText: 'Ví dụ: 20000',
                        prefixIcon: const Icon(Icons.monetization_on_outlined),
                        suffixText: 'VNĐ',
                        suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Các nút chọn nhanh số tiền
                    Wrap(
                      spacing: 8,
                      children: [10000, 20000, 50000, 100000].map((val) {
                        return ActionChip(
                          avatar: const Icon(Icons.bolt, size: 14, color: Colors.blue),
                          label: Text('${_formatMoney(val)} đ'),
                          onPressed: () => _selectQuickAmount(val),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // Hiển thị nội dung chuyển khoản tự sinh
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tag, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          const Text('Nội dung CK tự tạo: '),
                          Text(
                            _currentDes,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.cached, color: Colors.blue, size: 20),
                            tooltip: 'Đổi mã đơn hàng khác',
                            onPressed: () {
                              setState(() {
                                _currentDes = _generateOrderCode();
                              });
                              _createNewQr();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Nút bấm Tạo mã QR
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text(
                          'TẠO / CẬP NHẬT MÃ QR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _createNewQr,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ================= KHU VỰC HIỂN THỊ MÃ QR =================
            if (_hasCreatedQr) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        '2. Quét mã QR bằng App Ngân Hàng',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Ảnh mã VietQR
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            qrUrl,
                            key: ValueKey('$_currentDes-$_currentAmount'), // Re-render khi đổi tiền/mã
                            width: 270,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : const SizedBox(
                                        height: 270,
                                        width: 270,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(
                              height: 270,
                              width: 270,
                              child: Center(
                                child: Text(
                                  'Không thể tải mã QR.\nVui lòng kiểm tra kết nối mạng.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(),

                      // Thông tin chuyển khoản chi tiết
                      _buildInfoRow('Ngân hàng', widget.bank),
                      _buildInfoRow('Số tài khoản', widget.acc, canCopy: true),
                      _buildInfoRow(
                        'Số tiền',
                        '${_formatMoney(_currentAmount)} đ',
                        canCopy: true,
                        copyValue: _currentAmount.toString(),
                      ),
                      _buildInfoRow(
                        'Nội dung CK',
                        _currentDes,
                        canCopy: true,
                        highlight: true,
                      ),

                      const SizedBox(height: 16),

                      // Thông báo lỗi nếu có (vd 404)
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amber, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.brown.shade800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Trạng thái chờ thanh toán
                      if (!_isPaid) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isChecking)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              const Icon(Icons.access_time, size: 18, color: Colors.orange),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _isChecking
                                    ? 'Đang kiểm tra giao dịch...'
                                    : _statusMessage,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Nút kiểm tra thủ công
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Kiểm tra thanh toán lại'),
                            onPressed: _isChecking ? null : _checkPaymentStatus,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Nút giả lập thanh toán thành công
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal,
                              backgroundColor: Colors.teal.shade50,
                            ),
                            icon: const Icon(Icons.bolt, size: 20),
                            label: const Text('⚡ Giả lập thanh toán thành công (Test)'),
                            onPressed: _handlePaymentSuccess,
                          ),
                        ),
                      ] else ...[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Đã thanh toán thành công!',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool canCopy = false,
    String? copyValue,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.red : Colors.black87,
                ),
              ),
              if (canCopy) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.blue),
                  onPressed: () => _copyToClipboard(label, copyValue ?? value),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
