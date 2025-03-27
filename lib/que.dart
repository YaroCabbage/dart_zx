import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

class Que {
  Que(this.uuid) {
    queEcho = queEchoController.stream;
  }

  final StreamController<String> queEchoController =
      StreamController<String>.broadcast();
  late final Stream<String> queEcho;
  final Uuid uuid;

  void dispose() {
    queEchoController.close();
  }

  bool verbose = false;
  bool locked = false;

  final que = <String>[];

  Future<void> wait() async {
    String key = uuid.v1();
    que.add(key);
    if (verbose) {
      stdout.writeln('Lock: $key');
    }
    await queEcho.firstWhere((e) => e == key);
    if (verbose) {
      stdout.writeln('Unlock: $key');
    }
  }

  void chooseNext() {
    if (que.isEmpty) return;
    queEchoController.add(que.removeAt(0));
  }

  /// ожидание
  Future<void> lock() async {
    if (locked) {
      await wait();
    }
    locked = true;
  }

  /// передача следующему
  void unlock() {
    locked = false;
    chooseNext();
  }
}
