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

class GetDisplayManual extends StatefulWidget {
  const GetDisplayManual({super.key});

  @override
  GetDisplayManualState createState() => GetDisplayManualState();
}

class GetDisplayManualState extends State<GetDisplayManual> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  TextEditingController answerController = TextEditingController();

  Set<WebSocketChannel> clients = {};

  void initializeWebSocket() async {
    final handler = webSocketHandler((WebSocketChannel webSocket, _) {
      log("🟢 Client connected");
      clients.add(webSocket);

      webSocket.stream.listen(
        (message) async {
          log("📩 Received: $message");
          var data = jsonDecode(message);

          // If a client sends an offer, relay it to all other clients
          if (data['type'] == 'offer') {
            for (var client in clients) {
              if (client != webSocket) {
                client.sink.add(jsonEncode(data));
              }
            }
          }
          // If a client sends an answer, send it back to the original offer sender
          else if (data['type'] == 'answer') {
            for (var client in clients) {
              if (client != webSocket) {
                client.sink.add(jsonEncode(data));
              } else {
                log("✅ Received Answer via WebSocket");
                answerController.text = jsonEncode(data); // Store the answer
              }
            }
          }
        },
        onDone: () {
          log("🔴 Client disconnected");
          clients.remove(webSocket);
        },
        onError: (error) {
          log("⚠️ WebSocket error: $error");
          clients.remove(webSocket);
        },
      );
    });

    var server = await io.serve(handler, InternetAddress.anyIPv4, 4000);
    log(
      "🚀 WebSocket Server running on ws://${server.address.host}:${server.port}",
    );
  }

  /// ✅ Request background permission (Android only)
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

  void _startServer() async {
    var handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_htmlHandler);

    var server = await io.serve(handler, InternetAddress.anyIPv4, 3389);
    log('🚀 Server running at http://${server.address.host}:${server.port}');
  }

  /// ✅ Serve Simple HTML Page (without reading from a file)
  Response _htmlHandler(Request request) {
    return Response.ok(
      '''
  <!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>WebRTC Screen Viewer</title>
  </head>
  <body>
    <h1>WebRTC Screen Viewer</h1>

    <video
      id="remote-video"
      autoplay
      playsinline
      muted
      style="width: 80%; border: 2px solid black"
    ></video>

    <script>
      let peerConnection = new RTCPeerConnection({
        iceServers: [],
      });

      let socket = new WebSocket("ws://10.10.4.14:4000");
      let remoteVideo = document.getElementById("remote-video");

      socket.onopen = () => {
        console.log("🔗 WebSocket Connected!");
      };

      socket.onmessage = async (event) => {
        let data = JSON.parse(event.data);
        console.log("📩 Received from WebSocket:", data);

        if (data.type === "offer") {
          console.log("🔄 Received Offer → Generating Answer...");
          await peerConnection.setRemoteDescription(
            new RTCSessionDescription(data)
          );

          let answer = await peerConnection.createAnswer();
          await peerConnection.setLocalDescription(answer);

          socket.send(JSON.stringify({ type: "answer", sdp: answer.sdp }));
          console.log("📤 Sent Answer to WebSocket");
        } else if (data.type === "answer") {
          console.log("✅ Received Answer → Applying...");
          await peerConnection.setRemoteDescription(
            new RTCSessionDescription(data)
          );
        } else if (data.type === "candidate") {
          console.log("🔀 Adding ICE Candidate");
          peerConnection.addIceCandidate(new RTCIceCandidate(data.candidate));
        } 
        // ✅ Detect when Flutter stops the stream
        else if (data.type === "stream_stopped") {
          console.log("⛔ Stream stopped by Flutter. Stopping video playback...");
          stopVideoPlayback();
        }
      };

      peerConnection.ontrack = (event) => {
        console.log("🎥 Track event received:", event);
        if (event.streams.length > 0) {
          remoteVideo.srcObject = event.streams[0];

          // ✅ Detect when stream stops
          event.streams[0].oninactive = () => {
            console.log("⛔ Remote stream stopped.");
            stopVideoPlayback();
          };
        } else {
          console.log("⚠️ No stream attached to track event.");
        }
      };

      // ✅ Function to stop video playback
      function stopVideoPlayback() {
        remoteVideo.srcObject = null; // Clear video
        peerConnection.close(); // Close peer connection
        peerConnection = new RTCPeerConnection({ iceServers: [] }); // Reset connection
      }
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
    _initializePeerConnection();
    _startServer();
    initializeWebSocket();
    _automateOfferAndAnswer(); // Automate offer and answer
  }

  void _initializeRenderer() async {
    try {
      await _localRenderer.initialize();
      log("✅ Video Renderer Initialized");
      setState(() {}); // Ensure UI updates
    } catch (e) {
      log("❌ Error initializing renderer: $e");
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _peerConnection?.close();
    _localStream?.getTracks().forEach((track) => track.stop()); // Stop stream
    _localStream?.dispose();
    super.dispose();
  }

  /// ✅ Initialize WebRTC Peer Connection
  Future<void> _initializePeerConnection() async {
    final config = {'iceServers': []};

    _peerConnection = await createPeerConnection(config);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      log('📤 ICE Candidate generated: ${candidate.toMap()}');
      for (var client in clients) {
        client.sink.add(
          jsonEncode({'type': 'candidate', 'candidate': candidate.toMap()}),
        );
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      log('🎥 Remote track received');
      if (event.streams.isNotEmpty) {
        log('✅ Setting remote video stream');
        _localRenderer.srcObject = event.streams[0];
        setState(() {});
      }
    };

    log("✅ PeerConnection initialized");
  }

  /// ✅ Start Screen Sharing
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

      _localStream?.getTracks().forEach((track) {
        log('🔗 Adding track: ${track.kind}');
        _peerConnection?.addTrack(track, _localStream!);
      });

      setState(() {}); // Update UI after setting the stream

      // Automate sending offer and applying answer
      await createOffer(); // Send offer automatically

      // Periodically check and apply answer if available
      Timer.periodic(Duration(seconds: 5), (timer) async {
        if (answerController.text.isNotEmpty) {
          await applyAnswer();
          timer.cancel(); // Stop the timer once the answer is applied
        }
      });
    } catch (e) {
      log('❌ Error starting screen sharing: $e');
    }
  }

  /// ✅ Stop Screen Sharing
  Future<void> stopScreenSharing() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop()); // Stop tracks
      _localStream = null;
    }

    _localRenderer.srcObject = null; // Clear renderer
    setState(() {}); // Refresh UI

    log("⛔ Screen sharing stopped");

    // Notify all WebSocket clients that the stream has stopped
    for (var client in clients) {
      client.sink.add(jsonEncode({'type': 'stream_stopped'}));
    }

    // Re-initialize the peer connection to allow starting sharing again
    await _initializePeerConnection();
  }

  /// ✅ Create Offer (Flutter → Web)
  Future<void> createOffer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    var offerData = jsonEncode({'type': 'offer', 'sdp': offer.sdp});
    log('📤 Sending Offer via WebSocket...');
    for (var client in clients) {
      client.sink.add(offerData);
    }
  }

  /// ✅ Create Answer (Web → Flutter)
  Future<void> createAnswer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    answerController.text = jsonEncode({
      'sdp': answer.sdp,
      'type': answer.type,
    });

    log('📥 Answer created & set as Local Description');
  }

  /// ✅ Apply Answer (Web → Flutter)
  Future<void> applyAnswer() async {
    if (_peerConnection == null) {
      log('⚠️ Peer connection not initialized');
      return;
    }

    if (answerController.text.isEmpty) {
      log('⚠️ No answer available to apply');
      return;
    }

    final answer = jsonDecode(answerController.text);
    if (_peerConnection?.signalingState ==
        RTCSignalingState.RTCSignalingStateStable) {
      log('⚠️ Already in stable state, skipping setRemoteDescription');
      return;
    }

    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
      log('✅ Answer applied successfully');
    } catch (e) {
      log('❌ Error applying answer: $e');
    }
  }

  /// ✅ Automate sending offer and applying answer
  void _automateOfferAndAnswer() async {
    await Future.delayed(Duration(seconds: 2)); // Wait for initialization
    await createOffer(); // Send offer automatically

    // Periodically check and apply answer if available
    Timer.periodic(Duration(seconds: 5), (timer) async {
      if (answerController.text.isNotEmpty) {
        await applyAnswer();
        timer.cancel(); // Stop the timer once the answer is applied
      }
    });
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
            /// 🔹 WebRTC Video Preview
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

            /// 🔹 Start Sharing Button
            ElevatedButton.icon(
              onPressed: startScreenSharing,
              icon: Icon(Icons.screen_share),
              label: Text('Start Sharing'),
            ),

            SizedBox(height: 20),

            /// 🔹 Stop Sharing Button
            ElevatedButton.icon(
              onPressed: stopScreenSharing,
              icon: Icon(Icons.stop),
              label: Text('Stop Sharing'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
            ),

            SizedBox(height: 20),

            /// 🔹 Answer SDP (Read-Only)
            TextField(
              controller: answerController,
              decoration: InputDecoration(
                labelText: 'Answer SDP',
                border: OutlineInputBorder(),
              ),
              readOnly: true,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
