class Config {
  // Signaling server configuration
  static const String signalingServerUrl = String.fromEnvironment(
    'SIGNALING_SERVER_URL',
    defaultValue: 'webrtc.syedbipul.me', // Local development
  );

  // Production signaling server URL (replace with your GCP deployment URL)
  static const String productionSignalingUrl = 'webrtc.syedbipul.me';

  // TURN server configuration - your existing server
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:34.71.140.192:3478'},
      {
        'urls': 'turn:34.71.140.192:3478',
        'username': 'bipul',
        'credential': 'rahman',
      },
    ],
  };

  // WebRTC configuration
  static const Map<String, dynamic> rtcConfig = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  // Media constraints - optimized for Android stability
  static const Map<String, dynamic> mediaConstraints = {
    'audio': {
      'mandatory': {},
      'optional': [
        {'googEchoCancellation': true},
        {'googNoiseSuppression': true},
        {'googHighpassFilter': true},
      ],
    },
    'video': {
      'mandatory': {
        'minWidth': '320',
        'minHeight': '240', 
        'maxWidth': '1280',
        'maxHeight': '720',
        'minFrameRate': '15',
        'maxFrameRate': '30',
      },
      'facingMode': 'user',
      'optional': [
        {'googCpuOveruseDetection': true},
        {'googNoiseReduction': true},
      ],
    },
  };

  // Offer/Answer constraints
  static const Map<String, dynamic> offerAnswerConstraints = {
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    'optional': [],
  };

  // Environment checks
  static bool get isProduction => const bool.fromEnvironment('dart.vm.product');
  static bool get isDevelopment => !isProduction;

  // Get the appropriate signaling server URL
  static String get currentSignalingUrl {
    const envUrl = String.fromEnvironment('SIGNALING_SERVER_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    return isDevelopment ? 'https://webrtc.syedbipul.me' : 'https://$productionSignalingUrl';
  }
}
