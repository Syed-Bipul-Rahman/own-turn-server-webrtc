# WebRTC Video Chat Flutter App

A comprehensive Flutter WebRTC application for real-time video and audio communication using your TURN server configuration.

## Features

- **Real-time Video & Audio Communication**: High-quality peer-to-peer video calls
- **TURN/STUN Server Integration**: Uses your custom TURN server (`34.71.140.192:3478`)
- **Camera & Audio Controls**: Toggle video and mute/unmute audio during calls
- **Picture-in-Picture**: Local video overlay during calls
- **Permission Management**: Automatic camera and microphone permission handling
- **Cross-platform**: Works on both Android and iOS
- **Signaling Server**: Complete Node.js WebSocket signaling server included

## TURN Server Configuration

The app is configured with your TURN server:

```json
{
  "iceServers": [
    {
      "urls": "stun:34.71.140.192:3478"
    },
    {
      "urls": "turn:34.71.140.192:3478",
      "username": "bipul",
      "credential": "rahman"
    }
  ]
}
```

## Project Structure

```
webrtc_test/
├── lib/
│   ├── main.dart              # Main Flutter app with WebRTC UI
│   └── signaling_service.dart # SignalingService for WebSocket communication
├── android/                   # Android-specific configurations
├── ios/                      # iOS-specific configurations  
├── signaling_server.js       # Node.js signaling server
├── package.json              # Node.js dependencies
└── pubspec.yaml              # Flutter dependencies
```

## Setup Instructions

### Prerequisites

- Flutter SDK (3.9.0+)
- Node.js (14+)
- Android Studio / Xcode for device testing
- Physical devices for testing (WebRTC requires real devices, not emulators)

### 1. Flutter App Setup

```bash
# Install Flutter dependencies
flutter pub get

# For Android
flutter run -d android

# For iOS
flutter run -d ios
```

### 2. Signaling Server Setup

```bash
# Install Node.js dependencies
npm install

# Start the signaling server
npm start

# Or for development with auto-reload
npm run dev
```

The signaling server will run on `http://localhost:3000`

### 3. Server Endpoints

- **Health Check**: `GET /health` - Server status and statistics
- **Room Info**: `GET /rooms/:roomId` - Get users in a specific room

## Dependencies

### Flutter Dependencies
- `flutter_webrtc: ^0.9.36` - WebRTC implementation for Flutter
- `permission_handler: ^11.0.1` - Camera/microphone permissions
- `socket_io_client: ^2.0.3+1` - WebSocket client for signaling

### Node.js Dependencies
- `express: ^4.18.2` - Web server framework
- `socket.io: ^4.7.2` - WebSocket server for signaling
- `cors: ^2.8.5` - Cross-origin resource sharing

## How It Works

### WebRTC Flow

1. **Initialization**: App initializes video renderers and requests permissions
2. **Media Access**: Gets user's camera and microphone streams
3. **Peer Connection**: Creates RTCPeerConnection with your TURN server
4. **Signaling**: Uses WebSocket server to exchange offers, answers, and ICE candidates
5. **Connection**: Establishes peer-to-peer connection for audio/video

### Signaling Server Events

**Client → Server**:
- `join-room` - Join a video call room
- `offer` - Send WebRTC offer
- `answer` - Send WebRTC answer  
- `ice-candidate` - Send ICE candidate
- `initiate-call` - Start a call with another user

**Server → Client**:
- `user-joined` - New user joined room
- `user-left` - User left room
- `offer` - Received WebRTC offer
- `answer` - Received WebRTC answer
- `ice-candidate` - Received ICE candidate
- `incoming-call` - Someone is calling you

## Usage

### Basic Call Flow

1. **Start the signaling server**: `npm start`
2. **Run the Flutter app** on two devices
3. **Press "Start Call"** to:
   - Request camera/microphone permissions
   - Access local media stream
   - Create peer connection with your TURN server
   - Simulate call initiation (in demo mode)

### Demo Features

- **Start Call**: Initiates the WebRTC connection process
- **Mute/Unmute**: Toggle audio during call  
- **Video On/Off**: Toggle video during call
- **End Call**: Terminate the connection and cleanup

### Production Integration

To use with a real signaling server:

1. Update the signaling server URL in your Flutter app
2. Replace the demo `_simulateCall()` with real signaling logic
3. Implement proper room management and user authentication
4. Add error handling and reconnection logic

## Permissions

### Android Permissions (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS Permissions (Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to camera for video calling.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone for audio calling.</string>
```

## Testing

### Requirements for Testing
- **Two physical devices** (Android/iOS)
- **Same network** or proper TURN server configuration
- **Camera and microphone permissions** granted

### Test Scenarios
1. **Local Media**: Verify camera feed appears in local video view
2. **Peer Connection**: Check connection status updates  
3. **ICE Gathering**: Monitor ICE candidate generation
4. **Audio/Video Controls**: Test mute and video toggle functions

## Troubleshooting

### Common Issues

**No Video/Audio**:
- Check device permissions
- Ensure physical device (not emulator)
- Verify TURN server accessibility

**Connection Failed**:
- Check TURN server credentials
- Verify network connectivity
- Monitor signaling server logs

**ICE Connection Failed**:
- Test STUN/TURN server accessibility
- Check firewall/NAT configuration
- Verify ICE candidate exchange

### Debug Information

The app displays:
- Connection status in real-time
- TURN server configuration
- Technical details for debugging

## Production Considerations

### Security
- Implement proper authentication
- Use HTTPS/WSS for production
- Rotate TURN server credentials regularly
- Add rate limiting to signaling server

### Scalability  
- Implement room-based architecture
- Add load balancing for multiple signaling servers
- Use Redis for session management
- Monitor TURN server usage

### Quality
- Add adaptive bitrate control  
- Implement network quality monitoring
- Add reconnection logic
- Handle poor network conditions

## License

MIT License - Feel free to use this code for your projects.

## Support

For issues related to:
- **Flutter WebRTC**: Check [flutter_webrtc documentation](https://github.com/flutter-webrtc/flutter-webrtc)
- **TURN Server**: Verify server status and credentials
- **Signaling**: Check WebSocket connection and server logs
