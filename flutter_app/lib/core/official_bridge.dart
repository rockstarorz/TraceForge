import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

typedef BridgeProgress = void Function(String message);

class OfficialBridgeResult {
  const OfficialBridgeResult({
    required this.output,
    required this.jobDirectory,
    required this.metadata,
  });
  final String output, jobDirectory;
  final Map<String, Object?> metadata;
}

class OfficialBridgeClient {
  Process? _process;
  Directory? _job;
  bool get running => _process != null;

  Future<OfficialBridgeResult> parse(
    String source, {
    required Protocol protocol,
    required OfficialWindowMode windowMode,
    required BridgeProgress onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('官方解析桥接仅支持 Windows');
    }
    if (_process != null) throw StateError('官方解析任务已在运行');
    final launch = _resolveLaunch();
    final job = await Directory.systemTemp.createTemp('traceforge-official-');
    _job = job;
    final input = File('${job.path}${Platform.pathSeparator}submitted.txt');
    await input.writeAsString(source, flush: true);
    final args = <String>[
      ...launch.prefixArguments,
      'parse',
      '--input',
      input.path,
      '--launch',
      '--timeout',
      '0',
      '--worker',
      '--protocol',
      protocol.name,
      '--window-mode',
      windowMode.name,
      '--job-dir',
      job.path,
      if (launch.officialExe != null) ...['--exe', launch.officialExe!],
    ];
    onProgress('正在启动官方工具');
    final process = await Process.start(
      launch.executable,
      args,
      workingDirectory: launch.workingDirectory,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    _process = process;
    var progressLines = 0;
    var lastProgress = '';
    void reportProgress(String message) {
      final normalized = message.trim();
      if (normalized.isEmpty || normalized == lastProgress) return;
      lastProgress = normalized;
      onProgress(normalized);
    }

    final progressTimer = Timer.periodic(const Duration(milliseconds: 350), (
      _,
    ) {
      final file = File('${job.path}${Platform.pathSeparator}progress.log');
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      for (final line in lines.skip(progressLines)) {
        reportProgress(line.length > 9 ? line.substring(9) : line);
      }
      progressLines = lines.length;
    });
    final stderr = StringBuffer();
    final outDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('[桥接]')) reportProgress(line.substring(4));
        })
        .asFuture<void>();
    final errDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write)
        .asFuture<void>();
    final code = await process.exitCode;
    progressTimer.cancel();
    await Future.wait([outDone, errDone]);
    _process = null;
    _job = null;
    final resultFile = File('${job.path}${Platform.pathSeparator}result.json');
    Map<String, Object?> metadata = const {};
    if (await resultFile.exists()) {
      metadata = (jsonDecode(await resultFile.readAsString()) as Map)
          .cast<String, Object?>();
    }
    if (code != 0 || metadata['status'] != 'ok') {
      throw StateError(
        (metadata['error'] as String?) ??
            stderr.toString().trim().split('\n').lastOrNull ??
            '官方解析桥接未完成',
      );
    }
    final output = File('${job.path}${Platform.pathSeparator}parsed.txt');
    if (!await output.exists()) throw StateError('官方结果文件不存在');
    return OfficialBridgeResult(
      output: await output.readAsString(),
      jobDirectory: job.path,
      metadata: metadata,
    );
  }

  void cancel() {
    final process = _process;
    final job = _job;
    if (process == null) return;
    if (job != null) {
      File(
        '${job.path}${Platform.pathSeparator}cancel.request',
      ).writeAsStringSync('cancel');
    }
    Timer(const Duration(seconds: 2), () {
      if (identical(_process, process)) process.kill();
    });
  }

  _BridgeLaunch _resolveLaunch() {
    final environment = Platform.environment;
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final bridgeOverride = environment['OFFICIAL_BRIDGE_EXE'];
    final exeCandidates = <String>[
      ?bridgeOverride,
      '$appDir${Platform.pathSeparator}official_bridge.exe',
      '${Directory.current.path}${Platform.pathSeparator}official_bridge.exe',
    ];
    for (final candidate in exeCandidates) {
      if (File(candidate).existsSync()) {
        return _BridgeLaunch(
          candidate,
          const [],
          File(candidate).parent.path,
          _officialExe(appDir),
        );
      }
    }
    final scriptCandidates = <String>[
      '${Directory.current.path}${Platform.pathSeparator}official_bridge${Platform.pathSeparator}bridge.py',
      '${Directory.current.parent.path}${Platform.pathSeparator}official_bridge${Platform.pathSeparator}bridge.py',
      '$appDir${Platform.pathSeparator}official_bridge${Platform.pathSeparator}bridge.py',
    ];
    for (final script in scriptCandidates) {
      if (File(script).existsSync()) {
        final pythonCandidates = <String>[
          ?environment['OFFICIAL_BRIDGE_PYTHON'],
          '${File(script).parent.path}${Platform.pathSeparator}.venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
        ];
        final python =
            pythonCandidates
                .where((path) => File(path).existsSync())
                .firstOrNull ??
            'python';
        return _BridgeLaunch(
          python,
          [script],
          File(script).parent.path,
          _officialExe(appDir),
        );
      }
    }
    throw StateError(
      '未找到官方解析桥接工具，请将 official_bridge.exe 放到 TraceForge.exe 同目录',
    );
  }

  String? _officialExe(String appDir) {
    final override = Platform.environment['PROTOCOL_ANALYSIS_EXE'];
    final candidates = <String>[
      ?override,
      '$appDir${Platform.pathSeparator}ProtocolAnalysis.exe',
      '${Directory.current.path}${Platform.pathSeparator}ProtocolAnalysis.exe',
    ];
    return candidates.where((path) => File(path).existsSync()).firstOrNull;
  }
}

class _BridgeLaunch {
  const _BridgeLaunch(
    this.executable,
    this.prefixArguments,
    this.workingDirectory,
    this.officialExe,
  );
  final String executable, workingDirectory;
  final List<String> prefixArguments;
  final String? officialExe;
}
