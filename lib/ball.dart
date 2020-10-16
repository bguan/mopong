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
  var rad = 5.0; // until resize
  var speed = 300.0; // px/sec until resize
  var spin = 100.0; // px/sec until resize
  var vy = 300.0; // px/sec until resize
  var pause = 0.0;

  Ball([double x = 10, double y = 100]) : super() {
    anchor = Anchor.center;
    super.x = x;
    super.y = y;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null || gameRef.isOver || gameRef.isWaiting) return;

    if (vy < 0 && !gameRef.isSingle)
      return; // let oppo update states in network game if ball leaving me

    if (pause > 0) {
      pause -= dt;
      if (pause <= 0) {
        if (y <= gameRef.margin + 2 * gameRef.oppoPad.height) {
          y = gameRef.margin + 2 * gameRef.oppoPad.height + 3 * rad;
        }
        if (y >= size.height - gameRef.margin - 2 * gameRef.myPad.height) {
          y = size.height - gameRef.margin - 2 * gameRef.myPad.height - 3 * rad;
        }
      }
    } else {
      x = (x + dt * vx).clamp(0.0, size.width);
      y = (y + dt * vy).clamp(gameRef.margin, size.height - gameRef.margin);
      final rect = Rect.fromCircle(center: Offset(x, y), radius: rad);
      if (x <= 0) {
        // bounced left wall
        x = 0;
        vx = -vx;
      } else if (x >= size.width) {
        // bounced right wall
        x = size.width;
        vx = -vx;
      } else if (gameRef.isSingle && gameRef.oppoPad.touch(rect) && vy < 0) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.oppoPad.y + 2 * gameRef.oppoPad.height + 3 * rad;
        vy = -vy;
        vx += (gameRef.oppoPad.direction + (random.nextDouble() - .5)) * spin;
      } else if (gameRef.myPad.touch(rect) && vy > 0) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.myPad.y - 2 * gameRef.myPad.height - 3 * rad;
        vy = -vy;
        vx += (gameRef.myPad.direction + (random.nextDouble() - .5)) * spin;
      } else if (gameRef.isSingle && y <= gameRef.margin && vy < 0) {
        // bounced top
        gameRef.addMyScore();
        vx = 0;
        pause = PAUSE_INTERVAL;
        vy = -vy;
      } else if (y >= size.height - gameRef.margin && vy > 0) {
        // bounced bottom
        gameRef.addOpponentScore();
        vx = 0;
        pause = PAUSE_INTERVAL;
        vy = -vy;
      }
    }

    if (gameRef.isHost || gameRef.isGuest) gameRef.sendStateUpdate();
  }

  @override
  void render(Canvas canvas) {
    if (gameRef.isOver || gameRef.isWaiting) return;
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), rad, ballPaint);
  }

  @override
  void resize(Size size) {
    super.resize(size);
    speed = BALL_SPEED_RATIO * size.height;
    spin = SPIN_RATIO * size.width;
    vy = vy.sign * speed;
    rad = BALL_RAD_RATIO * size.height;
  }
}
