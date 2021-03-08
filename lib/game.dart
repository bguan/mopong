import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/game.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flame_audio/flame_audio.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/gestures.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:synchronized/synchronized.dart';

import 'ball.dart';
import 'constants.dart';
import 'namer.dart';
import 'net.dart';
import 'pad.dart';

/// Game class of Mobile Pong.
class MoPongGame extends BaseGame with HorizontalDragDetector {
  final txtCfg = TextConfig(fontSize: 20.0, color: Colors.white);
  final String gameHostHandle = genHostHandle();
  PongNetSvc? pongNetSvc;
  var _mode = GameMode.over; // private so only MoPong can change game mode
  get mode => _mode;

  bool get isOver => mode == GameMode.over;
  bool get isGuest => mode == GameMode.guest;
  bool get isHost => mode == GameMode.host;
  bool get isWaiting => mode == GameMode.wait;
  bool get isSingle => mode == GameMode.single;

  Pad myPad = Pad();
  Pad oppoPad = Pad(false);
  Ball ball = Ball();
  int myScore = 0;
  int oppoScore = 0;
  double lastFingerX = 0.0; // use to track the last finger drag position
  double margin = 50; // until resize
  int sndCount = 0; // to tag network packet sent for ordering
  int rcvCount = -1; // to order network packet received
  DateTime lastRcvTstmp = clock.now(); // timestamp of last received
  double width = 400; // until resize
  double height = 600; // until resize
  String topMsg = '';

  final lock = new Lock(); // to handle concurrent updates

  MoPongGame() : super() {
    pongNetSvc =
        kIsWeb ? null : PongNetSvc(gameHostHandle, _onDiscovery, width, height);
  }

  @override
  onLoad() async {
    add(myPad);
    add(oppoPad);
    add(ball);
    if (!kIsWeb)
      FlameAudio.audioCache
          .loadAll([POP_FILE, CRASH_FILE, TADA_FILE, WAH_FILE]);
  }

  void addMyScore() {
    FlameAudio.play(CRASH_FILE);
    myScore += 1;
    if (myScore >= MAX_SCORE) FlameAudio.play(TADA_FILE);
  }

  void addOpponentScore() {
    FlameAudio.play(CRASH_FILE);
    oppoScore += 1;
    if (oppoScore >= MAX_SCORE) FlameAudio.play(WAH_FILE);
  }

  @override
  void onResize(Vector2 canvasSize) {
    super.onResize(canvasSize);
    height = canvasSize.y;
    width = canvasSize.x;
    margin = MARGIN_RATIO * height;
    if (pongNetSvc != null) {
      pongNetSvc!.width = width;
      pongNetSvc!.height = height;
    }
  }

  @override
  void update(double t) async {
    super.update(t);
    bool endGame = false;
    if (myScore >= MAX_SCORE) {
      endGame = true;
      topMsg = "You've Won!";
    } else if (oppoScore >= MAX_SCORE) {
      endGame = true;
      topMsg = "You've Lost!";
    } else if (isHost || isGuest) {
      final now = clock.now();
      final waitLimit = lastRcvTstmp.add(MAX_NET_WAIT);
      if (now.isAfter(waitLimit)) {
        endGame = true;
        topMsg = "Connection Interrupted.";
      }
    }

    if (endGame) {
      if (isGuest) pongNetSvc?.leaveGame();
      if (isHost) pongNetSvc?.stopHosting();
      showMainMenu();
    }
  }

  // send game state over network.
  // let pad or ball trigger this to reduce traffic.
  void sendStateUpdate() {
    pongNetSvc?.send(
      PongData(
        sndCount++,
        myPad.x,
        ball.x,
        ball.y,
        ball.vx,
        ball.vy,
        ball.pause,
        myScore,
        oppoScore,
      ),
    );
  }

  void _onDiscovery() {
    if (isOver) showMainMenu(); // update game over menu only when isOver
  }

  @override
  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, width, height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);
    txtCfg.render(canvas, "Score $myScore:$oppoScore", Vector2(20, 20));
    super.render(canvas);
  }

  void showMainMenu() {
    _mode = GameMode.over; // just in case coming from weird state
    _safeRemoveOverlay();
    overlays.add(MAIN_MENU_OVERLAY_ID);
  }

  void _safeRemoveOverlay() {
    overlays.remove(MAIN_MENU_OVERLAY_ID);
    overlays.remove(HOST_WAITING_OVERLAY_ID);
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    lastFingerX = details.globalPosition.dx;
  }

  void startSinglePlayer() {
    _safeRemoveOverlay();
    myScore = 0;
    oppoScore = 0;
    _mode = GameMode.single;
    FlameAudio.play(POP_FILE);
  }

  void hostNetGame() async {
    _safeRemoveOverlay();
    _mode = GameMode.wait;
    myScore = 0;
    oppoScore = 0;
    myPad.x = myPad.width / 2;
    ball.x = myPad.width / 2;
    ball.y = margin + 2 * myPad.height;
    ball.vy = ball.speed;
    ball.vx = 0;
    pongNetSvc?.startHosting((p) => _onMsgFromGuest(p), stopHosting);
    overlays.add(HOST_WAITING_OVERLAY_ID);
  }

  void stopHosting() {
    pongNetSvc?.stopHosting();
    showMainMenu();
  }

  void _onMsgFromGuest(PongData data) async {
    if (mode == GameMode.wait) {
      _safeRemoveOverlay();
      _mode = GameMode.host;
    }
    if (mode != GameMode.host) return;
    if (lock.inLock) return; // ignore if in the middle of dealing w last msg
    if (data.count < rcvCount && data.count.sign == rcvCount.sign)
      return; // ignore if out of sequence and not underflow

    lock.synchronized(() => _updateOnReceive(data));
  }

  void joinNetGame(String hostSvcName) async {
    _safeRemoveOverlay();
    _mode = GameMode.guest;
    myScore = 0;
    oppoScore = 0;
    myPad.x = myPad.width / 2;
    ball.x = myPad.width / 2;
    ball.y = height - margin - 2 * myPad.height;
    ball.vy = -ball.speed;
    ball.vx = 0;
    pongNetSvc?.joinGame(hostSvcName, _onMsgFromHost, leaveNetGame);
    lastRcvTstmp = clock.now();
  }

  void leaveNetGame() {
    pongNetSvc?.leaveGame();
    showMainMenu();
  }

  void _onMsgFromHost(PongData data) {
    if (mode != GameMode.guest) return;
    if (lock.inLock) return; // ignore if in the middle of dealing w last
    if (data.count < rcvCount && data.count.sign == rcvCount.sign)
      return; // ignore if out of sequence and not underflow

    lock.synchronized(() => _updateOnReceive(data));
    if (myScore == MAX_SCORE || oppoScore == MAX_SCORE) leaveNetGame();
  }

  void _updateOnReceive(PongData data) async {
    rcvCount = data.count;
    lastRcvTstmp = clock.now();
    oppoPad.x = data.px;
    if (ball.vy < 0) {
      // ball going away from me, let opponent update my states & scores
      if (myScore < data.myScore || oppoScore < data.oppoScore) {
        // score changed, opponent must have detected crashed, play Crash
        if (data.oppoScore == MAX_SCORE) {
          FlameAudio.play(WAH_FILE);
        } else if (data.myScore == MAX_SCORE) {
          FlameAudio.play(TADA_FILE);
        } else {
          FlameAudio.play(CRASH_FILE);
        }
      } else if (ball.vy.sign != data.bvy.sign) {
        // ball Y direction changed, host must have detected hit, play Pop
        FlameAudio.play(POP_FILE);
      }

      myScore = data.myScore;
      oppoScore = data.oppoScore;
      ball.x = data.bx;
      ball.y = data.by;
      ball.vx = data.bvx;
      ball.vy = data.bvy;
      ball.pause = data.pause;
    }
  }
}
