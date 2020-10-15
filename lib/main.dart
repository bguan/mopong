import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bonsoir/bonsoir.dart';
import 'package:flame/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flame/gestures.dart';
import 'package:flame/position.dart';
import 'package:flame/text_config.dart';
import 'package:flame/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'name-generator.dart';
import 'pad.dart';
import 'ball.dart';

const BUTTON_SIZE_RATIO = .7;
const PONG_GAME_SVC_TYPE = '_pong._udp';
const PONG_GAME_SVC_PORT = 13579;
const POP_FILE = 'pop.wav';
const CRASH_FILE = 'crash.wav';
const TADA_FILE = 'tada.wav';
const WAHWAH_FILE = 'wahwah.wav';
const OVERLAY_ID = 'Overlay';

enum GameMode {
  over, // game is over, showing game over menu
  single, // playing as single player against computer
  waiting, // waiting as host for any guest to connect, show waiting menu
  hosting, // playing as host over network
  guest, // playing as guest over network
}

const MAX_SCORE = 5;
const MARGIN = 80.0;
const PAD_HEIGHT = 10.0;
const PAD_WIDTH = 100.0;

class MoPong extends BaseGame with HasWidgetsOverlay, HorizontalDragDetector {
  final audio = FlameAudio();
  final txtCfg = TextConfig(fontSize: 20.0, color: Colors.white);
  final String playerName;

  Widget overlay = null;
  var mode = GameMode.over;
  bool get isOver => mode == GameMode.over;
  bool get isWaitingAsHost => mode == GameMode.waiting;

  Pad myPad;
  Pad oppoPad;
  Ball ball;
  int myScore = 0;
  int oppoScore = 0;
  double lastFingerX = 0.0;
  BonsoirService myService = null; // network game I am hosting
  BonsoirBroadcast myBroadcast = null;
  Map<String, BonsoirService> host2svc = {};
  InternetAddress hostAddress = null; // from perspective of guest
  int hostPort = null; // from perspective of guest
  InternetAddress guestAddress = null; // from perspective of host
  int guestPort = null; // from perspective of host
  RawDatagramSocket socket = null;

  MoPong()
      : myPad = Pad(),
        oppoPad = Pad(false),
        ball = Ball(10, MARGIN + PAD_HEIGHT + BALL_RAD),
        playerName = genName() {
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

    discovery.eventStream.listen((event) {
      bool changed = false;
      if (event.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_RESOLVED) {
        if (myService?.name != event.service.name) {
          host2svc[event.service.name] = event.service;
          changed = true;
        }
      }
      if (event.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_LOST) {
        host2svc.remove(event.service.name);
        changed = true;
      }

      if (changed && isOver) gameOverMenu(); // redraw to reflect new discovery
    });
  }

  void onePlayerAction() {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }
    mode = GameMode.single;
    myScore = 0;
    oppoScore = 0;
    audio.play(POP_FILE);
  }

  void hostNetGameAction() async {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }

    myScore = 0;
    oppoScore = 0;
    myPad.x = 0;

    mode = GameMode.waiting;
    myService = BonsoirService(
      name: 'Pong with ${playerName}',
      type: PONG_GAME_SVC_TYPE,
      port: PONG_GAME_SVC_PORT,
    );

    myBroadcast = BonsoirBroadcast(service: myService);
    await myBroadcast.ready;
    await myBroadcast.start();

    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text('Hosting Game as ${playerName}...'),
          ),
          RaisedButton(
            child: Text('Cancel'),
            onPressed: () async {
              await myBroadcast.stop();
              myBroadcast = null;
              if (socket != null) {
                await socket.close();
                socket = null;
              }
              mode = GameMode.over;
              gameOverMenu();
            },
          ),
        ],
      ),
    );

    addWidgetOverlay(OVERLAY_ID, overlay);
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      PONG_GAME_SVC_PORT,
    );
    socket.listen(
      onMsgFromGuest,
      onError: errorHandler,
      onDone: finishedHandler,
      cancelOnError: true,
    );
  }

  void onMsgFromGuest(RawSocketEvent event) async {
    Datagram packet = socket.receive();
    if (packet == null) return;

    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }

    if (myBroadcast != null) {
      await myBroadcast.stop();
      myBroadcast = null;
    }

    if (mode == GameMode.waiting) {
      mode = GameMode.hosting;
      guestAddress = packet.address;
      guestPort = packet.port;
    }

    if (mode == GameMode.hosting) {
      Uint8List data = packet.data;
      if (data == null || data.length < 1) return; // bad data packet?
      final oppoX = size.width * data[0] / 256;
      oppoPad.x = oppoX;
    }
  }

  void joinNetGameAction(ResolvedBonsoirService hostSvc) async {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }

    myScore = 0;
    oppoScore = 0;
    myPad.x = 0;
    hostAddress = InternetAddress(hostSvc.ip);
    hostPort = hostSvc.port;
    mode = GameMode.guest;
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      hostPort,
    );
    socket.listen(
      onMsgFromHost,
      onError: errorHandler,
      onDone: finishedHandler,
      cancelOnError: true,
    );
  }

  void onMsgFromHost(RawSocketEvent event) {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }
    Datagram packet = socket.receive();
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
      socket.close();
      socket = null;
      mode = GameMode.over;
      gameOverMenu();
    }
  }

  void errorHandler(error) async {
    mode = GameMode.over;
    if (socket != null) {
      socket.close();
      socket = null;
    }

    if (myBroadcast != null) {
      await myBroadcast.stop();
      myBroadcast = null;
    }
    gameOverMenu();
  }

  void finishedHandler() async {
    mode = GameMode.over;
    if (socket != null) {
      socket.close();
      socket = null;
    }

    if (myBroadcast != null) {
      await myBroadcast.stop();
      myBroadcast = null;
    }
    gameOverMenu();
  }

  void gameOverMenu() {
    if (overlay != null) {
      removeWidgetOverlay(OVERLAY_ID);
      overlay = null;
    }
    overlay = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: BUTTON_SIZE_RATIO * size.width,
            child: RaisedButton(
              child: Text('Single Player'),
              onPressed: onePlayerAction,
            ),
          ),
          SizedBox(
            width: BUTTON_SIZE_RATIO * size.width,
            child: RaisedButton(
              child: Text('Host Network Game'),
              onPressed: hostNetGameAction,
            ),
          ),
          for (var hostSvc in host2svc.entries)
            SizedBox(
              width: BUTTON_SIZE_RATIO * size.width,
              child: RaisedButton(
                child: Text('Play ${hostSvc.key}'),
                onPressed: () => joinNetGameAction(hostSvc.value),
              ),
            ),
        ],
      ),
    );
    addWidgetOverlay(OVERLAY_ID, overlay);
  }

  void addMyScore() {
    if (mode == GameMode.single || mode == GameMode.hosting) {
      audio.play(CRASH_FILE);
      myScore += 1;
      if (myScore >= MAX_SCORE) {
        audio.play(TADA_FILE);
      }
    }
  }

  void addOpponentScore() {
    if (mode == GameMode.single || mode == GameMode.hosting) {
      audio.play(CRASH_FILE);
      oppoScore += 1;
      if (oppoScore >= MAX_SCORE) {
        audio.play(WAHWAH_FILE);
      }
    }
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
    } else if (mode == GameMode.hosting) {
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
      mode = GameMode.over;
      if (socket != null) {
        socket.close();
        socket = null;
      }
      gameOverMenu();
    }
  }

  void onHorizontalDragUpdate(DragUpdateDetails details) {
    lastFingerX = details.globalPosition.dx;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flameUtil = Util();
  flameUtil.fullScreen();
  flameUtil.setOrientation(DeviceOrientation.portraitUp);

  final game = MoPong();
  runApp(game.widget);
}
