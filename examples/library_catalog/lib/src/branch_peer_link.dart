import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zuke_annotations/zuke_annotations.dart';

/// One library branch endpoint that accepts peer connections from sibling
/// branches and exchanges loan-register snapshots over a plain TCP socket.
@ImplementsRequirement(['RULE-LIBRARY-BRANCH-PEER'])
final class BranchPeerServer {
  static const _deliveryTimeout = Duration(seconds: 2);

  final String branchId;
  final List<String> localLoans = [];
  final List<String> peerLoans = [];
  ServerSocket? _server;

  /// Outbound connections keyed by destination branch, so a share can only
  /// ever reach the branch it names.
  final _outbound = <String, Socket>{};
  final _listening = Completer<void>();
  final _connected = Completer<void>();
  final _loanWaiters = <Completer<void>>[];

  BranchPeerServer(this.branchId);

  int? get port => _server?.port;
  bool get isListening => _listening.isCompleted;
  bool get isConnected => _connected.isCompleted;

  Future<void> listen() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _listenForMessages(socket);
      if (!_connected.isCompleted) _connected.complete();
    });
    if (!_listening.isCompleted) _listening.complete();
  }

  Future<void> connectTo(BranchPeerServer peer) async {
    await _listening.future;
    await peer._listening.future;
    final port = peer.port;
    if (port == null) {
      throw StateError('Peer branch ${peer.branchId} is not listening.');
    }
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final previous = _outbound[peer.branchId];
    _outbound[peer.branchId] = socket;
    await previous?.close();
    _listenForMessages(
      socket,
      onClosed: () {
        if (identical(_outbound[peer.branchId], socket)) {
          _outbound.remove(peer.branchId);
        }
      },
    );
    socket.write('HELLO $branchId\n');
    await socket.flush();
    if (!_connected.isCompleted) _connected.complete();
    await peer._connected.future.timeout(_deliveryTimeout);
  }

  /// Sends this branch's loans to [peer] and waits until [peer] has them.
  ///
  /// Throws when this branch has no connection to [peer], or when delivery is
  /// not confirmed in time.
  Future<void> shareLoansWith(BranchPeerServer peer) async {
    final socket = _outbound[peer.branchId];
    if (socket == null) {
      throw StateError(
        'Branch $branchId has no active connection to ${peer.branchId}.',
      );
    }
    final waiter = Completer<void>();
    peer._loanWaiters.add(waiter);
    try {
      socket.write('LOANS ${jsonEncode(localLoans)}\n');
      await socket.flush();
      await waiter.future.timeout(
        _deliveryTimeout,
        onTimeout: () => throw StateError(
          'Branch ${peer.branchId} did not confirm loans from $branchId.',
        ),
      );
    } finally {
      peer._loanWaiters.remove(waiter);
    }
  }

  void seedLocalLoan(String isbn) {
    if (!localLoans.contains(isbn)) localLoans.add(isbn);
  }

  void _onLine(String line) {
    if (line.startsWith('LOANS ')) {
      final decoded = jsonDecode(line.substring(6)) as List<dynamic>;
      peerLoans
        ..clear()
        ..addAll(decoded.cast<String>());
      if (_loanWaiters.isNotEmpty) {
        final waiter = _loanWaiters.removeAt(0);
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  void _listenForMessages(Socket socket, {void Function()? onClosed}) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onDone: () => onClosed?.call(),
          onError: (_) => onClosed?.call(),
        );
  }

  Future<void> close() async {
    final sockets = _outbound.values.toList();
    _outbound.clear();
    for (final socket in sockets) {
      await socket.close();
    }
    await _server?.close();
    _server = null;
  }
}
