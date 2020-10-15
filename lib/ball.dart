import 'dart:math';
import 'dart:ui';

import 'package:flame/anchor.dart';
import 'package:flame/components/component.dart';
import 'package:flame/components/mixins/has_game_ref.dart';
import 'package:flame/components/mixins/resizable.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'game.dart';

class Ball extends PositionComponent with Resizable, HasGameRef<MoPong> {
  final random = Random();
  var vx = 0.0; // px/sec
  var vy = 400.0; // px/sec
  var pauseRundown = 0.0;
  get mode => gameRef?.mode;
  get isOver => gameRef?.isOver;
  get isGuest => mode == GameMode.guest;
  get isWaiting => mode == GameMode.wait;

  Ball([double x = 10, double y = 100]) : super() {
    anchor = Anchor.center;
    super.x = x;
    super.y = y;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null || isOver || isGuest || isWaiting) return;

    if (pauseRundown > 0) {
      pauseRundown -= dt;
      if (pauseRundown <= 0) {
        if (y < MARGIN) {
          y = MARGIN + PAD_HEIGHT + 2 * BALL_RAD;
        } else if (y > size.height - MARGIN) {
          y = size.height - MARGIN - PAD_HEIGHT - 2 * BALL_RAD;
        }
      }
    } else {
      final rect = Rect.fromCircle(center: Offset(x, y), radius: BALL_RAD);
      if (x < 0) {
        // bounced left wall
        x = 0;
        vx = -vx;
      } else if (x > size.width) {
        // bounced right wall
        x = size.width;
        vx = -vx;
      } else if (y < MARGIN) {
        // bounced top
        gameRef.addMyScore();
        vy = -vy;
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
      } else if (y > size.height - MARGIN) {
        // bounced bottom
        gameRef.addOpponentScore();
        vy = -vy;
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
      } else if (gameRef.oppoPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.oppoPad.y + gameRef.oppoPad.height / 2 + 1;
        vy = -vy;
        vx += (gameRef.oppoPad.direction + (random.nextDouble() - .5)) * SPIN;
      } else if (gameRef.myPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.myPad.y - gameRef.myPad.height / 2 - 1;
        vy = -vy;
        vx += (gameRef.myPad.direction + (random.nextDouble() - .5)) * SPIN;
      }

      x += dt * vx;
      y += dt * vy;
    }
  }

  @override
  void render(Canvas canvas) {
    if (isOver || isWaiting) return;
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), BALL_RAD, ballPaint);
  }
}
