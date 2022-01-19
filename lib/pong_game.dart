import 'package:clock/clock.dart';
import 'package:flame/input.dart';
import 'package:flame/game.dart';
import 'package:flame/widgets.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';
import 'pixel_mapper.dart';
import 'pong_constants.dart';
import 'pong_pad.dart';
import 'pong_ball.dart';
import 'pong_net_svc.dart';
import 'name_generator.dart';

enum GameMode {
  over, // game is over, showing game over menu
  single, // playing as single player against computer
  wait, // waiting as host for any guest to connect, show waiting menu
  host, // playing as host over network
  guest, // playing as guest over network
}

class PongGame extends FlameGame with HorizontalDragDetector {
  static final log = Logger("MoPongGame");

  static const MAIN_MENU_OVERLAY_ID = 'MainMenuOverlay';
  static const HOST_WAITING_OVERLAY_ID = 'HostWaitingOverlay';
  static const TOP_MARGIN = 0.05;
  static const BOTTOM_MARGIN = 0.95;
  static const MAX_SCORE = 3;
  static const INIT_WTH = 100.0; // before game size ready
  static const INIT_HGT = 200.0; // before game size ready

  final String _myNetHandle = NameGenerator.genNewName();
  final TextPaint _txtPaint = TextPaint(
    style: TextStyle(fontSize: 16.0, color: Colors.white),
  );

  final lock = new Lock(); // support concurrency during network callback

  late final PongNetSvc? pongNetSvc;
  late final Map<String, OverlayWidgetBuilder<PongGame>> overlayMap;
  late PixelMapper _pxMap;
  late final Pad myPad;
  late final Pad oppoPad;
  late final Ball ball;

  String _oppoHostHandle = "";
  String _gameMsg = "";
  String get gameMsg => _gameMsg;
  int _myScore = 0;
  int _oppoScore = 0;
  int _sendCount = 0; // to tag network packet sent for ordering
  int _receiveCount = -1; // to order network packet received
  DateTime _lastReceiveTime = clock.now(); // timestamp of last received

  GameMode _mode = GameMode.over; // private so only MoPong can change game mode

  // allow read access to these states
  GameMode get mode => _mode;
  bool get isOver => mode == GameMode.over;
  bool get isGuest => mode == GameMode.guest;
  bool get isHost => mode == GameMode.host;
  bool get isWaiting => mode == GameMode.wait;
  bool get isSingle => mode == GameMode.single;
  int get myScore => _myScore;
  int get oppoScore => _oppoScore;
  double get topMargin => _pxMap.toDevY(TOP_MARGIN);
  double get bottomMargin => _pxMap.toDevY(BOTTOM_MARGIN);
  double get leftMargin => _pxMap.toDevX(0.0);
  double get rightMargin => _pxMap.toDevX(1.0);
  DateTime get lastReceiveTime => _lastReceiveTime;

  PongGame() {
    _pxMap = PixelMapper(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    myPad = Pad(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    oppoPad = Pad(gameWidth: INIT_WTH, gameHeight: INIT_HGT, isPlayer: false);
    ball = Ball(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    pongNetSvc = kIsWeb ? null : PongNetSvc(_myNetHandle, onDiscovery);
    overlayMap = {
      MAIN_MENU_OVERLAY_ID: mainMenuOverlay,
      HOST_WAITING_OVERLAY_ID: hostWaitingOverlay,
    };
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    await FlameAudio.audioCache
        .loadAll([CRASH_FILE, POP_FILE, TADA_FILE, WAH_FILE]);

    add(myPad);
    add(oppoPad);
    add(ball);

    showMainMenu();
  }

  void showMainMenu() {
    _mode = GameMode.over; // just in case coming from weird state
    _safeRemoveOverlay();
    overlays.add(MAIN_MENU_OVERLAY_ID);
  }

  void _reset([GameMode mode = GameMode.over]) {
    _mode = mode;
    _myScore = 0;
    _oppoScore = 0;
    _receiveCount = -1;
    _lastReceiveTime = clock.now();
    final bvy = isHost || isSingle ? Ball.NORM_SPEED : 0.0;
    myPad.reset();
    ball.reset(
      normVY: bvy,
      normX: 0.5,
      normY: 0.5,
    );
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    _pxMap = PixelMapper(gameWidth: gameSize.x, gameHeight: gameSize.y);
  }

  Widget gameButton(String txt, void Function() handler) => Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0),
        child: SizedBox(
          width: _pxMap.toDevWth(.7),
          child: ElevatedButton(
            child: Text(
              txt,
              textAlign: TextAlign.center,
            ),
            onPressed: handler,
          ),
        ),
      );

  Widget mainMenuOverlay(BuildContext ctx, PongGame game) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (game.gameMsg.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Text(game.gameMsg),
              ),
            gameButton('Single Player', game.startSinglePlayer),
            if (!kIsWeb) gameButton('Host Network Game', game.hostNetGame),
            if (!kIsWeb)
              for (var svc in game.pongNetSvc!.serviceNames)
                gameButton('Play $svc', () => game.joinNetGame(svc))
          ],
        ),
      );

  Widget hostWaitingOverlay(BuildContext ctx, PongGame game) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Text('Hosting Game as ${game._myNetHandle}...'),
            ),
            gameButton('Cancel', game.stopHosting),
          ],
        ),
      );

  @override
  void onHorizontalDragUpdate(DragUpdateInfo info) {
    final dragX = info.delta.global.x;
    final endX = info.eventPosition.global.x;
    if (endX >= myPad.x - myPad.width / 2 &&
        endX <= myPad.x + myPad.width / 2) {
      myPad.setPlayerStationary();
    } else if (dragX < 0) {
      myPad.movePlayerLeft();
    } else if (dragX > 0) {
      myPad.movePlayerRight();
    }
  }

  @override
  void onHorizontalDragEnd(DragEndInfo info) {
    myPad.setPlayerStationary();
  }

  void _safeRemoveOverlay() {
    overlays.remove(MAIN_MENU_OVERLAY_ID);
    overlays.remove(HOST_WAITING_OVERLAY_ID);
  }

  void startSinglePlayer() {
    _safeRemoveOverlay();
    _reset(GameMode.single);
    ball.reset(normVY: Ball.NORM_SPEED);
  }

  void hostNetGame() {
    _safeRemoveOverlay();
    _reset(GameMode.wait);
    pongNetSvc?.startHosting(_updateOnReceive, stopHosting);
    overlays.add(HOST_WAITING_OVERLAY_ID);
  }

  void stopHosting() {
    pongNetSvc?.stopHosting();
    showMainMenu();
  }

  void joinNetGame(String netGameName) {
    _safeRemoveOverlay();
    _reset(GameMode.guest);
    pongNetSvc?.joinGame(netGameName, _updateOnReceive, endGame);
    _oppoHostHandle = netGameName;
  }

  void addMyScore() {
    FlameAudio.play(CRASH_FILE);
    _myScore += 1;
    if (_myScore >= MAX_SCORE) FlameAudio.play(TADA_FILE);
  }

  void addOpponentScore() {
    FlameAudio.play(CRASH_FILE);
    _oppoScore += 1;
    if (_oppoScore >= MAX_SCORE) FlameAudio.play(WAH_FILE);
  }

  void endGame() {
    if (isGuest) pongNetSvc?.leaveGame();
    if (isHost) pongNetSvc?.stopHosting();
    _mode = GameMode.over;
    showMainMenu();
  }

  void onDiscovery() {
    if (isOver) showMainMenu(); // update game over menu only when isOver
  }

  void showHostWaitingMenu() {
    overlays.add(HOST_WAITING_OVERLAY_ID);
  }

  void _updateOnReceive(PongData data) async {
    if (mode == GameMode.wait) {
      log.info("Received msg from guest, starting game as host...");
      _safeRemoveOverlay();
      _mode = GameMode.host;
      _receiveCount = data.count;
      ball.reset(normVY: Ball.NORM_SPEED, normX: .5, normY: .5);
    } else if (data.count < _receiveCount) {
      log.warning("Received data count ${data.count} less than last "
          "received count $_receiveCount, ignored...");
      return;
    }

    lock.synchronized(() {
      _receiveCount = data.count;
      oppoPad.setOpponentPos(_pxMap.toDevX(1.0 - data.px));

      if (ball.vy < 0 || data.bvy > 0) {
        // ball going away from me, let opponent update my ball state & scores

        if (myScore < data.myScore || oppoScore < data.oppoScore) {
          // score changed, opponent must have detected crashed, play Crash
          if (data.oppoScore == MAX_SCORE) {
            FlameAudio.play(WAH_FILE);
          } else if (data.myScore == MAX_SCORE) {
            FlameAudio.play(TADA_FILE);
          } else {
            FlameAudio.play(CRASH_FILE);
          }
        } else if (ball.vy.sign == data.bvy.sign) {
          // ball Y direction changed, host must have detected hit, play Pop
          FlameAudio.play(POP_FILE);
        }

        _myScore = data.myScore;
        _oppoScore = data.oppoScore;
        ball.updateOnReceive(
          data.bx,
          data.by,
          data.bvx,
          data.bvy,
          data.pause,
        );
      }
    });

    if (myScore >= MAX_SCORE || oppoScore >= MAX_SCORE) endGame();
  }

  void _sendStateUpdate() {
    final data = PongData(
      _sendCount++,
      _pxMap.toNormX(myPad.x),
      _pxMap.toNormX(ball.x),
      _pxMap.toNormY(ball.y),
      _pxMap.toNormWth(ball.vx),
      _pxMap.toNormHgt(ball.vy),
      ball.pause,
      myScore,
      oppoScore,
    );
    pongNetSvc?.send(data);
  }

  @override
  void update(double t) async {
    super.update(t);
    bool gameIsOver = false;
    if (myScore >= MAX_SCORE) {
      gameIsOver = true;
      _gameMsg = "You've Won!";
    } else if (oppoScore >= MAX_SCORE) {
      gameIsOver = true;
      _gameMsg = "You've Lost!";
    } else if (isHost || isGuest) {
      final now = clock.now();
      final waitLimit = lastReceiveTime.add(MAX_NET_WAIT);
      if (now.isAfter(waitLimit)) {
        gameIsOver = true;
        _gameMsg = "Connection Interrupted.";
      } else {
        _lastReceiveTime = now;
      }
    }

    if (isHost || isGuest) _sendStateUpdate();

    if (gameIsOver) endGame();
  }

  @override
  void render(Canvas canvas) {
    final scoreMsg = "Score $myScore:$oppoScore";
    _txtPaint.render(
      canvas,
      scoreMsg,
      _pxMap.toDevPos(0, 0),
      anchor: Anchor.topLeft,
    );

    late final String modeMsg;
    if (isSingle) {
      modeMsg = "Single Player";
    } else if (isHost) {
      modeMsg = "Hosting as $_myNetHandle";
    } else if (isGuest) {
      modeMsg = "Play against $_oppoHostHandle";
    } else {
      modeMsg = "";
    }

    if (modeMsg.isNotEmpty)
      _txtPaint.render(
        canvas,
        modeMsg,
        _pxMap.toDevPos(1, 0),
        anchor: Anchor.topRight,
      );

    super.render(canvas);
  }
}
