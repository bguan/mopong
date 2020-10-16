import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'constants.dart';

/// Pong Data to pack and send, or receive and unpack.
///
/// Need to normalize to 2^15-1 i.e. 2-byte int size, for screen width & height.
/// Need to flip Y on send as opponent sees it upside down to us.
/// Need to swap myScore and oppoScore on send.
class PongData {
  final int count;
  final double px, bx, by, bvx, bvy, pause;
  final int myScore, oppoScore; 

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

  PongData.fromPayload(Int16List data, double width, double height)
      : count = fromInt16(data, 0, width).toInt(), 
        px = fromInt16(data, 1, width),
        bx = fromInt16(data, 2, width),
        by = fromInt16(data, 3, height),
        bvx = fromInt16(data, 4, width),
        bvy = fromInt16(data, 5, height),
        pause = fromInt16(data, 6),
        myScore = fromInt16(data, 7).toInt(),
        oppoScore = fromInt16(data, 8).toInt();

  Int16List toNetBundle(double width, double height) {
    return Int16List.fromList([
      count,
      toInt16(px, width),
      toInt16(bx, width),
      toInt16(height - by, height),
      toInt16(bvx, width),
      toInt16(-bvy, height),
      toInt16(pause),
      toInt16(oppoScore.toDouble()),
      toInt16(myScore.toDouble()),
    ]);
  }
}

int toInt16(double v, [double max = 32767]) => 32767 * v ~/ max;

double fromInt16(Int16List d, int i, [double max = 32767]) =>
    d != null && d.length > i ? max * d[i] / 32767 : 0;

/// Pong Networking Service for Host and Guest, incl discovery & communication.
class PongNetSvc {
  String myName;
  double width, height; // size of my world
  BonsoirService _mySvc = null; // network game I am hosting
  BonsoirBroadcast _myBroadcast = null;
  Map<String, ResolvedBonsoirService> _host2svc = {}; // other hosts
  Function _onDiscovery;
  InternetAddress _oppoAddress = null;
  RawDatagramSocket _sock = null;

  PongNetSvc(this.myName, this._onDiscovery, this.width, this.height) {
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
          _host2svc[e.service.name] = e.service;
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
      name: 'Pong with ${myName}',
      type: PONG_SVC_TYPE,
      port: PONG_PORT,
    );

    _myBroadcast = BonsoirBroadcast(service: _mySvc);
    await _myBroadcast.ready;
    await _myBroadcast.start();

    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock.listen(
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

  void joinGame(String name, Function(PongData) onMsg, Function onDone) async {
    final hostSvc = _host2svc[name];
    _oppoAddress = InternetAddress(hostSvc.ip);
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock.listen(
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
    _sock.send(
      data.toNetBundle(width, height).buffer.asInt8List(),
      _oppoAddress,
      PONG_PORT,
    );
  }

  void _onEvent(Function(PongData) onMsg, RawSocketEvent event) {
    final packet = _sock?.receive();
    if (packet == null) return;
    final data = PongData.fromPayload(
      packet.data.buffer.asInt16List(),
      width,
      height,
    );
    if (data.count == null) return; // bad data packet?
    _oppoAddress = packet.address;
    onMsg(data);
  }

  void _finishedHandler(Function() onDone, [Object e = null]) {
    if (e != null) print(e);
    onDone();
  }

  void _safeCloseSocket() {
    if (_sock != null) {
      _sock.close();
      _sock = null;
    }
  }

  void _safeStopBroadcast() async {
    if (_myBroadcast != null) {
      await _myBroadcast.stop();
      _myBroadcast = null;
    }
    if (_mySvc != null) _mySvc = null;
  }
}
