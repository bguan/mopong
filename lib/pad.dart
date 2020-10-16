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
  double speed = 100; // px/sec, until resize

  Pad([this.isPlayer = true]) : super() {
    anchor = Anchor.center;
    x = 0;
    width = 100; // until resize
    height = 10; // until resize
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null) return;

    // regardless of mode, player always control self pad
    if (isPlayer) {
      y = size.height - height - gameRef.margin;
      if (gameRef.lastFingerX > (x + .3 * width)) {
        direction = 1;
      } else if (gameRef.lastFingerX < (x - .3 * width)) {
        direction = -1;
      } else {
        direction = 0;
      }
      x = (x + direction * dt * speed).clamp(0.0, size.width);
      if (direction != 0 && (gameRef.isHost || gameRef.isGuest))
        gameRef.sendStateUpdate();
    } else {
      y = gameRef.margin + height;
      if (gameRef.isSingle) {
        // computer controls opponent, go to direction of ball
        if (gameRef.ball.x > (x + .3 * width)) {
          direction = 1;
        } else if (gameRef.ball.x < (x - .3 * width)) {
          direction = -1;
        } else {
          direction = 0;
        }
        x = (x + direction * dt * speed).clamp(0.0, size.width);
      } // let remote host set opponet pad X in MoPong Game event handler
    }
  }

  @override
  void render(Canvas canvas) {
    final padRect = Rect.fromLTWH(
      x - width / 2, y - height / 2, width, height);
    final padPaint = Paint();
    padPaint.color = isPlayer ? Colors.blue : Colors.red;
    canvas.drawRect(padRect, padPaint);
  }

  bool touch(Rect objRect) {
    final padRect = Rect.fromLTWH(
      x - width / 2, y - height / 2, width, height);
    return padRect.overlaps(objRect);
  }

  @override
  void resize(Size size) {
    super.resize(size);
    speed = PAD_SPEED_RATIO * size.width;
    height = PAD_HEIGHT_RATIO * size.height;
    width = PAD_WIDTH_RATIO * size.width;
  }
}
