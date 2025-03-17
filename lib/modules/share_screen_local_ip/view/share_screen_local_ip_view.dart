import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_screen/utils/services/connectivity_service.dart';
import 'package:share_screen/utils/services/local_server_service.dart';
import 'package:share_screen/utils/services/web_info_service.dart';
import 'package:share_screen/utils/services/web_rtc_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

    // ConnectivityService.instance.connectionStatusNotifier.addListener(() {
    //   _handleWifiIpChange();
    // });
  }

  @override
  void dispose() {
    WebRtcService.instance.close();
    ConnectivityService.instance.close();
    super.dispose();
  }

  // void _handleWifiIpChange() {
  //   WebRtcService.instance.stopScreenSharing();
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Screen Sharing Host')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: LocalServerService.instance.isServerStarted,
              builder: (context, isStarted, _) {
                if (isStarted) {
                  final streamUrl =
                      "${WebInfoService.instance.wifiIpNotifier.value}:${LocalServerService.instance.clientWebPort}";

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      padding: EdgeInsets.all(12),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueAccent, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Access stream at:",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          SizedBox(height: 5),
                          InkWell(
                            onTap: () async {
                              var url = 'http://$streamUrl';
                              launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: Text(
                              streamUrl,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.copy, color: Colors.white),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: streamUrl),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Stream URL copied!"),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.share, color: Colors.white),
                                onPressed: () async {
                                  final result = await Share.share(
                                    'Check out my share screen at http://$streamUrl',
                                  );

                                  if (!context.mounted) return;

                                  if (result.status ==
                                      ShareResultStatus.success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Success to share Stream URL!",
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                    ), // Match padding
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent, width: 2),
                      ),
                      child: Text(
                        "Server not started",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.redAccent, fontSize: 16),
                      ),
                    ),
                  );
                }
              },
            ),
            SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: WebRtcService.instance.clientCountNotifier,
              builder: (context, clientCount, _) {
                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 6),
                  padding: EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      'Total Client: $clientCount',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ), // Ensure padding works
        child: ValueListenableBuilder<bool>(
          valueListenable: WebRtcService.instance.isScreenSharingNotifier,
          builder: (context, isSharing, _) {
            return ElevatedButton.icon(
              onPressed:
                  isSharing
                      ? WebRtcService.instance.stopScreenSharing
                      : WebRtcService.instance.startScreenSharing,
              icon: Icon(isSharing ? Icons.stop : Icons.screen_share),
              label: Text(isSharing ? 'Stop Sharing' : 'Start Sharing'),
              style: ElevatedButton.styleFrom(
                foregroundColor: isSharing ? Colors.red : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
