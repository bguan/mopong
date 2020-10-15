import 'dart:math';
import 'dart:ui';

import 'package:flame/anchor.dart';
import 'package:flame/components/component.dart';
import 'package:flame/components/mixins/has_game_ref.dart';
import 'package:flame/components/mixins/resizable.dart';
import 'package:flutter/material.dart';

import 'main.dart';

class Pad extends PositionComponent with Resizable, HasGameRef<MoPong> {
  final bool isPlayer;
  final double speed = 300.0; // px/sec
  double direction = 0.0; // from -1 (max speed to L) to 1 (max speed to R)

  Pad([this.isPlayer = true]) : super() {
    anchor = Anchor.center;
    width = PAD_WIDTH;
    height = PAD_HEIGHT;
    x = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null) return;

    // whether game over, single, host or guest mode
    // player always control own pad
    if (isPlayer) {
      if (gameRef.lastFingerX > (x + .3 * width)) {
        direction = 1;
      } else if (gameRef.lastFingerX < (x - .3 * width)) {
        direction = -1;
      } else {
        direction = 0;
      }
      x = max(0, min(size.width, x + direction * dt * speed));
      y = size.height - height / 2 - MARGIN;
    } else {
      y = MARGIN + height / 2;
      if (gameRef.mode == GameMode.single) {
        // computer controls opponent, go to direction of ball
        if (gameRef.ball.x > (x + .3 * width)) {
          direction = 1;
        } else if (gameRef.ball.x < (x - .3 * width)) {
          direction = -1;
        } else {
          direction = 0;
        }
        x = x + direction * dt * speed;
      }
      // else let remote host set X in MopongGame event handler
    }
  }

  @override
  void render(Canvas canvas) {
    final padRect = Rect.fromLTWH(x - width / 2, y - height / 2, width, height);
    final padPaint = Paint();
    padPaint.color = isPlayer ? Colors.blue : Colors.red;
    canvas.drawRect(padRect, padPaint);
  }

  bool touch(Rect objRect) {
    final padRect = Rect.fromLTWH(x - width / 2, y - height / 2, width, height);
    return padRect.overlaps(objRect);
  }
}