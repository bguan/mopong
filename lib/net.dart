import 'dart:io';
import 'dart:typed_data';

// ignore: import_of_legacy_library_into_null_safe
import 'package:bonsoir/bonsoir.dart';

import 'constants.dart';

/// Pong Data to pack and send, or receive and unpack.
///
/// Need to normalize by assuming screen width and height are 1000 units.
/// SCREEN_NORM_HEIGHT, SCREEN_NORM_WIDTH.
/// Need to flip Y on send as opponent sees it upside down to us.
/// Need to swap myScore and oppoScore on send.
class PongData {
  final int count;
  final int px, bx, by, bvx, bvy; // padX, ballX, ballY, ballVeloX, , ballVeloY
  final int myScore, oppoScore;
  final int pause;

  PongData(
    this.count,
    this.px,
    this.bx,
    this.by,
    this.bvx,
    this.bvy,
    this.pause,
    this.myScore,
    this.oppoScore,
  );

  PongData.fromPayload(Int16List data)
      : count = data[0],
        px = data[1],
        bx = data[2],
        by = data[3],
        bvx = data[4],
        bvy = data[5],
        pause = data[6],
        myScore = data[7],
        oppoScore = data[8];

  Int16List toNetBundle() {
    return Int16List.fromList([
      count,
      px,
      bx,
      -by,
      bvx,
      -bvy,
      pause,
      oppoScore,
      myScore,
    ]);
  }
}

/// Pong Networking Service for Host and Guest, incl discovery & communication.
class PongNetSvc {
  String myName;
  BonsoirService? _mySvc; // network game I am hosting
  BonsoirBroadcast? _myBroadcast;
  Map<String, ResolvedBonsoirService> _host2svc = {}; // other hosts
  Function _onDiscovery;
  InternetAddress? _oppoAddress;
  RawDatagramSocket? _sock;

  PongNetSvc(this.myName, this._onDiscovery) {
    _scan();
  }

  Iterable<String> get serviceNames => _host2svc.keys;

  void _scan() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: PONG_SVC_TYPE);
    await discovery.ready;
    await discovery.start();

    discovery.eventStream.listen((e) {
      if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_RESOLVED) {
        if (_mySvc?.name != e.service.name) {
          _host2svc[e.service.name] = (e.service) as ResolvedBonsoirService;
          this._onDiscovery();
        }
      } else if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_LOST) {
        _host2svc.remove(e.service.name);
        this._onDiscovery();
      }
    });
  }

  void startHosting(Function(PongData p) onMsg, Function() onDone) async {
    _safeCloseSocket();
    await _safeStopBroadcast();

    _mySvc = BonsoirService(
      name: 'Pong with $myName',
      type: PONG_SVC_TYPE,
      port: PONG_PORT,
    );

    _myBroadcast = BonsoirBroadcast(service: _mySvc);
    await _myBroadcast?.ready;
    await _myBroadcast?.start();

    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock?.listen(
      (evt) => _onEvent(onMsg, evt),
      onError: (err) => _finishedHandler(onDone, err),
      onDone: () => _finishedHandler(onDone),
      cancelOnError: true,
    );
  }

  void stopHosting() async {
    await _safeStopBroadcast();
    _safeCloseSocket();
  }

  void joinGame(String name, void Function(PongData) onMsg,
      void Function() onDone) async {
    final hostSvc = _host2svc[name];
    _oppoAddress = InternetAddress(hostSvc!.ip);
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock?.listen(
      (evt) => _onEvent(onMsg, evt),
      onError: (err) => _finishedHandler(onDone, err),
      onDone: () => _finishedHandler(onDone),
      cancelOnError: true,
    );
  }

  void leaveGame() {
    _safeCloseSocket();
  }

  void send(PongData data) {
    _sock?.send(
      data.toNetBundle().buffer.asInt8List(),
      _oppoAddress!,
      PONG_PORT,
    );
  }

  void _onEvent(Function(PongData) onMsg, RawSocketEvent event) {
    final packet = _sock?.receive();
    if (packet == null) return;
    final data = PongData.fromPayload(packet.data.buffer.asInt16List());
    _oppoAddress = packet.address;
    onMsg(data);
  }

  void _finishedHandler(Function() onDone, [Object? e]) {
    if (e != null) print(e);
    onDone();
  }

  void _safeCloseSocket() {
    _sock?.close();
    _sock = null;
  }

  Future<void> _safeStopBroadcast() async {
    await _myBroadcast?.stop();
    _myBroadcast = null;
    _mySvc = null;
  }
}
