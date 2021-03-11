import 'dart:math';
import 'dart:ui';

// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/components.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flame_audio/flame_audio.dart';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'game.dart';

class Ball extends PositionComponent with HasGameRef<MoPongGame> {
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
    if (gameRef.isOver || gameRef.isWaiting) return;

    // let opponent update states in network game if ball going away from me
    if (vy < 0 && !gameRef.isSingle) return;

    gameRef.lock.synchronized(() {
      if (pause > 0) {
        // if we are in a paused state, reduce the count down by elapsed time
        pause -= dt;
        if (pause <= 0) {
          if (y <= gameRef.margin + 2 * gameRef.oppoPad.height) {
            y = gameRef.margin + 2 * gameRef.oppoPad.height + 3 * rad;
          }
          if (y >= gameRef.height - gameRef.margin - 2 * gameRef.myPad.height) {
            y = gameRef.height -
                gameRef.margin -
                2 * gameRef.myPad.height -
                3 * rad;
          }
        }
      } else {
        x = (x + dt * vx).clamp(0.0, gameRef.width);
        y = (y + dt * vy)
            .clamp(gameRef.margin, gameRef.height - gameRef.margin);
        final rect = Rect.fromCircle(center: Offset(x, y), radius: rad);
        if (x <= 0) {
          // bounced left wall
          x = 0;
          vx = -vx;
        } else if (x >= gameRef.width) {
          // bounced right wall
          x = gameRef.width;
          vx = -vx;
        } else if (gameRef.isSingle && gameRef.oppoPad.touch(rect) && vy < 0) {
          FlameAudio.play(POP_FILE);
          y = gameRef.oppoPad.y + 2 * gameRef.oppoPad.height + 3 * rad;
          vy = -vy;
          vx += (gameRef.oppoPad.direction + .3 * (random.nextDouble() - .5)) *
              spin;
        } else if (gameRef.myPad.touch(rect) && vy > 0) {
          FlameAudio.play(POP_FILE);
          y = gameRef.myPad.y - 2 * gameRef.myPad.height - 3 * rad;
          vy = -vy;
          vx += (gameRef.myPad.direction + .3 * (random.nextDouble() - .5)) *
              spin;
        } else if (gameRef.isSingle && y <= gameRef.margin && vy < 0) {
          // bounced top
          gameRef.addMyScore();
          vx = 0;
          pause = PAUSE_INTERVAL;
          vy = -vy;
        } else if (y >= gameRef.height - gameRef.margin && vy > 0) {
          // bounced bottom
          gameRef.addOpponentScore();
          vx = 0;
          pause = PAUSE_INTERVAL;
          vy = -vy;
        }
      }
    });
    if (gameRef.isHost || gameRef.isGuest) gameRef.sendStateUpdate();
  }

  @override
  void render(Canvas canvas) {
    if (gameRef.isOver || gameRef.isWaiting) return;
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), rad, ballPaint);
    super.render(canvas);
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    speed = BALL_SPEED_RATIO * gameSize.y;
    spin = SPIN_RATIO * gameSize.x;
    vy = vy.sign * speed;
    rad = BALL_RAD_RATIO * gameSize.y;
    width = 2 * rad;
    height = 2 * rad;
  }
}
