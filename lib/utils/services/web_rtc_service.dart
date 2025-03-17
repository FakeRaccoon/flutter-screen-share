import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:share_screen/utils/services/web_info_service.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf/shelf_io.dart' as io;

class WebRtcService extends ChangeNotifier {
  WebRtcService._();
  static final WebRtcService _instance = WebRtcService._();
  static WebRtcService get instance => _instance;

  final ValueNotifier<RTCVideoRenderer> localRenderer =
      ValueNotifier<RTCVideoRenderer>(RTCVideoRenderer());
  final ValueNotifier<int?> localRendererNotifier = ValueNotifier<int?>(null);

  MediaStream? _localStream;
  final ValueNotifier<bool> isScreenSharingNotifier = ValueNotifier(false);

  Set<WebSocketChannel> clients = {};
  ValueNotifier<int> clientCountNotifier = ValueNotifier<int>(0);

  Map<WebSocketChannel, RTCPeerConnection> peerConnections = {};

  // ICE server configuration with a STUN server.
  final Map<String, dynamic> iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  void initializeWebSocket() async {
    await WebInfoService.instance.init();

    final handler = webSocketHandler((WebSocketChannel webSocket, _) async {
      log("🟢 Client connected");
      clients.add(webSocket);
      clientCountNotifier.value = clients.length;
      notifyListeners();

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
          clientCountNotifier.value = clients.length;
          notifyListeners();
        },
        onError: (error) {
          log("⚠️ WebSocket error: $error");
          clients.remove(webSocket);
          peerConnections[webSocket]?.close();
          peerConnections.remove(webSocket);
          clientCountNotifier.value = clients.length;
          notifyListeners();
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

  void initializeRenderer() async {
    try {
      await localRenderer.value.initialize();
      localRendererNotifier.value = localRenderer.value.textureId;
      notifyListeners();
      log("✅ Video Renderer Initialized");
    } catch (e) {
      notifyListeners();
      log("❌ Error initializing renderer: $e");
    }
  }

  Future<void> reuestPermisison() async {
    if (Platform.isAndroid) {
      // Android specific
      bool hasCapturePermission = await Helper.requestCapturePermission();
      if (!hasCapturePermission) {
        return;
      }

      requestBackgroundPermission([bool isRetry = false]) async {
        // Required for android screenshare.
        try {
          bool hasPermissions = await FlutterBackground.hasPermissions;
          if (!isRetry) {
            const androidConfig = FlutterBackgroundAndroidConfig(
              notificationTitle: 'Screen Sharing',
              notificationText: 'LiveKit Example is sharing the screen.',
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
          if (hasPermissions &&
              !FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        } catch (e) {
          if (!isRetry) {
            return await Future<void>.delayed(
              const Duration(seconds: 1),
              () => requestBackgroundPermission(true),
            );
          }
          log('could not publish video: $e');
        }
      }

      await requestBackgroundPermission();
    }
  }

  // Start screen sharing:
  // - Request background permission (if needed)
  // - Obtain the display media stream
  // - Set the local renderer's srcObject to the stream
  // - Add tracks to each existing peer connection and send an updated offer.
  Future<void> startScreenSharing() async {
    try {
      await reuestPermisison();
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
      localRenderer.value.srcObject = _localStream;

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

      isScreenSharingNotifier.value = true;
      notifyListeners();
    } catch (e) {
      notifyListeners();
      isScreenSharingNotifier.value = false;
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
    localRenderer.value.srcObject = null;
    log("⛔ Screen sharing stopped");

    // Notify all clients that the stream has stopped.
    for (var client in clients) {
      client.sink.add(jsonEncode({'type': 'stream_stopped'}));
    }
    isScreenSharingNotifier.value = false;
    await FlutterBackground.disableBackgroundExecution();
    notifyListeners();
  }

  void close() {
    localRenderer.dispose();
    _localStream?.getTracks().forEach((track) => track.stop()); // Stop stream
    _localStream?.dispose();
    localRendererNotifier.dispose();
    for (var pc in peerConnections.values) {
      pc.close();
    }
    notifyListeners();
  }
}
