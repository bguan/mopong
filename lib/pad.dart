import 'dart:math';
import 'dart:ui';

import 'package:flame/anchor.dart';
import 'package:flame/components/component.dart';
import 'package:flame/components/mixins/has_game_ref.dart';
import 'package:flame/components/mixins/resizable.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'game.dart';

class Pad extends PositionComponent with Resizable, HasGameRef<MoPong> {
  final bool isPlayer;
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

    // regardless of mode, player always control self pad
    if (isPlayer) {
      if (gameRef.lastFingerX > (x + .3 * width)) {
        direction = 1;
      } else if (gameRef.lastFingerX < (x - .3 * width)) {
        direction = -1;
      } else {
        direction = 0;
      }
      x = max(0, min(size.width, x + direction * dt * PAD_SPEED));
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
        x = x + direction * dt * PAD_SPEED;
      } // let remote host set opponet pad X in MoPong Game event handler
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