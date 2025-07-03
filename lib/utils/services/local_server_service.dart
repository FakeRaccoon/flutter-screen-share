import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_screen/utils/services/web_info_service.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf/shelf.dart';

class LocalServerService extends ChangeNotifier {
  LocalServerService._();
  static final LocalServerService _instance = LocalServerService._();
  static LocalServerService get instance => _instance;

  final ValueNotifier<bool> isServerStarted = ValueNotifier(false);

  String clientWebPort = "3389";
  String webSocketPort = "4000";

  double ratio = 0.0;

  void startServer(BuildContext context) async {
    await WebInfoService.instance.init();
    String wifiIP = WebInfoService.instance.wifiIpNotifier.value;

    if (!context.mounted) return;

    ratio =
        MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;

    log("ASPECT RATIO $ratio");

    log('ip : $wifiIP');
    var handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_htmlHandler);

    var server = await io.serve(handler, InternetAddress.anyIPv4, 3389);
    isServerStarted.value = true;
    notifyListeners();

    log('🚀 Server running at http://${server.address.host}:${server.port}');
  }

  Response _htmlHandler(Request request) {
    return Response.ok(
      '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>WebRTC Screen Viewer</title>
    <style>
      body {
        margin: 0;
        background-color: #181818;
        color: #fff;
        font-family: Arial, sans-serif;
        overflow: hidden;
      }
      .container {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100vh;
        width: 100vw;
        padding: 16px;
        box-sizing: border-box;
        position: relative;
      }
      video {
        border: 2px solid #333;
        border-radius: 8px;
        background-color: #000;
        width: 100%;
        height: auto;
        aspect-ratio: $ratio;
        object-fit: contain;
      }
      /* Status message styling */
      #status-message {
        position: absolute;
        font-size: 24px;
        color: #bbb;
        background: rgba(0, 0, 0, 0.6);
        padding: 10px 20px;
        border-radius: 8px;
        text-align: center;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div id="status-message">Connecting to ws://${WebInfoService.instance.wifiIpNotifier.value}...</div>
      <video id="remote-video" autoplay playsinline muted></video>
    </div>
    <script>
      function createPeerConnection() {
      const iceConfig = {
  iceServers: [], // No external STUN/TURN servers
  bundlePolicy: "max-bundle",
};
        let pc = new RTCPeerConnection(iceConfig);
        pc.ontrack = (event) => {
          console.log("🎥 Track event received:", event);
          if (event.streams.length > 0) {
            remoteVideo.srcObject = event.streams[0];
            hideStatusMessage(); // Hide message when stream starts
            remoteVideo.addEventListener("loadedmetadata", resizeVideo);
            event.streams[0].oninactive = () => {
              console.log("⛔ Remote stream stopped.");
              remoteVideo.srcObject = null; // Clear video
              showStatusMessage("Waiting for stream...");
            };
          }
        };
        return pc;
      }

      const remoteVideo = document.getElementById("remote-video");
      const statusMessage = document.getElementById("status-message");
      const socket = new WebSocket("ws://${WebInfoService.instance.wifiIpNotifier.value}:$webSocketPort");
      let peerConnection = createPeerConnection();

      socket.onopen = () => {
        console.log("🔗 WebSocket Connected!");
        showStatusMessage("Waiting for stream...");
      };

      socket.onmessage = async (event) => {
        const data = JSON.parse(event.data);
        if (data.type === "offer") {
          await peerConnection.setRemoteDescription(new RTCSessionDescription(data));
          const answer = await peerConnection.createAnswer();
          await peerConnection.setLocalDescription(answer);
          socket.send(JSON.stringify({ type: "answer", sdp: answer.sdp }));
        } else if (data.type === "candidate") {
          peerConnection.addIceCandidate(new RTCIceCandidate(data.candidate));
        } else if (data.type === "stream_stopped") {
          remoteVideo.srcObject = null; // Clear video
          showStatusMessage("Waiting for stream...");
        }
      };

      socket.onclose = () => {
        console.log("❌ WebSocket Disconnected!");
        showStatusMessage("You are disconnected, please reload the page");
      };

      socket.onerror = (error) => {
        console.error("⚠️ WebSocket Error:", error);
        showStatusMessage("You are disconnected, please reload the page");
      };

      function showStatusMessage(text) {
        statusMessage.textContent = text;
        statusMessage.style.display = "block";
      }

      function hideStatusMessage() {
        statusMessage.style.display = "none";
      }

      function resizeVideo() {
        if (!remoteVideo.videoWidth || !remoteVideo.videoHeight) return;
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        const videoAspect = remoteVideo.videoWidth / remoteVideo.videoHeight;
        const windowAspect = vw / vh;

        if (videoAspect > windowAspect) {
          remoteVideo.style.width = "100%";
          remoteVideo.style.height = "auto";
        } else {
          remoteVideo.style.width = "auto";
          remoteVideo.style.height = "100%";
        }
      }

      window.addEventListener("resize", resizeVideo);
    </script>
  </body>
</html>
    ''',
      headers: {'Content-Type': 'text/html'},
    );
  }
}
