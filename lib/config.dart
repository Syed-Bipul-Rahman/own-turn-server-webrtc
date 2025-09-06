class Config {
  // Signaling server configuration
  static const String signalingServerUrl = String.fromEnvironment(
    'SIGNALING_SERVER_URL',
    defaultValue: 'ws://localhost:8080', // Local development
  );
  
  // Production signaling server URL (replace with your GCP deployment URL)
  static const String productionSignalingUrl = 'wss://your-project-id.uc.r.appspot.com';
  
  // TURN server configuration - your existing server
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {
        'urls': 'stun:34.71.140.192:3478'
      },
      {
        'urls': 'turn:34.71.140.192:3478',
        'username': 'bipul',
        'credential': 'rahman'
      }
    ]
  };
  
  // WebRTC configuration
  static const Map<String, dynamic> rtcConfig = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };
  
  // Media constraints
  static const Map<String, dynamic> mediaConstraints = {
    'audio': true,
    'video': {
      'mandatory': {
        'minWidth': '640',
        'minHeight': '480',
        'minFrameRate': '30',
      },
      'facingMode': 'user',
      'optional': [],
    }
  };
  
  // Offer/Answer constraints
  static const Map<String, dynamic> offerAnswerConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
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
    return isDevelopment ? 'ws://localhost:8080' : productionSignalingUrl;
  }
}