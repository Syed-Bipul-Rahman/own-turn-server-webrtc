import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  IO.Socket? _socket;
  String? _currentRoom;
  String? _userId;
  
  // Callbacks
  Function(String socketId, RTCSessionDescription offer)? onOfferReceived;
  Function(String socketId, RTCSessionDescription answer)? onAnswerReceived;
  Function(String socketId, RTCIceCandidate candidate)? onIceCandidateReceived;
  Function(String socketId)? onUserJoined;
  Function(String socketId)? onUserLeft;
  Function(String callerSocketId)? onIncomingCall;
  Function(bool accepted, String responderSocketId)? onCallResponse;

  // Connect to signaling server
  void connect(String serverUrl) {
    _socket = IO.io(serverUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .build()
    );

    _socket!.onConnect((_) {
      print('Connected to signaling server');
    });

    _socket!.onDisconnect((_) {
      print('Disconnected from signaling server');
    });

    // Listen for WebRTC signaling events
    _socket!.on('offer', (data) {
      print('Received offer: $data');
      final offer = RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      );
      onOfferReceived?.call(data['senderSocketId'], offer);
    });

    _socket!.on('answer', (data) {
      print('Received answer: $data');
      final answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );
      onAnswerReceived?.call(data['senderSocketId'], answer);
    });

    _socket!.on('ice-candidate', (data) {
      print('Received ICE candidate: $data');
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      onIceCandidateReceived?.call(data['senderSocketId'], candidate);
    });

    _socket!.on('user-joined', (data) {
      print('User joined: $data');
      onUserJoined?.call(data['socketId']);
    });

    _socket!.on('user-left', (data) {
      print('User left: $data');
      onUserLeft?.call(data['socketId']);
    });

    _socket!.on('incoming-call', (data) {
      print('Incoming call: $data');
      onIncomingCall?.call(data['callerSocketId']);
    });

    _socket!.on('call-response', (data) {
      print('Call response: $data');
      onCallResponse?.call(data['accepted'], data['responderSocketId']);
    });

    _socket!.on('room-users', (data) {
      print('Room users: $data');
      // Handle existing users in room
      if (data is List) {
        for (var user in data) {
          onUserJoined?.call(user['socketId']);
        }
      }
    });
  }

  // Join a room
  void joinRoom(String roomId, String userId) {
    _currentRoom = roomId;
    _userId = userId;
    
    _socket?.emit('join-room', {
      'roomId': roomId,
      'userId': userId,
    });
  }

  // Send WebRTC offer
  void sendOffer(String targetSocketId, RTCSessionDescription offer) {
    _socket?.emit('offer', {
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'targetSocketId': targetSocketId,
    });
  }

  // Send WebRTC answer
  void sendAnswer(String targetSocketId, RTCSessionDescription answer) {
    _socket?.emit('answer', {
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
      'targetSocketId': targetSocketId,
    });
  }

  // Send ICE candidate
  void sendIceCandidate(String targetSocketId, RTCIceCandidate candidate) {
    _socket?.emit('ice-candidate', {
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
      'targetSocketId': targetSocketId,
    });
  }

  // Initiate a call
  void initiateCall(String targetSocketId) {
    _socket?.emit('initiate-call', {
      'targetSocketId': targetSocketId,
    });
  }

  // Respond to a call
  void respondToCall(String targetSocketId, bool accepted) {
    _socket?.emit('call-response', {
      'targetSocketId': targetSocketId,
      'accepted': accepted,
    });
  }

  // Disconnect
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _currentRoom = null;
    _userId = null;
  }

  // Getters
  String? get currentRoom => _currentRoom;
  String? get userId => _userId;
  bool get isConnected => _socket?.connected ?? false;
}