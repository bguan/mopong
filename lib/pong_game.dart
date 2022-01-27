import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flame/input.dart';
import 'package:flame/game.dart';
import 'package:flame/widgets.dart';
import 'package:flame_audio/bgm.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';
import 'name_generator.dart';
import 'pixel_mapper.dart';
import 'pong_constants.dart';
import 'pong_pad.dart';
import 'pong_ball.dart';
import 'pong_net_svc.dart';

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

  final TextPaint _txtPaint = TextPaint(
    style: TextStyle(fontSize: 16.0, color: Colors.white),
  );

  final lock = new Lock(); // support concurrency during network callback

  late final String _myNetHandle;
  late final PongNetSvc? pongNetSvc;
  late final Map<String, OverlayWidgetBuilder<PongGame>> overlayMap;
  late PixelMapper _pxMap;
  late final Pad myPad;
  late final Pad oppoPad;
  late final Ball ball;

  Bgm _music = FlameAudio.bgm..initialize();
  bool _firstLoad = true;
  String _oppoHostHandle = "";
  String _gameMsg = "";
  String get gameMsg => _gameMsg;
  int _myScore = 0;
  int _oppoScore = 0;
  int _sendCount = 0; // to tag network packet sent for ordering
  int _receiveCount = -1; // to order network packet received

  GameMode _mode = GameMode.wait; // private so only MoPong can change game mode
  DateTime _lastReceiveTime = clock.now();

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

  PongGame(Uint8List addressIPv4) {
    _myNetHandle = NameGenerator.genNewName(addressIPv4);
    _pxMap = PixelMapper(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    myPad = Pad(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    oppoPad = Pad(gameWidth: INIT_WTH, gameHeight: INIT_HGT, isPlayer: false);
    ball = Ball(gameWidth: INIT_WTH, gameHeight: INIT_HGT);
    pongNetSvc = kIsWeb || addressIPv4[0] == 0
        ? null
        : PongNetSvc(addressIPv4, _myNetHandle, onDiscovery);
    overlayMap = {
      MAIN_MENU_OVERLAY_ID: mainMenuOverlay,
      HOST_WAITING_OVERLAY_ID: hostWaitingOverlay,
    };
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    await FlameAudio.audioCache.loadAll([
      CRASH_FILE,
      POP_FILE,
      TADA_FILE,
      WAH_FILE,
      BKGND_FILE,
      PLAY_FILE,
      WHISTLE_FILE,
    ]);

    add(myPad);
    add(oppoPad);
    add(ball);
    showMainMenu();
  }

  void showMainMenu() async {
    _mode = GameMode.over;
    if (!kIsWeb || !_firstLoad) {
      await _music.stop();
      await _music.play(BKGND_FILE);
    }
    refreshMainMenu();
  }

  void refreshMainMenu() async {
    overlays.remove(MAIN_MENU_OVERLAY_ID);
    overlays.add(MAIN_MENU_OVERLAY_ID);
  }

  void _reset([GameMode mode = GameMode.over]) {
    _firstLoad = false;
    _mode = mode;
    _myScore = 0;
    _oppoScore = 0;
    _receiveCount = -1;
    final bvy = isHost || isSingle ? Ball.NORM_SPEED : 0.0;
    myPad.reset();
    _lastReceiveTime = clock.now();
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

  void startSinglePlayer() async {
    overlays.remove(MAIN_MENU_OVERLAY_ID);
    if (isSingle) return;
    _reset(GameMode.single);
    ball.reset(normVY: Ball.NORM_SPEED);
    FlameAudio.play(WHISTLE_FILE);
    await _music.stop();
    _music.play(PLAY_FILE);
  }

  void hostNetGame() {
    lock.synchronized(() {
      overlays.remove(MAIN_MENU_OVERLAY_ID);
      overlays.add(HOST_WAITING_OVERLAY_ID);

      if (isWaiting) return;

      _reset(GameMode.wait);
      pongNetSvc!.startHosting(_updateOnReceive, endGame);
    });
  }

  void stopHosting() {
    lock.synchronized(() async {
      pongNetSvc?.stopHosting();
      _reset(GameMode.over);
      overlays.remove(HOST_WAITING_OVERLAY_ID);
      overlays.add(MAIN_MENU_OVERLAY_ID);
    });
  }

  void joinNetGame(String netGameName) async {
    lock.synchronized(() async {
      overlays.remove(MAIN_MENU_OVERLAY_ID);
      _reset(GameMode.guest);
      pongNetSvc?.joinGame(netGameName, _updateOnReceive, endGame);
      _oppoHostHandle = netGameName;
      await FlameAudio.play(WHISTLE_FILE);
      await _music.stop();
      _music.play(PLAY_FILE);
    });
  }

  void addMyScore([maxScore = MAX_SCORE]) async {
    await FlameAudio.play(CRASH_FILE);
    if (myScore < maxScore) _myScore = min(_myScore + 1, maxScore);
  }

  void addOpponentScore([maxScore = MAX_SCORE]) async {
    await FlameAudio.play(CRASH_FILE);
    if (oppoScore < MAX_SCORE) _oppoScore = min(_oppoScore + 1, maxScore);
  }

  void endGame() async {
    lock.synchronized(() async {
      if (isOver) return;

      if (myScore >= MAX_SCORE) {
        await FlameAudio.play(TADA_FILE);
      } else if (_oppoScore >= MAX_SCORE) {
        await FlameAudio.play(WAH_FILE);
      }

      if (isGuest) pongNetSvc?.leaveGame();
      if (isHost) pongNetSvc?.stopHosting();

      _mode = GameMode.over;

      showMainMenu();
    });
  }

  void onDiscovery() {
    if (isOver) refreshMainMenu(); // update game over menu only when isOver
  }

  void _updateOnReceive(PongData data) async {
    _lastReceiveTime = clock.now();

    lock.synchronized(() async {
      if (mode == GameMode.wait) {
        log.info("Received msg from guest, starting game as host...");
        overlays.remove(HOST_WAITING_OVERLAY_ID);
        _mode = GameMode.host;
        _receiveCount = data.count;
        ball.reset(normVY: Ball.NORM_SPEED, normX: .5, normY: .5);
        await FlameAudio.play(WHISTLE_FILE);
        await _music.stop();
        await _music.play(PLAY_FILE);
      } else if (ball.vy == 0 && data.bvy != 0) {
        log.info("Guest just got the first update from host...");
        _receiveCount = data.count;
      } else if (data.count < _receiveCount) {
        log.warning("Received data count ${data.count} less than last "
            "received count $_receiveCount, ignored...");
        return;
      }

      _receiveCount = data.count;
      oppoPad.setOpponentPos(_pxMap.toDevX(1.0 - data.px));

      if (ball.vy < 0 || data.bvy > 0) {
        // ball going away from me let opponent update my ball state

        ball.updateOnReceive(
          data.bx,
          data.by,
          data.bvx,
          data.bvy,
          data.pause,
        );
      }

      if (myScore < data.oppoScore) {
        // score changed, opponent must have detected crashed, play Crash
        if (data.oppoScore >= MAX_SCORE) {
          endGame();
        } else {
          FlameAudio.play(CRASH_FILE);
        }
        _myScore = data.oppoScore;
      } else if (data.by > 0.8 && ball.vy.sign == data.bvy.sign) {
        // ball Y direction changed, opponent must have detected hit, play Pop
        FlameAudio.play(POP_FILE);
      }
    });
  }

  void sendStateUpdate() {
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
      final waitLimit = lastReceiveTime.add(MAX_NET_WAIT);
      if (clock.now().isAfter(waitLimit)) {
        gameIsOver = true;
        _gameMsg = "Connection Interrupted.";
      }
    }

    if (isHost || isGuest) sendStateUpdate();

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
