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
  PongNetSvc svc = null;
  Widget overlay = null;
  var _mode = GameMode.over;
  get mode => _mode;

  bool get isOver => mode == GameMode.over;
  Pad myPad = Pad();
  Pad oppoPad = Pad(false);
  Ball ball = Ball();
  int mySc = 0;
  int oSc = 0;
  double lastFingerX = 0.0;

  final _lock = new Lock(); // to coordinate multiple incoming packets

  MoPong() : super() {
    add(myPad);
    add(oppoPad);
    add(ball);
    audio.disableLog();
    audio.loadAll([CRASH_FILE, CRASH_FILE, TADA_FILE, WAHWAH_FILE]);
  }

  void addMyScore() {
    if (mode == GameMode.single || mode == GameMode.host) {
      audio.play(CRASH_FILE);
      mySc += 1;
      if (mySc >= MAX_SCORE) {
        audio.play(TADA_FILE);
      }
    }
  }

  void addOpponentScore() {
    if (mode == GameMode.single || mode == GameMode.host) {
      audio.play(CRASH_FILE);
      oSc += 1;
      if (oSc >= MAX_SCORE) {
        audio.play(WAHWAH_FILE);
      }
    }
  }

  @override
  void resize(Size size) {
    super.resize(size);
    if (svc == null) {
      svc = PongNetSvc(myName, onDiscovery, size.width, size.height);
    } else {
      svc.width = size.width;
      svc.height = size.height;
    }
  }

  @override
  void update(double t) async {
    super.update(t);
    if (mode == GameMode.guest || mode == GameMode.host)
      svc.send(PongData(myPad.x, ball.x, ball.y, ball.vx, ball.vy, mySc, oSc));

    if (mySc >= MAX_SCORE || oSc >= MAX_SCORE) {
      if (mode == GameMode.guest) svc.leaveGame();
      if (mode == GameMode.host) svc.stopHosting();
      showGameOverMenu();
    }
  }

  void onDiscovery() {
    if (isOver) showGameOverMenu(); // update game over menu only when isOver
  }

  @override
  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);
    if (isOver && overlay == null) showGameOverMenu();
    txtCfg.render(canvas, "Score ${mySc}:${oSc}", Position(20, 20));
    super.render(canvas);
  }

  void showGameOverMenu() {
    _mode = GameMode.over; // just in case coming from weird state
    _safeRemoveOverlay();
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _gameButton('Single Player', _startSinglePlayer),
          if (svc != null) _gameButton('Host Network Game', _hostNetGame),
          if (svc != null)
            for (var sname in svc.serviceNames)
              _gameButton('Play ${sname}', () => _joinNetGame(sname))
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void _safeRemoveOverlay() {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    lastFingerX = details.globalPosition.dx;
  }

  Widget _gameButton(String txt, Function handler) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0),
      child: SizedBox(
        width: BUTTON_SIZE_RATIO * size.width,
        child: RaisedButton(child: Text(txt), onPressed: handler),
      ),
    );
  }

  void _startSinglePlayer() {
    _safeRemoveOverlay();
    mySc = 0;
    oSc = 0;
    _mode = GameMode.single;
    audio.play(POP_FILE);
  }

  void _hostNetGame() async {
    _safeRemoveOverlay();
    _mode = GameMode.wait;
    mySc = 0;
    oSc = 0;
    myPad.x = PAD_WIDTH / 2;
    ball.x = PAD_WIDTH / 2;
    ball.y = MARGIN + 2 * PAD_HEIGHT;
    ball.vy = BALL_SPEED;
    ball.vx = 0;
    svc.startHosting((p) => _onMsgFromGuest(p), _stopHosting);
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text('Hosting Game as ${myName}...'),
          ),
          _gameButton('Cancel', _stopHosting),
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void _stopHosting() {
    svc.stopHosting();
    showGameOverMenu();
  }

  void _onMsgFromGuest(PongData data) async {
    if (mode == GameMode.wait) {
      _safeRemoveOverlay();
      _mode = GameMode.host;
    }
    if (mode != GameMode.host) return;

    if (_lock.inLock) return; // ignore if in the middle of dealing w last

    _lock.synchronized(() async {
      // only take oppo pad X from guest
      oppoPad.x = data.px;
    });
  }

  void _joinNetGame(String hostSvcName) async {
    _safeRemoveOverlay();
    _mode = GameMode.guest;
    mySc = 0;
    oSc = 0;
    myPad.x = PAD_WIDTH / 2;
    ball.x = PAD_WIDTH / 2;
    ball.y = size.height - MARGIN - 2 * PAD_HEIGHT;
    ball.vy = -BALL_SPEED;
    ball.vx = 0;
    svc.joinGame(hostSvcName, _onMsgFromHost, _leaveNetGame);
  }

  void _leaveNetGame() {
    svc.leaveGame();
    showGameOverMenu();
  }

  void _onMsgFromHost(PongData data) {
    if (mode != GameMode.guest) return;

    if (_lock.inLock) return; // ignore if in the middle of dealing w last

    _lock.synchronized(() async {
      _safeRemoveOverlay();
      if (mySc < data.sc || oSc < data.osc) {
        // score changed, host must have detected crashed, play Crash
        audio.play(CRASH_FILE);
        if (data.osc == MAX_SCORE) {
          audio.play(WAHWAH_FILE);
        } else if (data.sc == MAX_SCORE) {
          audio.play(TADA_FILE);
        }
      } else if (ball.vy != data.bvy) {
        // ball Y direction changed, host must have detected hit, play Pop
        audio.play(POP_FILE);
      }

      oppoPad.x = data.px;
      // always take ball state and score from host
      mySc = data.sc;
      oSc = data.osc;
      ball.x = data.bx;
      ball.y = data.by;
      ball.vx = data.bvx;
      ball.vy = data.bvy;

      if (mySc == MAX_SCORE || oSc == MAX_SCORE) _leaveNetGame();
    });
  }
}
