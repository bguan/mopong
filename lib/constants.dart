const BUTTON_SIZE_RATIO = .7;
const PONG_GAME_SVC_TYPE = '_pong._udp';
const PONG_GAME_SVC_PORT = 13579;
const POP_FILE = 'pop.wav';
const CRASH_FILE = 'crash.wav';
const TADA_FILE = 'tada.wav';
const WAHWAH_FILE = 'wahwah.wav';
const OVERLAY_ID = 'Overlay';
const MAX_SCORE = 5;
const MARGIN = 80.0;
const PAD_HEIGHT = 10.0;
const PAD_WIDTH = 100.0;
const PAD_SPEED = 300.0; // px/sec
const BALL_RAD = 4.0;
const SPIN = 150.0; // side spin when pad is moving while ball strike
const PAUSE_INTERVAL = 2.0; // pause in secs when a point is scored

enum GameMode {
  over, // game is over, showing game over menu
  single, // playing as single player against computer
  wait, // waiting as host for any guest to connect, show waiting menu
  host, // playing as host over network
  guest, // playing as guest over network
}