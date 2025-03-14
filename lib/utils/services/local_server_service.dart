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

  void startServer() async {
    await WebInfoService.instance.init();
    String wifiIP = WebInfoService.instance.wifiIpNotifier.value;

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
      /* Dark theme and full screen container */
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
      /* Video element styling */
      video {
        border: 2px solid #333;
        border-radius: 8px;
        background-color: #000;
        width: 100%;
        height: auto;
        max-width: 360px; /* Adjust the max-width to resemble YouTube shorts */
        aspect-ratio: 9 / 16; /* Aspect ratio for YouTube shorts */
        object-fit: contain;
      }
      header,
      footer {
        position: absolute;
        width: 100%;
        text-align: center;
        padding: 10px;
      }
      header {
        top: 0;
      }
      footer {
        bottom: 0;
        font-size: 0.9em;
      }
    </style>
  </head>
  <body>
    <header>
      <h1>Screen Viewer</h1>
    </header>
    <div class="container">
      <video id="remote-video" autoplay playsinline muted></video>
    </div>
    <script>
      // Helper: create a new RTCPeerConnection with event handlers.
      function createPeerConnection() {
        let pc = new RTCPeerConnection({
          iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
        });
        pc.ontrack = (event) => {
          console.log("🎥 Track event received:", event);
          if (event.streams.length > 0) {
            remoteVideo.srcObject = event.streams[0];
            // When metadata loads, adjust size.
            remoteVideo.addEventListener("loadedmetadata", resizeVideo);
            // Handle stream end.
            event.streams[0].oninactive = () => {
              console.log("⛔ Remote stream stopped.");
              stopVideoPlayback();
            };
          } else {
            console.log("⚠️ No stream attached to track event.");
          }
        };
        return pc;
      }
      
      // Global variables.
      const remoteVideo = document.getElementById("remote-video");
      const socket = new WebSocket("ws://${WebInfoService.instance.wifiIpNotifier.value}:$webSocketPort");
      let peerConnection = createPeerConnection();
      
      socket.onopen = () => { 
        console.log("🔗 WebSocket Connected!"); 
      };
      
      socket.onmessage = async (event) => {
        const data = JSON.parse(event.data);
        console.log("📩 Received from WebSocket:", data);
        if (data.type === "offer") {
          console.log("🔄 Received Offer → Generating Answer...");
          await peerConnection.setRemoteDescription(new RTCSessionDescription(data));
          const answer = await peerConnection.createAnswer();
          await peerConnection.setLocalDescription(answer);
          socket.send(JSON.stringify({ type: "answer", sdp: answer.sdp }));
          console.log("📤 Sent Answer to WebSocket");
        } else if (data.type === "candidate") {
          console.log("🔀 Adding ICE Candidate");
          peerConnection.addIceCandidate(new RTCIceCandidate(data.candidate));
        } else if (data.type === "stream_stopped") {
          console.log("⛔ Stream stopped by Flutter. Stopping video playback...");
          stopVideoPlayback();
        }
      };
      
      // When stopping video playback, close the current peerConnection
      // and create a new one with fresh event handlers.
      function stopVideoPlayback() {
        remoteVideo.srcObject = null;
        peerConnection.close();
        peerConnection = createPeerConnection();
      }
      
      // Adjust the video size based on its intrinsic dimensions vs. viewport.
      function resizeVideo() {
        if (!remoteVideo.videoWidth || !remoteVideo.videoHeight) return;
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        const videoAspect = remoteVideo.videoWidth / remoteVideo.videoHeight;
        const windowAspect = vw / vh;
        
        if (videoAspect > windowAspect) {
          // For wider videos: fill width and adjust height.
          remoteVideo.style.width = "100%";
          remoteVideo.style.height = "auto";
        } else {
          // For taller videos: fill height and adjust width.
          remoteVideo.style.width = "auto";
          remoteVideo.style.height = "100%";
        }
      }
      
      // Resize on window resize.
      window.addEventListener("resize", resizeVideo);
    </script>
  </body>
</html>
      ''',
      headers: {'Content-Type': 'text/html'},
    );
  }
}
