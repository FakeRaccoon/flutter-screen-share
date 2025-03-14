import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:share_screen/utils/services/connectivity_service.dart';
import 'package:share_screen/utils/services/local_server_service.dart';
import 'package:share_screen/utils/services/web_info_service.dart';
import 'package:share_screen/utils/services/web_rtc_service.dart';

class ShareScreenLocalIpView extends StatefulWidget {
  const ShareScreenLocalIpView({super.key});

  @override
  ShareScreenLocalIpViewState createState() => ShareScreenLocalIpViewState();
}

class ShareScreenLocalIpViewState extends State<ShareScreenLocalIpView> {
  @override
  void initState() {
    super.initState();
    //NetworkInfo
    WebInfoService.instance.init();

    //Web RTC
    WebRtcService.instance.initializeRenderer();

    //Local Server
    LocalServerService.instance.startServer();

    //WebSocket
    WebRtcService.instance.initializeWebSocket();

    //Connectivity Plus
    ConnectivityService.instance.initConnectivity();
    ConnectivityService.instance.addListener();

    ConnectivityService.instance.connectionStatusNotifier.addListener(() {
      _handleWifiIpChange();
    });
  }

  @override
  void dispose() {
    WebRtcService.instance.close();
    ConnectivityService.instance.close();
    super.dispose();
  }

  void _handleWifiIpChange() {
    log("Network Change");
    WebRtcService.instance.stopScreenSharing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Sharing Host')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: WebRtcService.instance.startScreenSharing,
              icon: Icon(Icons.screen_share),
              label: Text('Start Sharing'),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: WebRtcService.instance.stopScreenSharing,
              icon: Icon(Icons.stop),
              label: Text('Stop Sharing'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
            ),
            SizedBox(height: 20),

            // Listen for WebInfoService updates
            ValueListenableBuilder<String>(
              valueListenable: WebInfoService.instance.wifiIpNotifier,
              builder: (context, wifiIp, _) {
                return Text("WiFi IP: $wifiIp");
              },
            ),

            // Listen for LocalServerService updates
            ValueListenableBuilder<bool>(
              valueListenable: LocalServerService.instance.isServerStarted,
              builder: (context, isStarted, _) {
                return isStarted
                    ? Text(
                      "Client IP: ${WebInfoService.instance.wifiIpNotifier.value}:${LocalServerService.instance.clientWebPort}",
                    )
                    : Text("Server not started");
              },
            ),
          ],
        ),
      ),
    );
  }
}
