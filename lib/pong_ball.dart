import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'pixel_mapper.dart';
import 'pong_game.dart';
import 'pong_constants.dart';

class Ball extends PositionComponent with HasGameRef<PongGame> {
  static final log = Logger("Ball");

  static const NORM_RAD = 0.01;
  static const NORM_SPEED = 0.3;
  static const NORM_SPIN = 0.3;

  final _rand = Random();

  late PixelMapper _pxMap;

  double _vx = 0.0;
  double _vy = 0.0;
  double _pause = 0.0;

  Ball({double gameWidth: 0, double gameHeight: 0}) : super() {
    _pxMap = PixelMapper(gameWidth: gameWidth, gameHeight: gameHeight);
    reset();
  }

  void reset({double normVY: NORM_SPEED, double normX: .5, double normY: .5}) {
    scale = Vector2(1, 1);
    anchor = Anchor.center;
    _pause = 0.0;
    _vx = 0.0;
    _vy = _pxMap.toDevHgt(normVY);
    width = _pxMap.toDevHgt(2 * NORM_RAD);
    height = _pxMap.toDevHgt(2 * NORM_RAD);
    position = _pxMap.toDevPos(normX, normY);
  }

  double get vx => _vx;
  double get vy => _vy;
  double get pause => _pause;
  double get radius => height / 2;
  double randSpin(double padVX) =>
      (padVX.sign + (_rand.nextDouble() - .5)) * NORM_SPIN * _pxMap.safeWidth;

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isOver || gameRef.isWaiting) return;

    // let opponent update states in network game if ball going away from me
    if (_vy < 0 && !gameRef.isSingle) return;

    if (_pause > 0) {
      // if we are in a paused state, reduce the count down by elapsed time
      _pause -= dt;
      // at the end of pause, make sure ball is not beyond bounds
      if (_pause <= 0) {
        y = y.clamp(
          gameRef.topMargin + gameRef.oppoPad.height + height,
          gameRef.bottomMargin - gameRef.myPad.height - height,
        );
        x = x.clamp(
          gameRef.leftMargin + width,
          gameRef.rightMargin - width,
        );
      }
    } else {
      x = (x + dt * vx).clamp(gameRef.leftMargin, gameRef.rightMargin);
      y = (y + dt * vy).clamp(gameRef.topMargin, gameRef.bottomMargin);
      final ballRect = toAbsoluteRect();
      if (x <= gameRef.leftMargin + radius) {
        // bounced left wall
        x = gameRef.leftMargin + radius;
        _vx = -vx;
      } else if (x >= gameRef.rightMargin - radius) {
        // bounced right wall
        x = gameRef.rightMargin - radius;
        _vx = -vx;
      }

      if (gameRef.myPad.touch(ballRect)) {
        FlameAudio.play(POP_FILE);
        y = gameRef.myPad.y - gameRef.myPad.height - 2 * radius;
        _vy = -vy;
        _vx += randSpin(gameRef.myPad.vx.sign);
      } else if (y >= gameRef.bottomMargin - radius) {
        // bounced bottom
        gameRef.addOpponentScore();
        _pause = PAUSE_INTERVAL;
        _vx = 0;
        _vy = -vy;
      }

      if (gameRef.isSingle) {
        if (gameRef.oppoPad.touch(ballRect)) {
          FlameAudio.play(POP_FILE);
          y = gameRef.oppoPad.y + gameRef.oppoPad.height + 2 * radius;
          _vy = -vy;
          _vx += randSpin(gameRef.myPad.vx.sign);
        } else if (y <= gameRef.topMargin + radius) {
          // bounced top
          gameRef.addMyScore();
          _pause = PAUSE_INTERVAL;
          _vx = 0;
          _vy = -vy;
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(radius, radius), radius, ballPaint);
    super.render(canvas);
  }

  @override
  void onGameResize(Vector2 gameSize) {
    final normX = _pxMap.toNormX(x);
    final normY = _pxMap.toNormY(y);

    super.onGameResize(gameSize);

    _pxMap = PixelMapper(gameWidth: gameSize.x, gameHeight: gameSize.y);
    x = _pxMap.toDevX(normX);
    y = _pxMap.toDevY(normY);
    _vx = 0;
    _vy = _pxMap.toDevHgt(NORM_SPEED);
    width = _pxMap.toDevWth(2 * NORM_RAD);
    height = _pxMap.toDevHgt(2 * NORM_RAD);
  }

  void updateOnReceive(
    double normX,
    double normY,
    double normVX,
    double normVY,
    double pauseCountDown,
  ) {
    _vx = -_pxMap.toDevWth(normVX);
    _vy = -_pxMap.toDevHgt(normVY);
    _pause = pauseCountDown;
    position = _pxMap.toDevPos(1.0 - normX, 1.0 - normY);
  }
}
