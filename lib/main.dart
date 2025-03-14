import 'package:flutter/material.dart';
import 'package:share_screen/config/themes/theme.dart';
import 'package:share_screen/modules/share_screen_local_ip/view/share_screen_local_ip_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Share Screen App',
      theme: AppTheme.theme,
      home: ShareScreenLocalIpView(),
    );
  }
}
