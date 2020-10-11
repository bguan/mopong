import 'dart:math';
import 'dart:ui';

import 'package:flame/anchor.dart';
import 'package:flame/components/component.dart';
import 'package:flame/components/mixins/has_game_ref.dart';
import 'package:flame/components/mixins/resizable.dart';
import 'package:flame/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flame/position.dart';
import 'package:flame/text_config.dart';
import 'package:flutter/material.dart';
import 'package:sensors/sensors.dart';

class Pad extends PositionComponent with Resizable, HasGameRef<MoPongGame> {
  final bool isPlayer;
  bool firstDrawn = true;
  double speed = 300.0; // px/sec
  bool goRight = true; // tristate logic null for neutral

  Pad([this.isPlayer = true]) : super() {
    anchor = Anchor.center;
    width = 100;
    height = 10;

    if (isPlayer) {
      gyroscopeEvents.listen((GyroscopeEvent event) {
        if (event.y > .6) {
          goRight = true;
        } else if (event.y < -.6) {
          goRight = false;
        }
      });
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null ) return;
    if (firstDrawn || gameRef.isOver) {
      firstDrawn = false;
      x = size.width / 2;
      y = isPlayer ? size.height - height / 2 : gameRef.topMargin + height / 2;
    } else if (isPlayer) {
      x = x + (goRight ? 1 : -1) * dt * speed;
      x = min(size.width, x);
      x = max(0, x);
    } else {
      // computer controls opponent, go to direction of ball
      goRight = (gameRef.ball.x > x);
      x = x + (goRight ? 1 : -1) * dt * speed;
    }
  }

  @override
  void render(Canvas canvas) {
    final padRect = Rect.fromLTWH(x - width / 2, y - height / 2, width, height);
    final padPaint = Paint();
    padPaint.color = this.isPlayer ? Colors.blue : Colors.red;
    canvas.drawRect(padRect, padPaint);
  }

  bool touch(Rect objRect) {
    final padRect = Rect.fromLTWH(x - width / 2, y - height / 2, width, height);
    return padRect.overlaps(objRect);
  }
}

class Ball extends PositionComponent with Resizable, HasGameRef<MoPongGame> {
  final radius = 4.0;
  final sideSpin = 50.0;
  final pause = 2.0;
  var isFirstDrawn = true;
  var vx = 0.0; // px/sec
  var vy = 400.0; // px/sec
  var pauseCountDown = 0.0;

  Ball() : super() {
    anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size == null || gameRef.isOver) return;
    if (isFirstDrawn) {
      x = size.width / 2;
      y = size.height / 2;
      isFirstDrawn = false;
    } else if (pauseCountDown > 0) {
      pauseCountDown -= dt;
    } else {
      final ballRect = Rect.fromCircle(center: Offset(x, y), radius: radius);
      if (x < 0) {
        // bounced left wall
        x = 0;
        vx = -vx;
      } else if (x > size.width) {
        // bounced right wall
        x = size.width;
        vx = -vx;
      } else if (y < gameRef.topMargin) {
        // bounced top
        gameRef.audio.play('crash.wav');
        gameRef.addMyScore();
        y = gameRef.topMargin;
        vy = -vy;
        vx = 0;
        pauseCountDown = pause;
      } else if (y > size.height) {
        // bounced bottom
        gameRef.audio.play('crash.wav');
        gameRef.addOpponentScore();
        y = size.height;
        vy = -vy;
        vx = 0;
        pauseCountDown = pause;
      } else if (gameRef.opponentPad.touch(ballRect)) {
        gameRef.audio.play('pop.wav');
        y = gameRef.opponentPad.y + gameRef.opponentPad.height / 2 + 1;
        vy = -vy;
        vx += (gameRef.opponentPad.goRight ? 1 : -1) * sideSpin;
      } else if (gameRef.myPad.touch(ballRect)) {
        gameRef.audio.play('pop.wav');
        y = gameRef.myPad.y - gameRef.myPad.height / 2 - 1;
        vy = -vy;
        vx += (gameRef.myPad.goRight ? 1 : -1) * sideSpin;
      }

      if (pauseCountDown <= 0) {
        final dx = dt * vx;
        final dy = dt * vy;
        x = x + dx;
        y = y + dy;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (gameRef.isOver) return;
    final ballPaint = Paint();
    ballPaint.color = Colors.white;
    canvas.drawCircle(Offset(x, y), radius, ballPaint);
  }
}

class MoPongGame extends BaseGame with HasWidgetsOverlay {
  final audio = FlameAudio();
  final maxScore = 5;
  bool isOver = true;
  Pad myPad;
  Pad opponentPad;
  Ball ball;
  int myScore = 0;
  int opponentScore = 0;
  Widget overlay = null;
  final topMargin = 40.0;
  final txtCfg = TextConfig(fontSize: 20.0, color: Colors.white);

  MoPongGame()
      : myPad = Pad(),
        opponentPad = Pad(false),
        ball = Ball() {
    add(myPad);
    add(opponentPad);
    add(ball);
  }

  void addMyScore() {
    myScore += 1;
    if (myScore >= maxScore) {
      isOver = true;
      audio.play('tada.wav');
    }
  }

  void addOpponentScore() {
    opponentScore += 1;
    if (opponentScore >= maxScore) {
      isOver = true;
      audio.play('tada.wav');
    }
  }

  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);

    if (isOver && overlay == null) {
      final overMenu = Center(
        child: RaisedButton(
          child: Text('Click to Start'),
          onPressed: () {
            removeWidgetOverlay('OverMenu');
            isOver = false;
            overlay = null;
            myScore = 0;
            opponentScore = 0;
          },
        ),
      );
      addWidgetOverlay('OverMenu', overMenu);
      overlay = overMenu;
    }
    txtCfg.render(canvas, "score ${myScore}:${opponentScore}", Position(15, 5));
    super.render(canvas);
  }
}
