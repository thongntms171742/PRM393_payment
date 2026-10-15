import 'package:flutter/material.dart';
import 'sepay_qr_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo Thanh Toán SePay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SepayQrScreen(
        bank: 'Vietcombank',
        acc: 'SBSEPAYPFJHZ4SXKYXH',
        template: 'compact',
        checkStatusUrl: 'https://seminar-impatient-muck.ngrok-free.dev/api/webhooks/sepay',
      ),
    );
  }
}
