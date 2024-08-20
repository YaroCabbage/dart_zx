import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';

class Base {
  Base();

  final ansiStdout = AnsiPen()..green();
  final ansiStderr = AnsiPen()..red();

  bool verbose = false;
  bool stopOnError = false;

  Future<ProcessResult> run(String script, {bool bash = true, String? workingDirectory}) async {
    Process process;
    if (bash) {
      process = await Process.start('bash', ['-c', script], workingDirectory: workingDirectory);
    } else {
      final scriptParts = script.split(" ").map((e) => e.trim()).toList();

      final exe = scriptParts.removeAt(0).trim();
      process = await Process.start(exe, scriptParts, workingDirectory: workingDirectory);
    }
    print("\$ $script");

    final processStdout = process.stdout.asBroadcastStream();
    final processStderr = process.stderr.asBroadcastStream();

    final processStdoutStr = utf8.decoder.bind(processStdout);
    final processStderrStr = utf8.decoder.bind(processStderr);

    StreamSubscription<String>? listenProcessStdoutStr;
    StreamSubscription<String>? listenProcessStderrStr;

    if (verbose) {
      listenProcessStdoutStr = processStdoutStr.listen((v) => stdout.write(ansiStdout(v)));
      listenProcessStderrStr = processStderrStr.listen((v) => stdout.write(ansiStderr(v)));
    }

    final processExitCode = process.exitCode;
    final processStdoutResult = processStdoutStr.toList();
    final processStderrResult = processStderrStr.toList();

    return (processExitCode, processStdoutResult, processStderrResult).wait.then((result) {
      listenProcessStdoutStr?.cancel();
      listenProcessStderrStr?.cancel();
      return ProcessResult(process.pid, result.$1, result.$2, result.$3);
    });
  }

  Future<ProcessResult> call(String script, {String? workingDirectory}) {
    return run(script, workingDirectory: workingDirectory);
  }
}

final $ = Base();

extension S on ProcessResult {}
