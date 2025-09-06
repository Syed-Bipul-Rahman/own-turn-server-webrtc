import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'config.dart';
import 'signaling_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Video Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WebRTCVideoChat(),
    );
  }
}

class WebRTCVideoChat extends StatefulWidget {
  const WebRTCVideoChat({super.key});

  @override
  State<WebRTCVideoChat> createState() => _WebRTCVideoChatState();
}

class _WebRTCVideoChatState extends State<WebRTCVideoChat> {
  final _localVideoRenderer = RTCVideoRenderer();
  final _remoteVideoRenderer = RTCVideoRenderer();
  final _signaling = SignalingService();
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  String _connectionStatus = 'Disconnected';
  String? _remoteSocketId;
  String _currentRoom = 'test-room';
  String _userId = 'user-${Random().nextInt(10000)}';

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
    _setupSignalingCallbacks();
  }

  @override
  void dispose() {
    _localVideoRenderer.dispose();
    _remoteVideoRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();
    _signaling.disconnect();
    super.dispose();
  }

  Future<void> _initializeRenderers() async {
    await _localVideoRenderer.initialize();
    await _remoteVideoRenderer.initialize();
    setState(() {
      _isInitialized = true;
    });
  }

  void _setupSignalingCallbacks() {
    _signaling.onOfferReceived = (socketId, offer) async {
      _remoteSocketId = socketId;
      await _handleReceivedOffer(offer);
    };

    _signaling.onAnswerReceived = (socketId, answer) async {
      await _handleReceivedAnswer(answer);
    };

    _signaling.onIceCandidateReceived = (socketId, candidate) async {
      await _handleReceivedIceCandidate(candidate);
    };

    _signaling.onUserJoined = (socketId) {
      setState(() {
        _connectionStatus = 'User joined: $socketId';
        _remoteSocketId = socketId;
      });
    };

    _signaling.onUserLeft = (socketId) {
      setState(() {
        _connectionStatus = 'User left';
        _remoteSocketId = null;
      });
    };

    _signaling.onIncomingCall = (callerSocketId) {
      _remoteSocketId = callerSocketId;
      _signaling.respondToCall(callerSocketId, true);
    };
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();
  }

  Future<void> _getUserMedia() async {
    try {
      await _requestPermissions();
      _localStream = await navigator.mediaDevices.getUserMedia(Config.mediaConstraints);
      _localVideoRenderer.srcObject = _localStream;

      setState(() {
        _connectionStatus = 'Local media ready';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error getting media: $e';
      });
    }
  }

  Future<void> _createPeerConnection() async {
    try {
      _peerConnection = await createPeerConnection(Config.iceServers, Config.rtcConfig);

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (_remoteSocketId != null) {
          _signaling.sendIceCandidate(_remoteSocketId!, candidate);
        }
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        setState(() {
          _connectionStatus = 'ICE Connection: ${state.toString()}';
          _isConnected = state == RTCIceConnectionState.RTCIceConnectionStateConnected;
        });
      };

      _peerConnection!.onAddStream = (MediaStream stream) {
        setState(() {
          _remoteVideoRenderer.srcObject = stream;
          _connectionStatus = 'Remote stream received';
        });
      };

      if (_localStream != null) {
        await _peerConnection!.addStream(_localStream!);
      }

      setState(() {
        _connectionStatus = 'Peer connection created';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error creating peer connection: $e';
      });
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null || _remoteSocketId == null) return;

    try {
      RTCSessionDescription description = await _peerConnection!.createOffer(Config.offerAnswerConstraints);
      await _peerConnection!.setLocalDescription(description);
      _signaling.sendOffer(_remoteSocketId!, description);

      setState(() {
        _connectionStatus = 'Offer sent';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error creating offer: $e';
      });
    }
  }

  Future<void> _createAnswer() async {
    if (_peerConnection == null || _remoteSocketId == null) return;

    try {
      RTCSessionDescription description = await _peerConnection!.createAnswer(Config.offerAnswerConstraints);
      await _peerConnection!.setLocalDescription(description);
      _signaling.sendAnswer(_remoteSocketId!, description);

      setState(() {
        _connectionStatus = 'Answer sent';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error creating answer: $e';
      });
    }
  }

  Future<void> _handleReceivedOffer(RTCSessionDescription offer) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.setRemoteDescription(offer);
      await _createAnswer();
      
      setState(() {
        _connectionStatus = 'Offer received, answer sent';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error handling offer: $e';
      });
    }
  }

  Future<void> _handleReceivedAnswer(RTCSessionDescription answer) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.setRemoteDescription(answer);
      
      setState(() {
        _connectionStatus = 'Answer received';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error handling answer: $e';
      });
    }
  }

  Future<void> _handleReceivedIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;

    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error adding ICE candidate: $e';
      });
    }
  }

  void _toggleMute() {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isMuted;
      });
      setState(() {
        _isMuted = !_isMuted;
      });
    }
  }

  void _toggleVideo() {
    if (_localStream != null) {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = !_isVideoEnabled;
      });
      setState(() {
        _isVideoEnabled = !_isVideoEnabled;
      });
    }
  }

  void _hangUp() {
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _localVideoRenderer.srcObject = null;
    _remoteVideoRenderer.srcObject = null;
    
    setState(() {
      _isConnected = false;
      _connectionStatus = 'Disconnected';
    });
  }

  void _startCall() async {
    // Connect to signaling server
    setState(() {
      _connectionStatus = 'Connecting to signaling server...';
    });
    
    _signaling.connect(Config.currentSignalingUrl);
    
    // Wait a moment for connection
    await Future.delayed(const Duration(seconds: 1));
    
    // Join room
    _signaling.joinRoom(_currentRoom, _userId);
    
    // Get user media and create peer connection
    await _getUserMedia();
    await _createPeerConnection();
    
    setState(() {
      _connectionStatus = 'Ready for call - waiting for peer...';
    });
  }

  void _initiateCall() async {
    if (_remoteSocketId != null) {
      _signaling.initiateCall(_remoteSocketId!);
      await _createOffer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Video Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isConnected ? Colors.green[100] : Colors.red[100],
            child: Text(
              _connectionStatus,
              style: TextStyle(
                color: _isConnected ? Colors.green[800] : Colors.red[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // Video containers
          Expanded(
            child: Stack(
              children: [
                // Remote video (full screen)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black,
                  child: _remoteVideoRenderer.srcObject != null
                      ? RTCVideoView(_remoteVideoRenderer)
                      : const Center(
                          child: Text(
                            'Remote Video',
                            style: TextStyle(color: Colors.white, fontSize: 24),
                          ),
                        ),
                ),
                
                // Local video (picture-in-picture)
                Positioned(
                  top: 20,
                  right: 20,
                  width: 120,
                  height: 160,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _localVideoRenderer.srcObject != null
                          ? RTCVideoView(_localVideoRenderer, mirror: true)
                          : Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Control buttons
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Start call button
                ElevatedButton.icon(
                  onPressed: _isConnected ? null : (_remoteSocketId == null ? _startCall : _initiateCall),
                  icon: const Icon(Icons.call),
                  label: Text(_remoteSocketId == null ? 'Join Room' : 'Call Peer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                
                // Mute button
                IconButton(
                  onPressed: _isMuted ? null : _toggleMute,
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                  color: _isMuted ? Colors.red : Colors.blue,
                  iconSize: 32,
                ),
                
                // Video toggle button
                IconButton(
                  onPressed: _toggleVideo,
                  icon: Icon(_isVideoEnabled ? Icons.videocam : Icons.videocam_off),
                  color: _isVideoEnabled ? Colors.blue : Colors.red,
                  iconSize: 32,
                ),
                
                // Hang up button
                ElevatedButton.icon(
                  onPressed: _isConnected ? _hangUp : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('End Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Technical details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TURN Server Configuration:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('STUN: stun:34.71.140.192:3478'),
                Text('TURN: turn:34.71.140.192:3478'),
                Text('Username: bipul'),
                const SizedBox(height: 8),
                Text(
                  'Note: This is a demo app. For production use, implement proper signaling server.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
