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
  var vy = BALL_SPEED; // px/sec
  var pauseRundown = 0.0;
  get mode => gameRef?.mode;
  get isOver => gameRef?.isOver;
  get isHost => mode == GameMode.host;
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
    if (size == null || isOver || isWaiting) return;

    // always let host calculate ball state
    if (isGuest) return;

    if (pauseRundown > 0) {
      pauseRundown -= dt;
      if (pauseRundown <= 0) {
        if (y < MARGIN + 2*PAD_HEIGHT) {
          y = MARGIN + 2*PAD_HEIGHT;
        } else if (y > size.height - MARGIN - 2*PAD_HEIGHT) {
          y = size.height - MARGIN - 2*PAD_HEIGHT;
        }
      }
    } else {
      final rect = Rect.fromCircle(center: Offset(x, y), radius: BALL_RAD);
      if (x <= 0) {
        // bounced left wall
        x = 0;
        vx = -vx;
      } else if (x >= size.width) {
        // bounced right wall
        x = size.width;
        vx = -vx;
      } else if (y <= MARGIN) {
        // bounced top
        gameRef.addMyScore();
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
        vy = -vy; 
      } else if (y >= size.height - MARGIN) {
        // bounced bottom
        gameRef.addOpponentScore();
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
        vy = -vy; 
      } else if (gameRef.oppoPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.oppoPad.y + gameRef.oppoPad.height;
        vy = -vy; 
        vx += (gameRef.oppoPad.direction + (random.nextDouble() - .5)) * SPIN;
      } else if (gameRef.myPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.myPad.y - gameRef.myPad.height;
        vy = -vy; 
        vx += (gameRef.myPad.direction + (random.nextDouble() - .5)) * SPIN;
      }

      x = max(0, min(size.width, x + dt * vx));
      y = max(MARGIN, min(size.height - MARGIN, y + dt * vy));
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
