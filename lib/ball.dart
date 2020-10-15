import 'dart:math';
import 'dart:ui';

import 'package:flame/anchor.dart';
import 'package:flame/components/component.dart';
import 'package:flame/components/mixins/has_game_ref.dart';
import 'package:flame/components/mixins/resizable.dart';
import 'package:flutter/material.dart';

import 'main.dart';

const BALL_RAD = 4.0;
const SIDE_SPIN = 150.0; // side spin when pad is moving while ball strike
const PAUSE_INTERVAL = 2.0; // pause in secs when a point is scored

class Ball extends PositionComponent with Resizable, HasGameRef<MoPong> {
  final random = Random();
  var vx = 0.0; // px/sec
  var vy = 400.0; // px/sec
  var pauseCountDown = 0.0;

  Ball(double x, double y) : super() {
    anchor = Anchor.center;
    super.x = x;
    super.y = y;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null || gameRef.isOver) return;

    // in net guest mode, let host set ball x, y and score
    if (gameRef.mode == GameMode.single || gameRef.mode == GameMode.hosting) {
      if (pauseCountDown > 0) {
        pauseCountDown -= dt;
        if (pauseCountDown <= 0) {
          if (y < MARGIN) {
            y = MARGIN + PAD_HEIGHT + 2 * BALL_RAD;
          } else if (y > size.height - MARGIN) {
            y = size.height - MARGIN - PAD_HEIGHT - 2 * BALL_RAD;
          }
        }
      } else {
        final ballRect =
            Rect.fromCircle(center: Offset(x, y), radius: BALL_RAD);
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
          pauseCountDown = PAUSE_INTERVAL;
        } else if (y > size.height - MARGIN) {
          // bounced bottom
          gameRef.addOpponentScore();
          vy = -vy;
          vx = 0;
          pauseCountDown = PAUSE_INTERVAL;
        } else if (gameRef.oppoPad.touch(ballRect)) {
          gameRef.audio.play(POP_FILE);
          y = gameRef.oppoPad.y + gameRef.oppoPad.height / 2 + 1;
          vy = -vy;
          vx += (gameRef.oppoPad.direction + .5 * (random.nextDouble() - .5)) *
              SIDE_SPIN;
        } else if (gameRef.myPad.touch(ballRect)) {
          gameRef.audio.play(POP_FILE);
          y = gameRef.myPad.y - gameRef.myPad.height / 2 - 1;
          vy = -vy;
          vx += (gameRef.myPad.direction + .5 * (random.nextDouble() - .5)) *
              SIDE_SPIN;
        }

        if (pauseCountDown <= 0) {
          final dx = dt * vx;
          final dy = dt * vy;
          x = x + dx;
          y = y + dy;
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (gameRef.isOver) return;
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), BALL_RAD, ballPaint);
  }
}
