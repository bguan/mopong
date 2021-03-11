const BUTTON_SIZE_RATIO = .7;
const PONG_SVC_TYPE = '_mopong._udp';
const PONG_PORT = 13579;
const POP_FILE = 'pop.wav';
const CRASH_FILE = 'crash.wav';
const TADA_FILE = 'tada.wav';
const WAH_FILE = 'wahwah.wav';
const MAIN_MENU_OVERLAY_ID = 'MainMenuOverlay';
const HOST_WAITING_OVERLAY_ID = 'HostWaitingOverlay';
const MAX_SCORE = 3;
const MARGIN_RATIO = .1; // of screen height
const PAD_HEIGHT_RATIO = .01;
const PAD_WIDTH_RATIO = .25; // of screen width
const PAD_SPEED_RATIO = .8; // of screen height per sec
const BALL_SPEED_RATIO = 0.5; // of screen height per sec
const BALL_RAD_RATIO = .005; // of screen height
const SPIN_RATIO = .2; // of screen width, side spin of ball hitting moving pad
const PAUSE_INTERVAL = 2.0; // pause in secs when a point is scored
const MAX_NET_WAIT = Duration(seconds: 5); // assume opponent disconnected after
const SCREEN_NORM_HEIGHT = 1000;
const SCREEN_NORM_WIDTH = 1000;

enum GameMode {
  over, // game is over, showing game over menu
  single, // playing as single player against computer
  wait, // waiting as host for any guest to connect, show waiting menu
  host, // playing as host over network
  guest, // playing as guest over network
}
