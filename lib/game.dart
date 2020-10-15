import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bonsoir/bonsoir.dart';
import 'package:flame/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flame/gestures.dart';
import 'package:flame/position.dart';
import 'package:flame/text_config.dart';
import 'package:flutter/material.dart';

import 'ball.dart';
import 'constants.dart';
import 'namer.dart';
import 'pad.dart';

class MoPong extends BaseGame with HasWidgetsOverlay, HorizontalDragDetector {
  final audio = FlameAudio();
  final txtCfg = TextConfig(fontSize: 20.0, color: Colors.white);
  final String myName = genName();

  Widget overlay = null;
  var _mode = GameMode.over;
  GameMode get mode => _mode;
  set mode(GameMode nextMode) {
    _mode = nextMode;
    if (nextMode != GameMode.over) {
      myScore = 0;
      oppoScore = 0;
    }
  }

  bool get isOver => mode == GameMode.over;

  Pad myPad = Pad();
  Pad oppoPad = Pad(false);
  Ball ball = Ball();
  int myScore = 0;
  int oppoScore = 0;
  double lastFingerX = 0.0;
  BonsoirService mySvc = null; // network game I am hosting
  BonsoirBroadcast myBroadcast = null;
  Map<String, BonsoirService> host2svc = {};
  InternetAddress hostAddress = null; // from perspective of guest
  int hostPort = null; // from perspective of guest
  InternetAddress guestAddress = null; // from perspective of host
  int guestPort = null; // from perspective of host
  RawDatagramSocket socket = null;

  MoPong() : super() {
    add(myPad);
    add(oppoPad);
    add(ball);
    audio.loadAll([CRASH_FILE, CRASH_FILE, TADA_FILE, WAHWAH_FILE]);
    scanHosts();
  }

  void scanHosts() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: PONG_GAME_SVC_TYPE);
    await discovery.ready;
    await discovery.start();

    discovery.eventStream.listen((e) {
      if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_RESOLVED) {
        if (mySvc?.name != e.service.name) {
          host2svc[e.service.name] = e.service;
          gameOverMenu();
        }
      } else if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_LOST) {
        host2svc.remove(e.service.name);
        gameOverMenu();
      }
    });
  }

  Widget gameButton(String txt, Function handler) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0),
      child: SizedBox(
        width: BUTTON_SIZE_RATIO * size.width,
        child: RaisedButton(child: Text(txt), onPressed: handler),
      ),
    );
  }

  void onePlayerAction() {
    safeRemoveOverlay();
    mode = GameMode.single;
    audio.play(POP_FILE);
  }

  void hostNetGameAction() async {
    safeRemoveOverlay();
    mode = GameMode.wait;
    mySvc = BonsoirService(
      name: 'Pong with ${myName}',
      type: PONG_GAME_SVC_TYPE,
      port: PONG_GAME_SVC_PORT,
    );

    myBroadcast = BonsoirBroadcast(service: mySvc);
    await myBroadcast.ready;
    await myBroadcast.start();

    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text('Hosting Game as ${myName}...'),
          ),
          gameButton(
            'Cancel',
            () async {
              safeStopBroadcast();
              safeCloseSocket();
              gameOverMenu();
            },
          ),
        ],
      ),
    );

    addWidgetOverlay(OVERLAY_ID, overlay);
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, mySvc.port);
    socket.listen(
      onMsgFromGuest,
      onError: finishedHandler,
      onDone: finishedHandler,
      cancelOnError: true,
    );
  }

  void onMsgFromGuest(RawSocketEvent event) async {
    Datagram packet = socket?.receive();
    if (packet == null) return;
    safeRemoveOverlay();
    safeStopBroadcast();
    if (mode == GameMode.wait) {
      mode = GameMode.host;
      guestAddress = packet.address;
      guestPort = packet.port;
    }

    if (mode == GameMode.host) {
      Uint8List data = packet.data;
      if (data == null || data.length < 1) return; // bad data packet?
      final oppoX = size.width * data[0] / 256;
      oppoPad.x = oppoX;
    }
  }

  void joinNetGameAction(ResolvedBonsoirService hostSvc) async {
    safeRemoveOverlay();
    hostAddress = InternetAddress(hostSvc.ip);
    hostPort = hostSvc.port;
    mode = GameMode.guest;
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, hostPort);
    socket.listen(
      onMsgFromHost,
      onError: finishedHandler,
      onDone: finishedHandler,
      cancelOnError: true,
    );
  }

  void onMsgFromHost(RawSocketEvent event) {
    safeRemoveOverlay();
    Datagram packet = socket?.receive();
    if (packet == null) return;
    Uint8List data = packet.data;
    if (data == null || data.length < 7) return; // bad data packet?
    final oppoX = size.width * data[0] / 256;
    final ballX = size.width * data[1] / 256;
    final ballY = size.height * data[2] / 256;
    final ballVX = size.width * data[3] / 256;
    final ballVY = size.height * data[4] / 256;
    final hostScore = data[5];
    final guestScore = data[6];

    if (myScore < guestScore || oppoScore < hostScore) {
      // score changed, host must have detected crashed, play Crash
      audio.play(CRASH_FILE);
      if (hostScore == MAX_SCORE) {
        audio.play(WAHWAH_FILE);
      } else if (guestScore == MAX_SCORE) {
        audio.play(TADA_FILE);
      }
    } else if (ball.vy != ballVY) {
      // ball Y direction changed, host must have detected hit, play Pop
      audio.play(POP_FILE);
    }

    myScore = guestScore;
    oppoScore = hostScore;
    ball.x = ballX;
    ball.y = ballY;
    ball.vx = ballVX;
    ball.vy = ballVY;
    oppoPad.x = oppoX;

    if (myScore == MAX_SCORE || oppoScore == MAX_SCORE) {
      safeCloseSocket();
      gameOverMenu();
    }
  }

  void finishedHandler() async {
    safeCloseSocket();
    safeStopBroadcast();
    gameOverMenu();
  }

  void gameOverMenu() {
    mode = GameMode.over;
    safeRemoveOverlay();
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          gameButton('Single Player', onePlayerAction),
          gameButton('Host Network Game', hostNetGameAction),
          for (var svc in host2svc.entries)
            gameButton('Play ${svc.key}', () => joinNetGameAction(svc.value))
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void addMyScore() {
    if (mode == GameMode.single || mode == GameMode.host) {
      audio.play(CRASH_FILE);
      myScore += 1;
      if (myScore >= MAX_SCORE) {
        audio.play(TADA_FILE);
      }
    }
  }

  void addOpponentScore() {
    if (mode == GameMode.single || mode == GameMode.host) {
      audio.play(CRASH_FILE);
      oppoScore += 1;
      if (oppoScore >= MAX_SCORE) {
        audio.play(WAHWAH_FILE);
      }
    }
  }

  void safeRemoveOverlay() {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }
  }

  void safeCloseSocket() {
    if (socket != null) {
      socket.close();
      socket = null;
    }
  }

  void safeStopBroadcast() async {
    if (myBroadcast != null) {
      await myBroadcast.stop();
      myBroadcast = null;
    }
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    lastFingerX = details.globalPosition.dx;
  }

  @override
  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);
    if (isOver && overlay == null) {
      gameOverMenu();
    }
    txtCfg.render(canvas, "Score ${myScore}:${oppoScore}", Position(20, 20));

    super.render(canvas);
  }

  @override
  void update(double t) async {
    super.update(t);
    // note that coordinate of host vs guest is upside down so need adjustment
    if (mode == GameMode.guest) {
      int guestX = 256 * myPad.x ~/ size.width;
      Uint8List data = Uint8List.fromList([guestX]);
      socket.send(data, hostAddress, hostPort);
    } else if (mode == GameMode.host) {
      int hostX = 256 * myPad.x ~/ size.width;
      int ballX = 256 * ball.x ~/ size.width;
      int ballY = 256 * (size.height - ball.y) ~/ size.height;
      int ballVX = 256 * ball.vx ~/ size.width;
      int ballVY = 256 * -ball.vy ~/ size.height;
      int hostScore = myScore;
      int guestScore = oppoScore;
      Uint8List data = Uint8List.fromList(
        [hostX, ballX, ballY, ballVX, ballVY, hostScore, guestScore],
      );
      socket.send(data, guestAddress, guestPort);
    }

    if (myScore >= MAX_SCORE || oppoScore >= MAX_SCORE) {
      safeCloseSocket();
      gameOverMenu();
    }
  }
}
