import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(MaterialApp(home: GetDisplayManual()));
}

class GetDisplayManual extends StatefulWidget {
  const GetDisplayManual({super.key});

  @override
  GetDisplayManualState createState() => GetDisplayManualState();
}

class GetDisplayManualState extends State<GetDisplayManual> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  // Map each WebSocket client to its RTCPeerConnection.
  Map<WebSocketChannel, RTCPeerConnection> peerConnections = {};
  Set<WebSocketChannel> clients = {};

  // ICE server configuration with a STUN server.
  final Map<String, dynamic> iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  // Initialize the WebSocket server for signaling.
  void initializeWebSocket() async {
    final handler = webSocketHandler((WebSocketChannel webSocket, _) async {
      log("🟢 Client connected");
      clients.add(webSocket);

      // Create a new peer connection for this client.
      var peerConnection = await createPeerConnection(iceConfig);

      // Set up the ICE candidate callback.
      peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          log('📤 ICE Candidate generated: ${candidate.toMap()}');
          webSocket.sink.add(
            jsonEncode({'type': 'candidate', 'candidate': candidate.toMap()}),
          );
        }
      };

      // (Optional) Listen for remote tracks if needed.
      peerConnection.onTrack = (RTCTrackEvent event) {
        log('🎥 Remote track received');
      };

      // If screen sharing is active, add its tracks to this new connection
      // and send an offer immediately.
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          log('🔗 Adding track: ${track.kind} to new connection');
          peerConnection.addTrack(track, _localStream!);
        }
        await createOfferForClient(peerConnection, webSocket);
      }

      // Save the peer connection.
      peerConnections[webSocket] = peerConnection;

      // Listen for messages (answer, ICE candidates) from the client.
      webSocket.stream.listen(
        (message) async {
          log("📩 Received: $message");
          var data = jsonDecode(message);
          if (data['type'] == 'answer') {
            await handleAnswer(data, webSocket);
          } else if (data['type'] == 'candidate') {
            await handleCandidate(data, webSocket);
          }
        },
        onDone: () {
          log("🔴 Client disconnected");
          clients.remove(webSocket);
          peerConnections[webSocket]?.close();
          peerConnections.remove(webSocket);
          setState(() {});
        },
        onError: (error) {
          log("⚠️ WebSocket error: $error");
          clients.remove(webSocket);
          peerConnections[webSocket]?.close();
          peerConnections.remove(webSocket);
          setState(() {});
        },
      );
    });

    var server = await io.serve(handler, InternetAddress.anyIPv4, 4000);
    log(
      "🚀 WebSocket Server running on ws://${server.address.host}:${server.port}",
    );
  }

  // Apply an answer received from a client to the correct peer connection.
  Future<void> handleAnswer(
    Map<String, dynamic> data,
    WebSocketChannel webSocket,
  ) async {
    var peerConnection = peerConnections[webSocket];
    if (peerConnection != null) {
      await peerConnection.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      log("✅ Answer applied for client");
    } else {
      log("❌ No peer connection found for this client to apply answer");
    }
  }

  // Handle ICE candidates received from a client.
  Future<void> handleCandidate(
    Map<String, dynamic> data,
    WebSocketChannel webSocket,
  ) async {
    var peerConnection = peerConnections[webSocket];
    if (peerConnection != null) {
      var candidateData = data['candidate'];
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );
      await peerConnection.addCandidate(candidate);
      log("✅ Added ICE candidate for client");
    }
  }

  // Create an offer for a specific client and send it over its WebSocket.
  Future<void> createOfferForClient(
    RTCPeerConnection peerConnection,
    WebSocketChannel client,
  ) async {
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    var offerData = jsonEncode({'type': 'offer', 'sdp': offer.sdp});
    log('📤 Sending Offer to client');
    client.sink.add(offerData);
  }

  // Start screen sharing:
  // - Request background permission (if needed)
  // - Obtain the display media stream
  // - Set the local renderer's srcObject to the stream
  // - Add tracks to each existing peer connection and send an updated offer.
  Future<void> startScreenSharing() async {
    try {
      await requestBackgroundPermission();
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': true,
      });

      if (stream.getTracks().isEmpty) {
        log('❌ No screen share stream received');
        return;
      }

      log('✅ Screen share stream received');
      _localStream = stream;
      _localRenderer.srcObject = _localStream;

      // Add the screen tracks to every connection and create an offer per client.
      for (var entry in peerConnections.entries) {
        var pc = entry.value;
        // Add each track from the stream.
        for (var track in _localStream!.getTracks()) {
          log('🔗 Adding track: ${track.kind} to existing connection');
          pc.addTrack(track, _localStream!);
        }
        await createOfferForClient(pc, entry.key);
      }
      setState(() {});
    } catch (e) {
      log('❌ Error starting screen sharing: $e');
    }
  }

  // Stop screen sharing:
  // - Remove local stream tracks from every peer connection
  // - Stop the stream tracks and clear the renderer.
  // - Notify connected clients that the stream has stopped.
  Future<void> stopScreenSharing() async {
    if (_localStream != null) {
      // Remove the tracks from each peer connection.
      for (var pc in peerConnections.values) {
        List<RTCRtpSender> senders = await pc.getSenders();
        for (var sender in senders) {
          if (_localStream!.getTracks().contains(sender.track)) {
            pc.removeTrack(sender);
          }
        }
      }
      // Stop all tracks of the local stream.
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream = null;
    }
    _localRenderer.srcObject = null;
    setState(() {});
    log("⛔ Screen sharing stopped");

    // Notify all clients that the stream has stopped.
    for (var client in clients) {
      client.sink.add(jsonEncode({'type': 'stream_stopped'}));
    }
  }

  // Request background permission on Android (if required).
  Future<void> requestBackgroundPermission([bool isRetry = false]) async {
    try {
      var hasPermissions = await FlutterBackground.hasPermissions;
      if (!isRetry) {
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: 'Screen Sharing',
          notificationText: 'Screen is being shared.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(
            name: 'livekit_ic_launcher',
            defType: 'mipmap',
          ),
        );
        hasPermissions = await FlutterBackground.initialize(
          androidConfig: androidConfig,
        );
      }
      if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
    } catch (e) {
      if (!isRetry) {
        await Future.delayed(
          Duration(seconds: 1),
          () => requestBackgroundPermission(true),
        );
      }
      log('⚠️ Background permission error: $e');
    }
  }

  // Start a simple HTTP server to serve the client HTML page.
  void _startServer() async {
    var handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_htmlHandler);
    var server = await io.serve(handler, InternetAddress.anyIPv4, 3389);
    log('🚀 Server running at http://${server.address.host}:${server.port}');
  }

  // Serve a simple HTML page that runs the WebRTC client.
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
      const socket = new WebSocket("ws://192.168.1.8:4000");
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

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _startServer();
    initializeWebSocket();
  }

  void _initializeRenderer() async {
    try {
      await _localRenderer.initialize();
      log("✅ Video Renderer Initialized");
      setState(() {});
    } catch (e) {
      log("❌ Error initializing renderer: $e");
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    for (var pc in peerConnections.values) {
      pc.close();
    }
    super.dispose();
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
            Expanded(
              child: Center(
                child:
                    _localRenderer.textureId != null
                        ? RTCVideoView(_localRenderer)
                        : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text('Initializing WebRTC...'),
                          ],
                        ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: startScreenSharing,
              icon: Icon(Icons.screen_share),
              label: Text('Start Sharing'),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: stopScreenSharing,
              icon: Icon(Icons.stop),
              label: Text('Stop Sharing'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
