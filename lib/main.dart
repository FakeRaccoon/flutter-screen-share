import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_screen/config/themes/theme.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:share_screen/modules/share_screen_local_ip/view/share_screen_local_ip_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) await startForegroundService();
  runApp(const MyApp());
}

Future<bool> startForegroundService() async {
  final androidConfig = FlutterBackgroundAndroidConfig(
    notificationTitle: 'Title of the notification',
    notificationText: 'Text of the notification',
    notificationImportance: AndroidNotificationImportance.normal,
    notificationIcon: AndroidResource(
      name: 'background_icon',
      defType: 'drawable',
    ), // Default is ic_launcher from folder mipmap
  );
  await FlutterBackground.initialize(androidConfig: androidConfig);
  return FlutterBackground.enableBackgroundExecution();
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
