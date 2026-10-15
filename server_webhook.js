/**
 * SERVER BACKEND GIẢ LẬP XỬ LÝ SEPAY WEBHOOK & API CHECK STATUS CHO FLUTTER
 * Chạy bằng Node.js thuần (KHÔNG CẦN CÀI THÊM THƯ VIỆN NPM)
 * Cách chạy:
 *   node server_webhook.js
 * Sau đó mở ngrok:
 *   ngrok http 3000
 */

const http = require('http');
const url = require('url');

// Lưu danh sách các mã đơn hàng đã nhận được tiền từ SePay
const paidOrders = new Set(['SMA0001_PAID']); // Đã có sẵn 1 mã test thành công

const server = http.createServer((req, res) => {
  // Cấu hình CORS để Flutter Web hoặc App không bị chặn
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, ngrok-skip-browser-warning');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  // =========================================================================
  // 1. WEBHOOK POST: Nhận thông báo giao dịch từ SePay khi khách chuyển tiền
  // =========================================================================
  if (req.method === 'POST' && pathname === '/api/webhooks/sepay') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      console.log('\n[SEPAY WEBHOOK NHẬN ĐƯỢC]:', body);
      try {
        const data = JSON.parse(body);
        // data.content chính là nội dung chuyển khoản (des) ví dụ: "SMA0001"
        if (data.content) {
          const orderCode = data.content.trim();
          paidOrders.add(orderCode);
          console.log(`=> Đã đánh dấu đơn hàng "${orderCode}" là ĐÃ THANH TOÁN!`);
        }
      } catch (err) {
        console.error('Lỗi parse json webhook:', err);
      }

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, message: 'Webhook received' }));
    });
    return;
  }

  // =========================================================================
  // 2. CHECK STATUS GET: Flutter App gọi lên để hỏi đơn hàng đã thanh toán chưa
  // =========================================================================
  if (req.method === 'GET' && pathname === '/api/webhooks/sepay') {
    const des = (parsedUrl.query.des || '').trim();
    const isPaid = paidOrders.has(des);

    console.log(`[FLUTTER CHECK] Mã đơn: "${des}" -> Trạng thái: ${isPaid ? 'PAID (Thành công)' : 'PENDING (Chờ)'}`);

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      des: des,
      status: isPaid ? 'PAID' : 'PENDING',
      isPaid: isPaid
    }));
    return;
  }

  // =========================================================================
  // 3. API TEST NHANH: Bấm vào link này trên trình duyệt để đánh dấu thanh toán
  // Ví dụ: http://localhost:3000/api/mock-pay?des=SMA0001
  // =========================================================================
  if (req.method === 'GET' && pathname === '/api/mock-pay') {
    const des = (parsedUrl.query.des || 'SMA0001').trim();
    paidOrders.add(des);
    console.log(`[TEST MANUAL] Đã kích hoạt thanh toán thành công cho mã "${des}"`);
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({
      message: `Đã kích hoạt thanh toán thành công cho đơn: ${des}! Mở App Flutter để thấy kết quả.`,
      status: 'PAID'
    }));
    return;
  }

  // 404 cho các route khác
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint not found', path: pathname }));
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log('=================================================================');
  console.log(`Server Backend SePay đang chạy tại: http://localhost:${PORT}`);
  console.log(`- Webhook nhận từ SePay (POST):  /api/webhooks/sepay`);
  console.log(`- App Flutter kiểm tra   (GET):   /api/webhooks/sepay?des=SMA0001`);
  console.log(`- Kích hoạt test nhanh   (GET):   /api/mock-pay?des=SMA0001`);
  console.log('=================================================================');
});
