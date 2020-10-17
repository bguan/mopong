import 'dart:ui';
import 'package:flame/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flame/gestures.dart';
import 'package:flame/position.dart';
import 'package:flame/text_config.dart';
import 'package:flutter/material.dart';
import 'package:synchronized/synchronized.dart';

import 'ball.dart';
import 'constants.dart';
import 'namer.dart';
import 'net.dart';
import 'pad.dart';

/// Game class of Mobile Pong.
class MoPong extends BaseGame with HasWidgetsOverlay, HorizontalDragDetector {
  final audio = FlameAudio();
  final txtCfg = TextConfig(fontSize: 20.0, color: Colors.white);
  final String myName = genName();
  PongNetSvc svc;
  Widget overlay;
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
  double width = 400; // until resize
  double height = 600; // until resize

  final lock = new Lock(); // to handle concurrent updates

  MoPong() : super() {
    add(myPad);
    add(oppoPad);
    add(ball);
    audio.disableLog();
    audio.loadAll([CRASH_FILE, CRASH_FILE, TADA_FILE, WAHWAH_FILE]);
    svc = PongNetSvc(myName, _onDiscovery, width, height);
  }

  void addMyScore() {
    audio.play(CRASH_FILE);
    myScore += 1;
    if (myScore >= MAX_SCORE) audio.play(TADA_FILE);
  }

  void addOpponentScore() {
    audio.play(CRASH_FILE);
    oppoScore += 1;
    if (oppoScore >= MAX_SCORE) audio.play(WAHWAH_FILE);
  }

  @override
  void resize(Size size) {
    super.resize(size);
    height = size.height;
    width = size.width;
    margin = MARGIN_RATIO * height;
    svc.width = width;
    svc.height = height;
  }

  @override
  void update(double t) async {
    super.update(t);
    if (myScore >= MAX_SCORE || oppoScore >= MAX_SCORE) {
      if (isGuest) svc.leaveGame();
      if (isHost) svc.stopHosting();
      _showGameOverMenu();
    }
  }

  // send game state over network.
  // let pad or ball trigger this to reduce traffic.
  void sendStateUpdate() {
    svc.send(
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
    if (isOver) _showGameOverMenu(); // update game over menu only when isOver
  }

  @override
  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, width, height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);
    if (isOver && overlay == null) _showGameOverMenu();
    txtCfg.render(canvas, "Score $myScore:$oppoScore", Position(20, 20));
    super.render(canvas);
  }

  void _showGameOverMenu() {
    _mode = GameMode.over; // just in case coming from weird state
    _safeRemoveOverlay();
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _gameButton('Single Player', _startSinglePlayer),
          _gameButton('Host Network Game', _hostNetGame),
          for (var sname in svc.serviceNames)
            _gameButton('Play $sname', () => _joinNetGame(sname))
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void _safeRemoveOverlay() {
    if (overlay == null) return;
    removeWidgetOverlay(OVERLAY_ID);
    overlay = null;
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    lastFingerX = details.globalPosition.dx;
  }

  Widget _gameButton(String txt, void Function() handler) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0),
      child: SizedBox(
        width: BUTTON_SIZE_RATIO * width,
        child: RaisedButton(child: Text(txt), onPressed: handler),
      ),
    );
  }

  void _startSinglePlayer() {
    _safeRemoveOverlay();
    myScore = 0;
    oppoScore = 0;
    _mode = GameMode.single;
    audio.play(POP_FILE);
  }

  void _hostNetGame() async {
    _safeRemoveOverlay();
    _mode = GameMode.wait;
    myScore = 0;
    oppoScore = 0;
    myPad.x = myPad.width / 2;
    ball.x = myPad.width / 2;
    ball.y = margin + 2 * myPad.height;
    ball.vy = ball.speed;
    ball.vx = 0;
    svc.startHosting((p) => _onMsgFromGuest(p), _stopHosting);
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text('Hosting Game as $myName...'),
          ),
          _gameButton('Cancel', _stopHosting),
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void _stopHosting() {
    svc.stopHosting();
    _showGameOverMenu();
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

  void _joinNetGame(String hostSvcName) async {
    _safeRemoveOverlay();
    _mode = GameMode.guest;
    myScore = 0;
    oppoScore = 0;
    myPad.x = myPad.width / 2;
    ball.x = myPad.width / 2;
    ball.y = height - margin - 2 * myPad.height;
    ball.vy = -ball.speed;
    ball.vx = 0;
    svc.joinGame(hostSvcName, _onMsgFromHost, _leaveNetGame);
  }

  void _leaveNetGame() {
    svc.leaveGame();
    _showGameOverMenu();
  }

  void _onMsgFromHost(PongData data) {
    if (mode != GameMode.guest) return;
    if (lock.inLock) return; // ignore if in the middle of dealing w last
    if (data.count < rcvCount && data.count.sign == rcvCount.sign)
      return; // ignore if out of sequence and not underflow

    lock.synchronized(() => _updateOnReceive(data));
    if (myScore == MAX_SCORE || oppoScore == MAX_SCORE) _leaveNetGame();
  }

  void _updateOnReceive(PongData data) async {
    rcvCount = data.count;
    oppoPad.x = data.px;
    if (ball.vy < 0) {
      // ball going away from me, let opponent update my states & scores
      if (myScore < data.myScore || oppoScore < data.oppoScore) {
        // score changed, opponent must have detected crashed, play Crash
        if (data.oppoScore == MAX_SCORE) {
          audio.play(WAHWAH_FILE);
        } else if (data.myScore == MAX_SCORE) {
          audio.play(TADA_FILE);
        } else {
          audio.play(CRASH_FILE);
        }
      } else if (ball.vy.sign != data.bvy.sign) {
        // ball Y direction changed, host must have detected hit, play Pop
        audio.play(POP_FILE);
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
