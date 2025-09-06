import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:io';
import 'config.dart';
import 'signaling_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Video Chat',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const WebRTCVideoChat(),
    );
  }
}

class WebRTCVideoChat extends StatefulWidget {
  const WebRTCVideoChat({super.key});

  @override
  State<WebRTCVideoChat> createState() => _WebRTCVideoChatState();
}

class _WebRTCVideoChatState extends State<WebRTCVideoChat>
    with WidgetsBindingObserver {
  final _localVideoRenderer = RTCVideoRenderer();
  final _remoteVideoRenderer = RTCVideoRenderer();
  final _signaling = SignalingService();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isInBackground = false;
  bool _isDisposed = false;
  String _connectionStatus = 'Disconnected';
  String? _remoteSocketId;
  String _currentRoom = 'test-room';
  String _userId = 'user-${Random().nextInt(10000)}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeRenderers();
    _setupSignalingCallbacks();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        _isInBackground = true;
        _pauseCamera();
        break;
      case AppLifecycleState.resumed:
        _isInBackground = false;
        _resumeCamera();
        break;
      case AppLifecycleState.detached:
        _cleanupResources();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cleanupResources();
    super.dispose();
  }

  Future<void> _cleanupResources() async {
    try {
      await _localStream?.dispose();
      _localStream = null;
      await _peerConnection?.dispose();
      _peerConnection = null;
      await _localVideoRenderer.dispose();
      await _remoteVideoRenderer.dispose();
      _signaling.disconnect();
    } catch (e) {
      print('Error cleaning up resources: $e');
    }
  }

  Future<void> _pauseCamera() async {
    if (_localStream != null && !_isDisposed) {
      try {
        _localStream!.getVideoTracks().forEach((track) {
          track.enabled = false;
        });
      } catch (e) {
        print('Error pausing camera: $e');
      }
    }
  }

  Future<void> _resumeCamera() async {
    if (_localStream != null && !_isDisposed && _isVideoEnabled) {
      try {
        _localStream!.getVideoTracks().forEach((track) {
          track.enabled = true;
        });
      } catch (e) {
        print('Error resuming camera: $e');
        // If resume fails, try to reinitialize camera
        await _reinitializeCamera();
      }
    }
  }

  Future<void> _reinitializeCamera() async {
    if (_isDisposed) return;

    try {
      setState(() {
        _connectionStatus = 'Reinitializing camera...';
      });

      // Dispose old stream
      await _localStream?.dispose();
      _localStream = null;
      _localVideoRenderer.srcObject = null;

      // Get new stream
      await _getUserMedia();

      // Update peer connection if exists using addTrack
      if (_peerConnection != null && _localStream != null) {
        await _addLocalStreamToPeerConnection();
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Failed to reinitialize camera: $e';
        });
      }
    }
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

  Future<bool> _requestPermissions() async {
    try {
      // Check current status first
      final cameraStatus = await Permission.camera.status;
      final microphoneStatus = await Permission.microphone.status;

      if (cameraStatus == PermissionStatus.granted &&
          microphoneStatus == PermissionStatus.granted) {
        return true;
      }

      // Request permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final cameraGranted =
          statuses[Permission.camera] == PermissionStatus.granted;
      final micGranted =
          statuses[Permission.microphone] == PermissionStatus.granted;

      if (!cameraGranted) {
        if (!_isDisposed) {
          setState(() {
            _connectionStatus = 'Camera permission required for video calls';
          });
        }
        return false;
      }

      if (!micGranted) {
        if (!_isDisposed) {
          setState(() {
            _connectionStatus =
                'Microphone permission required for audio calls';
          });
        }
        return false;
      }

      return true;
    } catch (e) {
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Permission request failed: $e';
        });
      }
      return false;
    }
  }

  Future<void> _getUserMedia() async {
    if (_isDisposed || _isInBackground) return;

    try {
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Requesting camera access...';
        });
      }

      final permissionsGranted = await _requestPermissions();
      if (!permissionsGranted || _isDisposed) {
        return;
      }

      // Add small delay to ensure camera is ready
      await Future.delayed(const Duration(milliseconds: 500));

      if (_isDisposed) return;

      _localStream = await navigator.mediaDevices.getUserMedia(
        Config.mediaConstraints,
      );

      if (_isDisposed) {
        await _localStream?.dispose();
        return;
      }

      _localVideoRenderer.srcObject = _localStream;

      // Add stream tracks event listeners for Android
      _localStream?.getVideoTracks().forEach((track) {
        track.onEnded = () {
          print('Video track ended');
          if (!_isDisposed) {
            _reinitializeCamera();
          }
        };
      });

      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Camera ready';
        });
      }
    } catch (e) {
      print('Error getting user media: $e');
      if (!_isDisposed) {
        setState(() {
          _connectionStatus =
              'Camera error: ${e.toString().split(':').last.trim()}';
        });

        // Try again with lower quality settings on Android
        if (Platform.isAndroid) {
          await _tryFallbackCamera();
        }
      }
    }
  }

  Future<void> _tryFallbackCamera() async {
    if (_isDisposed) return;

    try {
      const fallbackConstraints = {
        'audio': true,
        'video': {
          'mandatory': {
            'minWidth': '240',
            'minHeight': '180',
            'maxWidth': '640',
            'maxHeight': '480',
            'minFrameRate': '10',
            'maxFrameRate': '15',
          },
          'facingMode': 'user',
          'optional': [],
        },
      };

      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Trying lower quality camera...';
        });
      }

      _localStream = await navigator.mediaDevices.getUserMedia(
        fallbackConstraints,
      );

      if (_isDisposed) {
        await _localStream?.dispose();
        return;
      }

      _localVideoRenderer.srcObject = _localStream;

      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Camera ready (reduced quality)';
        });
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Camera unavailable: $e';
        });
      }
    }
  }

  // NEW METHOD: Add local stream tracks to peer connection using addTrack
  Future<void> _addLocalStreamToPeerConnection() async {
    if (_peerConnection == null || _localStream == null || _isDisposed) return;

    try {
      // Add audio tracks
      for (var audioTrack in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(audioTrack, _localStream!);
      }

      // Add video tracks
      for (var videoTrack in _localStream!.getVideoTracks()) {
        await _peerConnection!.addTrack(videoTrack, _localStream!);
      }

      print(
        'Added ${_localStream!.getAudioTracks().length} audio tracks and ${_localStream!.getVideoTracks().length} video tracks',
      );
    } catch (e) {
      print('Error adding tracks to peer connection: $e');
      throw e;
    }
  }

  Future<void> _createPeerConnection() async {
    if (_isDisposed) return;

    try {
      // UPDATED: Use Plan B SDP semantics to avoid the Unified Plan issue
      final configuration = Map<String, dynamic>.from(Config.iceServers);
      configuration['sdpSemantics'] = 'plan-b'; // Force Plan B semantics

      _peerConnection = await createPeerConnection(
        configuration,
        Config.rtcConfig,
      );

      if (_isDisposed) {
        await _peerConnection?.dispose();
        return;
      }

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (_remoteSocketId != null && !_isDisposed) {
          _signaling.sendIceCandidate(_remoteSocketId!, candidate);
        }
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        if (!_isDisposed) {
          setState(() {
            _connectionStatus =
                'ICE Connection: ${state.toString().split('.').last}';
            _isConnected =
                state == RTCIceConnectionState.RTCIceConnectionStateConnected;
          });

          // Handle connection failures
          if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            _handleConnectionFailure();
          }
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (!_isDisposed) {
          print('Peer connection state: $state');
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _handleConnectionFailure();
          }
        }
      };

      // UPDATED: Handle both onAddStream (for Plan B) and onTrack (for Unified Plan)
      _peerConnection!.onAddStream = (MediaStream stream) {
        if (!_isDisposed) {
          setState(() {
            _remoteVideoRenderer.srcObject = stream;
            _connectionStatus = 'Connected to peer';
          });
        }
      };

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (!_isDisposed && event.streams.isNotEmpty) {
          setState(() {
            _remoteVideoRenderer.srcObject = event.streams[0];
            _connectionStatus = 'Connected to peer (track)';
          });
        }
      };

      _peerConnection!.onRemoveStream = (MediaStream stream) {
        if (!_isDisposed) {
          setState(() {
            _remoteVideoRenderer.srcObject = null;
            _connectionStatus = 'Peer disconnected';
          });
        }
      };

      // UPDATED: Use addTrack instead of addStream for better compatibility
      if (_localStream != null && !_isDisposed) {
        try {
          // Try Plan B approach first (addStream)
          await _peerConnection!.addStream(_localStream!);
          print('Successfully added stream using addStream (Plan B)');
        } catch (e) {
          print('addStream failed, trying addTrack: $e');
          // If addStream fails, try addTrack approach
          await _addLocalStreamToPeerConnection();
        }
      }

      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Peer connection ready';
        });
      }
    } catch (e) {
      print('Error creating peer connection: $e');
      if (!_isDisposed) {
        setState(() {
          _connectionStatus =
              'Connection error: ${e.toString().split(':').last.trim()}';
        });
      }
    }
  }

  void _handleConnectionFailure() {
    print('Connection failed, attempting to reconnect...');
    if (!_isDisposed) {
      setState(() {
        _connectionStatus = 'Connection failed, retrying...';
      });

      // Restart the connection after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (!_isDisposed && _remoteSocketId != null) {
          _restartConnection();
        }
      });
    }
  }

  Future<void> _restartConnection() async {
    if (_isDisposed) return;

    try {
      // Close existing connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Reinitialize camera if needed
      if (_localStream == null) {
        await _getUserMedia();
      }

      // Create new peer connection
      await _createPeerConnection();

      // Restart the call process
      if (_remoteSocketId != null) {
        await _createOffer();
      }
    } catch (e) {
      print('Error restarting connection: $e');
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Restart failed: $e';
        });
      }
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null || _remoteSocketId == null) return;

    try {
      RTCSessionDescription description = await _peerConnection!.createOffer(
        Config.offerAnswerConstraints,
      );
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
      RTCSessionDescription description = await _peerConnection!.createAnswer(
        Config.offerAnswerConstraints,
      );
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
    if (_localStream != null && !_isDisposed) {
      try {
        _localStream!.getAudioTracks().forEach((track) {
          track.enabled = _isMuted;
        });
        setState(() {
          _isMuted = !_isMuted;
        });
      } catch (e) {
        print('Error toggling mute: $e');
      }
    }
  }

  void _toggleVideo() {
    if (_localStream != null && !_isDisposed) {
      try {
        _localStream!.getVideoTracks().forEach((track) {
          track.enabled = !_isVideoEnabled;
        });
        setState(() {
          _isVideoEnabled = !_isVideoEnabled;
        });
      } catch (e) {
        print('Error toggling video: $e');
        // If toggling fails, try to reinitialize camera
        if (_isVideoEnabled) {
          _reinitializeCamera();
        }
      }
    }
  }

  void _hangUp() async {
    if (_isDisposed) return;

    try {
      setState(() {
        _connectionStatus = 'Disconnecting...';
        _isConnected = false;
      });

      // Close peer connection first
      await _peerConnection?.close();
      _peerConnection = null;

      // Dispose local stream
      await _localStream?.dispose();
      _localStream = null;

      // Clear video renderers
      _localVideoRenderer.srcObject = null;
      _remoteVideoRenderer.srcObject = null;

      // Reset remote socket
      _remoteSocketId = null;

      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Disconnected';
        });
      }
    } catch (e) {
      print('Error during hang up: $e');
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Disconnected';
        });
      }
    }
  }

  void _startCall() async {
    if (_isDisposed) return;

    try {
      // Connect to signaling server
      if (!_isDisposed) {
        setState(() {
          _connectionStatus = 'Connecting to server...';
        });
      }

      _signaling.connect(Config.currentSignalingUrl);

      // Wait for connection
      await Future.delayed(const Duration(seconds: 2));

      if (_isDisposed) return;

      // Check if connected
      if (!_signaling.isConnected) {
        setState(() {
          _connectionStatus = 'Server connection failed';
        });
        return;
      }

      // Join room
      _signaling.joinRoom(_currentRoom, _userId);

      // Get user media and create peer connection
      await _getUserMedia();

      if (_isDisposed) return;

      if (_localStream != null) {
        await _createPeerConnection();

        if (!_isDisposed) {
          setState(() {
            _connectionStatus = 'Ready - waiting for peer...';
          });
        }
      } else {
        setState(() {
          _connectionStatus = 'Camera initialization failed';
        });
      }
    } catch (e) {
      print('Error starting call: $e');
      if (!_isDisposed) {
        setState(() {
          _connectionStatus =
              'Start failed: ${e.toString().split(':').last.trim()}';
        });
      }
    }
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                  onPressed: _isConnected
                      ? null
                      : (_remoteSocketId == null ? _startCall : _initiateCall),
                  icon: const Icon(Icons.call),
                  label: Text(
                    _remoteSocketId == null ? 'Join Room' : 'Call Peer',
                  ),
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
                  icon: Icon(
                    _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                  ),
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
