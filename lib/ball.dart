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
        if (y <= gameRef.margin + 2*gameRef.myPad.height) {
          y = gameRef.margin + 2*gameRef.myPad.height + 3*rad;
        } 
        if (y >= size.height - gameRef.margin - 2*gameRef.myPad.height) {
          y = size.height - gameRef.margin - 2*gameRef.myPad.height - 3*rad;
        }
      }
    } else {
      final rect = Rect.fromCircle(center: Offset(x, y), radius: 2*rad);
      if (x <= 0) {
        // bounced left wall
        x = 0;
        vx = -vx;
      } else if (x >= size.width) {
        // bounced right wall
        x = size.width;
        vx = -vx;
      } else if (gameRef.oppoPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.oppoPad.y + gameRef.oppoPad.height;
        vy = -vy;
        vx += (gameRef.oppoPad.direction + (random.nextDouble() - .5)) * spin;
      } else if (gameRef.myPad.touch(rect)) {
        gameRef.audio.play(POP_FILE);
        y = gameRef.myPad.y - gameRef.myPad.height;
        vy = -vy;
        vx += (gameRef.myPad.direction + (random.nextDouble() - .5)) * spin;
      } else if (y <= gameRef.margin) {
        // bounced top
        gameRef.addMyScore();
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
        vy = -vy;
      } else if (y >= size.height - gameRef.margin) {
        // bounced bottom
        gameRef.addOpponentScore();
        vx = 0;
        pauseRundown = PAUSE_INTERVAL;
        vy = -vy;
      }

      x = max(0, min(size.width, x + dt * vx));
      y = max(gameRef.margin, min(size.height - gameRef.margin, y + dt * vy));
    }
  }

  @override
  void render(Canvas canvas) {
    if (isOver || isWaiting) return;
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
