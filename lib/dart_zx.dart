import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:dart_zx/que.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

class Base {
  Base() {
    enableAnsiColor = false;
  }

  static const uuid = Uuid();
  final ansiStdout = AnsiPen()..green();
  final ansiStderr = AnsiPen()..red();

  bool verbose = false;

  bool get enableAnsiColor => ansiColorDisabled;

  set enableAnsiColor(value) => ansiColorDisabled = value;

  bool stopOnError = false;

  Future<ProcessResult> run(String script,
      {bool bash = true, String? workingDirectory}) async {
    Process process;
    if (bash) {
      process = await Process.start('bash', ['-c', script],
          workingDirectory: workingDirectory);
    } else {
      final scriptParts = script.split(" ").map((e) => e.trim()).toList();

      final exe = scriptParts.removeAt(0).trim();
      process = await Process.start(exe, scriptParts,
          workingDirectory: workingDirectory);
    }
    print("\$ $script");

    final processStdout = process.stdout.asBroadcastStream();
    final processStderr = process.stderr.asBroadcastStream();

    final processStdoutStr = utf8.decoder.bind(processStdout);
    final processStderrStr = utf8.decoder.bind(processStderr);

    StreamSubscription<String>? listenProcessStdoutStr;
    StreamSubscription<String>? listenProcessStderrStr;

    if (verbose) {
      listenProcessStdoutStr =
          processStdoutStr.listen((v) => stdout.write(ansiStdout(v)));
      listenProcessStderrStr =
          processStderrStr.listen((v) => stdout.write(ansiStderr(v)));
    }

    final processExitCode = process.exitCode;
    final processStdoutResult = processStdoutStr.toList();
    final processStderrResult = processStderrStr.toList();

    return (processExitCode, processStdoutResult, processStderrResult)
        .wait
        .then((result) {
      listenProcessStdoutStr?.cancel();
      listenProcessStderrStr?.cancel();
      return ProcessResult(process.pid, result.$1, result.$2, result.$3);
    });
  }

  Future<ZxProcess> start({
    String? startScript,
    bool bash = true,
    String? workingDirectory,
    bool? verbose,
  }) async {
    Process process;
    if (bash) {
      process =
          await Process.start('bash', [], workingDirectory: workingDirectory);
    } else {
      startScript!;
      final scriptParts = startScript.split(" ").map((e) => e.trim()).toList();

      final exe = scriptParts.removeAt(0).trim();
      process = await Process.start(exe, scriptParts,
          workingDirectory: workingDirectory);
      print("\$ $startScript");
    }
    final zxProcess = ZxProcess(process: process);

    /// Automatically starting subprocess
    if (bash && startScript != null) {
      final subProcess = zxProcess.run(startScript);
      subProcess.wait.whenComplete(() => zxProcess.kill());
    }

    if (verbose ?? this.verbose) {
      final processExitCode = process.exitCode;

      StreamSubscription<String>? listenProcessStdoutStr;
      StreamSubscription<String>? listenProcessStderrStr;

      listenProcessStdoutStr =
          zxProcess.stdoutStr.listen((v) => stdout.write(ansiStdout(v)));
      listenProcessStderrStr =
          zxProcess.stderrStr.listen((v) => stdout.write(ansiStderr(v)));

      processExitCode.then((result) {
        listenProcessStdoutStr?.cancel();
        listenProcessStderrStr?.cancel();
      });
    }

    return zxProcess;
  }

  Future<ProcessResult> call(String script, {String? workingDirectory}) {
    return run(script, workingDirectory: workingDirectory);
  }
}

final $ = Base();

extension S on ProcessResult {}

class ZxProcess implements Process {
  final Process process;
  final Que que;
  final Map<String, ZxSubProcess> subProcesses = {};

  ZxProcess({required this.process}) : que = Que(Base.uuid) {
    _processStdout = process.stdout.asBroadcastStream();
    _processStderr = process.stderr.asBroadcastStream();
  }

  late final Stream<List<int>> _processStdout;

  late final Stream<List<int>> _processStderr;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return process.kill(signal);
  }

  @override
  int get pid => process.pid;

  @override
  Stream<List<int>> get stderr => _processStderr;

  @override
  IOSink get stdin => process.stdin;

  @override
  Stream<List<int>> get stdout => _processStdout;

  Stream<String> get stdoutStr => utf8.decoder.bind(_processStdout);

  Stream<String> get stderrStr => utf8.decoder.bind(_processStderr);

  void runStartScript(String script) {}

  ZxSubProcess run(
    String script, {
    Map<String, String> environment = const {},
  }) {
    final commandId = Base.uuid.v1();
    final ok = '$commandId-OK';
    final failed = '$commandId-Failed';
    final onFailed = stderrStr.firstWhere((str) => str.contains(commandId));
    final onSuccess = stdoutStr.firstWhere((str) => str.contains(commandId));
    final onCompleted = Future.any([onFailed, onSuccess]);

    final subStdout =
        _processStdout.takeUntil(onCompleted.asStream()).asBroadcastStream();
    final subStderr =
        _processStderr.takeUntil(onCompleted.asStream()).asBroadcastStream();

    environment.forEach((key, value) {
      stdin.writeln('export $key="$value"');
    });

    final command = '$script && echo $ok || echo $failed';
    print("\$ $command");
    stdin.writeln(command);

    onCompleted.then((_) {
      environment.forEach((key, value) {
        stdin.writeln('unset $key');
      });
      subProcesses.remove(commandId);
    });

    return subProcesses[commandId] ??= ZxSubProcess(
      id: commandId,
      stdout: subStdout,
      stderr: subStderr,
      onFailed: onFailed,
      onSuccess: onSuccess,
    );
  }
}

class ZxSubProcess {
  final String id;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final Future<String> onFailed;
  final Future<String> onSuccess;

  ZxSubProcess({
    required this.id,
    required this.stdout,
    required this.stderr,
    required this.onFailed,
    required this.onSuccess,
  });

  Future<String> get wait => Future.any([onFailed, onSuccess]);
}
