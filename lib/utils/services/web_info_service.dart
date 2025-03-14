import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class WebInfoService extends ChangeNotifier {
  WebInfoService._();

  static final WebInfoService _instance = WebInfoService._();
  static WebInfoService get instance => _instance;

  final NetworkInfo _wifiInfo = NetworkInfo();

  // Use ValueNotifier so UI can listen for changes
  final ValueNotifier<String> wifiIpNotifier = ValueNotifier("Fetching...");

  Future<void> init() async {
    try {
      String? wifiIP = await _wifiInfo.getWifiIP();
      wifiIpNotifier.value = wifiIP ?? "No IP found";
      notifyListeners();
    } catch (e) {
      wifiIpNotifier.value = "Error: $e";
      notifyListeners();
    }
  }
}
