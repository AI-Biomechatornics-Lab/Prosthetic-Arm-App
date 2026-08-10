class AppConstants {
  // Backend API - Raspberry Pi static IP, via the Caddy TLS proxy on :3443
  // (Firebase Hosting serves this app over HTTPS, so the API must be HTTPS/WSS
  // too or browsers block it as mixed content). The Node backend itself still
  // only listens on plain HTTP on :3000, proxied by Caddy.
  static const String apiHost = '172.29.68.89';
  static const int apiPort = 3443;
  static const String apiBaseUrl = 'https://$apiHost:$apiPort';
  static const String wsBaseUrl = 'wss://$apiHost:$apiPort';

  static const String lastUserIdKey = 'last_user_id';

  static const List<String> gestures = [
    'rest',
    'fist',
    'grasp',
    'index',
    'middle',
    'ring',
    'pinky',
    'thumb',
    'wrist_rotate_out',
    'wrist_rotate_in',
  ];

  static const int repsPerGesture = 3;
  static const int secondsPerRep = 5;

  static const int emgChannelCount = 8;
}
