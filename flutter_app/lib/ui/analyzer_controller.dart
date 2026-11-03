import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/kml.dart';
import '../core/models.dart';
import '../core/official_bridge.dart';
import '../core/worker.dart';

class AnalyzerController extends ChangeNotifier {
  final source = ProtocolTextController();
  final distanceKm = TextEditingController(text: '1.5');
  final durationMin = TextEditingController(text: '30');
  final heartbeatExpectedMin = TextEditingController(text: '5');

  final OfficialBridgeClient _bridge = OfficialBridgeClient();
  Isolate? _isolate;
  Completer<void>? _activeDone;
  int _runId = 0;

  Protocol protocol = Protocol.concox;
  InputMode inputMode = InputMode.officialText;
  OfficialWindowMode officialWindowMode = OfficialWindowMode.background;
  bool chineseKml = false;
  bool detailedKml = false;
  bool filterZero = true;
  bool filterMtkRollback = false;
  bool sidebarOpen = true;
  bool terminalOpen = false;
  bool busy = false;
  double progress = 0;
  String progressLabel = '';
  ParsedData? parsed;
  KmlResult? kml;
  String? officialOutput, officialJobDirectory;
  int resultRevision = 0;
  int importRevision = 0;
  final List<String> logs = <String>['[READY] Parser core initialized'];

  ParseOptions get options => ParseOptions(
    protocol: protocol,
    filterZero: filterZero,
    filterMtkRollback: filterMtkRollback,
    detailed: detailedKml,
    chinese: chineseKml,
    driftMeters: (double.tryParse(distanceKm.text) ?? 1.5) * 1000,
    driftSeconds: (double.tryParse(durationMin.text) ?? 30) * 60,
  );

  void setProtocol(Protocol value) {
    protocol = value;
    notifyListeners();
  }

  void setInputMode(InputMode value) {
    inputMode = value;
    notifyListeners();
  }

  void setOfficialWindowMode(OfficialWindowMode value) {
    officialWindowMode = value;
    notifyListeners();
  }

  void setChineseKml(bool value) {
    chineseKml = value;
    notifyListeners();
  }

  void setFilterZero(bool value) {
    filterZero = value;
    notifyListeners();
  }

  void setFilterMtkRollback(bool value) {
    filterMtkRollback = value;
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarOpen = !sidebarOpen;
    notifyListeners();
  }

  void toggleTerminal() {
    terminalOpen = !terminalOpen;
    notifyListeners();
  }

  void setTerminalOpen(bool value) {
    if (terminalOpen == value) return;
    terminalOpen = value;
    notifyListeners();
  }

  Future<void> copyTerminalLogs() async {
    await Clipboard.setData(ClipboardData(text: logs.join('\n')));
  }

  String _heartbeatInterval(Duration? value) {
    if (value == null) return '--';
    final seconds = value.inMilliseconds / 1000;
    return seconds >= 60
        ? '${(seconds / 60).toStringAsFixed(1)} min'
        : '${seconds.toStringAsFixed(1)} s';
  }

  String _heartbeatTime(DateTime? value) =>
      value == null ? '--' : localTime(value);

  void setSource(String value, {String origin = 'INPUT'}) {
    source.setSource(value);
    importRevision++;
    _log(
      '[$origin] ${source.sourceLength} chars, ${source.sourceLineCount} lines',
    );
    notifyListeners();
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _log('[WARN] Clipboard contains no text');
      notifyListeners();
      return;
    }
    setSource(text, origin: 'PASTE');
  }

  Future<void> importFile() async {
    const textFiles = XTypeGroup(
      label: 'Text logs',
      extensions: <String>['txt', 'log'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[textFiles],
    );
    if (file == null) return;
    setSource(await file.readAsString(), origin: 'FILE');
  }

  Future<void> parse() async {
    if (busy) return;
    final input = source.sourceText;
    if (input.trim().isEmpty) {
      _log('[ERROR] Paste or import protocol text first');
      terminalOpen = true;
      notifyListeners();
      return;
    }
    final runId = ++_runId;
    busy = true;
    parsed = null;
    kml = null;
    progress = 0;
    progressLabel = inputMode == InputMode.rawLog ? '正在启动官方工具' : '正在准备解析';
    _log(
      '[PARSE] ${protocol == Protocol.concox ? 'Concox / GT06' : 'JT/T808'} '
      '${inputMode == InputMode.rawLog ? 'raw' : 'official-text'} started',
    );
    notifyListeners();

    String officialText = input;
    if (inputMode == InputMode.rawLog) {
      try {
        final bridgeResult = await _bridge.parse(
          input,
          protocol: protocol,
          windowMode: officialWindowMode,
          onProgress: (message) {
            if (runId != _runId) return;
            progress = .05;
            progressLabel = message;
            notifyListeners();
          },
        );
        if (runId != _runId) return;
        officialText = bridgeResult.output;
        officialOutput = officialText;
        officialJobDirectory = bridgeResult.jobDirectory;
        progress = .18;
        progressLabel = '正在融合';
        _log('[OFFICIAL] ${officialText.length} chars received');
      } catch (error) {
        if (runId != _runId) return;
        busy = false;
        terminalOpen = true;
        final detail = error.toString();
        final message = detail.contains('ProtocolAnalysis.exe') ||
                detail.contains('找不到官方程序')
            ? '未找到官方解析工具，请将 ProtocolAnalysis.exe 放到 TraceForge.exe 同目录。'
            : '解析未完成，请重试！';
        progressLabel = message;
        _log('[ERROR] $message');
        notifyListeners();
        return;
      }
    }

    final port = ReceivePort();
    StreamSubscription<dynamic>? subscription;
    final done = Completer<void>();
    _activeDone = done;
    try {
      _isolate = await Isolate.spawn(
        generateInBackground,
        WorkerRequest(
          port.sendPort,
          officialText,
          options,
          rawSource: inputMode == InputMode.rawLog ? input : null,
        ),
      );
      subscription = port.listen((dynamic raw) {
        if (runId != _runId) return;
        final event = raw as List<Object?>;
        switch (event[0]) {
          case 0:
            progress = (event[1] as num).toDouble().clamp(0, 1);
            progressLabel = event[2] as String;
            notifyListeners();
          case 1:
            parsed = event[1] as ParsedData;
            kml = event[2] as KmlResult;
            progress = 1;
            progressLabel = 'Complete';
            busy = false;
            sidebarOpen = false;
            resultRevision++;
            final data = parsed!;
            _log(
              '[DONE] ${data.packets.length} packets, ${data.points.length} locations',
            );
            _log(
              '[ALARM] ${data.packets.where((p) => p.alarm).length} alarm packets',
            );
            final commandCount = data.packets
                .where((packet) => packet.command)
                .length;
            _log('[COMMAND] $commandCount Concox downlink commands');
            _log(
              '[FILTER] ${data.diagnostics.zeroCoordinatesFiltered} zero coordinates, '
              '${data.diagnostics.mtkRollbackFiltered} MTK rollback locations',
            );
            if (inputMode == InputMode.rawLog) {
              final d = data.diagnostics;
              final heartbeat = HeartbeatStats.fromPackets(
                data.packets,
                expectedInterval: Duration(
                  minutes: int.tryParse(heartbeatExpectedMin.text) ?? 5,
                ),
              );
              _log(
                '[FUSION] raw=${d.rawRecords}, fused=${d.fusedRecords}, '
                'ambiguous=${d.ambiguousRecords}, unmatchedRaw=${d.unmatchedRawRecords}, '
                'unmatchedOfficial=${d.unmatchedOfficialPackets}, formatIssues=${d.rawFormatIssues}',
              );
              _log(
                '[HEARTBEAT] total=${heartbeat.total}, uplink=${heartbeat.uplink}, '
                'reply=${heartbeat.replies}, exact=${heartbeat.exactTimes}, '
                'unresolved=${heartbeat.unresolved}, breaks=${heartbeat.breakpoints}',
              );
              _log(
                '[HEARTBEAT TIME] first=${_heartbeatTime(heartbeat.first)}, '
                'last=${_heartbeatTime(heartbeat.last)}, '
                'average=${_heartbeatInterval(heartbeat.averageInterval)}, '
                'shortest=${_heartbeatInterval(heartbeat.shortestInterval)}, '
                'longest=${_heartbeatInterval(heartbeat.longestInterval)}',
              );
              _log(
                '[OFFICIAL] errorPackets=${d.officialErrorPackets ?? 'unknown'}',
              );
            }
            _log(
              '[KML] ${kml!.text.length} chars, ${kml!.driftCount} drift segments',
            );
            notifyListeners();
            if (!done.isCompleted) done.complete();
          case 2:
            busy = false;
            terminalOpen = true;
            _log('[ERROR] ${event[1]}');
            notifyListeners();
            if (!done.isCompleted) done.complete();
        }
      });
      await done.future;
    } catch (error) {
      busy = false;
      terminalOpen = true;
      _log('[ERROR] $error');
      notifyListeners();
    } finally {
      await subscription?.cancel();
      port.close();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      if (identical(_activeDone, done)) _activeDone = null;
    }
  }

  void cancel() {
    if (!busy) return;
    _runId++;
    _bridge.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    if (_activeDone?.isCompleted == false) _activeDone!.complete();
    _activeDone = null;
    busy = false;
    progressLabel = '已取消';
    terminalOpen = true;
    _log('[CANCEL] Task cancelled; user input retained');
    notifyListeners();
  }

  Future<bool> copyKml() async {
    final output = kml?.text;
    if (output == null || output.isEmpty) {
      _log('[WARN] No KML available to copy');
      notifyListeners();
      return false;
    }
    await Clipboard.setData(ClipboardData(text: output));
    _log('[COPY] KML copied to clipboard');
    notifyListeners();
    return true;
  }

  Future<void> exportKml() async {
    final output = kml?.text;
    if (output == null || output.isEmpty) {
      _log('[WARN] No KML available for export');
      notifyListeners();
      return;
    }
    final identity = parsed;
    String safePart(String value) => value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final nameParts = <String>[
      'GPS_Track',
      if (identity?.model?.trim().isNotEmpty == true)
        safePart(identity!.model!),
      if (identity?.device?.trim().isNotEmpty == true)
        safePart(identity!.device!),
    ];
    final location = await getSaveLocation(
      suggestedName: '${nameParts.join('_')}.kml',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Google Earth KML', extensions: <String>['kml']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString(output);
    _log('[EXPORT] ${location.path}');
    notifyListeners();
  }

  void _log(String value) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    logs.add('$stamp  $value');
    if (logs.length > 300) logs.removeRange(0, logs.length - 300);
  }

  @override
  void dispose() {
    source.dispose();
    distanceKm.dispose();
    durationMin.dispose();
    heartbeatExpectedMin.dispose();
    _bridge.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }
}

/// 小型输入使用关键字着色；超大文本直接使用单一 TextSpan，避免正则高亮拖慢编辑。
class ProtocolTextController extends TextEditingController {
  ProtocolTextController({this.previewLimit = 16000});

  final int previewLimit;
  String? _fullSource;
  int _fullLineCount = 0;
  int _visibleLimit = 0;

  bool get isPreviewing => _fullSource != null;
  bool get hasMorePreview =>
      _fullSource != null && super.text.length < _fullSource!.length;
  int get visibleLength => super.text.length;
  int get sourceLength => (_fullSource ?? text).length;
  String get sourceText => _fullSource ?? text;
  int get sourceLineCount {
    if (_fullSource != null) return _fullLineCount;
    return text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
  }

  void setSource(String source) {
    if (source.length <= previewLimit) {
      _fullSource = null;
      _fullLineCount = 0;
      _visibleLimit = source.length;
      super.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      return;
    }

    _fullSource = source;
    _fullLineCount = source.isEmpty ? 0 : '\n'.allMatches(source).length + 1;
    _visibleLimit = previewLimit;
    final visible = source.substring(0, _visibleLimit);
    super.value = TextEditingValue(
      text: visible,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  bool loadNextPreviewPage() {
    final full = _fullSource;
    if (full == null || !hasMorePreview) return false;

    // 每次只扩展一页，不把数 MB 原文一次交给 TextField 排版。
    final next = super.text.length + previewLimit;
    _visibleLimit = next < full.length ? next : full.length;
    final oldSelection = super.selection;
    final base = oldSelection.baseOffset.clamp(0, _visibleLimit);
    final extent = oldSelection.extentOffset.clamp(0, _visibleLimit);
    super.value = TextEditingValue(
      text: full.substring(0, _visibleLimit),
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );
    return true;
  }

  @override
  set value(TextEditingValue newValue) {
    final full = _fullSource;
    final oldPreview = super.text;
    // Selection-only updates must not discard the full source kept off-screen.
    if (full != null && newValue.text == oldPreview) {
      super.value = newValue;
      return;
    }
    if (full != null) {
      // Map edits in the bounded preview back into the full source. Selecting
      // the whole preview means replace the whole source, which keeps Ctrl+A
      // followed by Ctrl+V or Windows clipboard history intuitive.
      var prefix = 0;
      final prefixLimit = oldPreview.length < newValue.text.length
          ? oldPreview.length
          : newValue.text.length;
      while (prefix < prefixLimit &&
          oldPreview.codeUnitAt(prefix) == newValue.text.codeUnitAt(prefix)) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < oldPreview.length - prefix &&
          suffix < newValue.text.length - prefix &&
          oldPreview.codeUnitAt(oldPreview.length - 1 - suffix) ==
              newValue.text.codeUnitAt(newValue.text.length - 1 - suffix)) {
        suffix++;
      }
      final oldEnd = oldPreview.length - suffix;
      final newEnd = newValue.text.length - suffix;
      final inserted = newValue.text.substring(prefix, newEnd);
      final replaceWhole = prefix == 0 && oldEnd == oldPreview.length;
      final fullEnd = replaceWhole ? full.length : oldEnd;
      final updated = full.replaceRange(prefix, fullEnd, inserted);
      final caret = (prefix + inserted.length).clamp(0, updated.length);
      if (updated.length <= previewLimit) {
        _fullSource = null;
        _fullLineCount = 0;
        _visibleLimit = updated.length;
        super.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: caret),
        );
      } else {
        _fullSource = updated;
        _fullLineCount = '\n'.allMatches(updated).length + 1;
        // 编辑已加载的页时保留当前可见边界，不退回第一页。
        _visibleLimit = _visibleLimit.clamp(previewLimit, updated.length);
        super.value = TextEditingValue(
          text: updated.substring(0, _visibleLimit),
          selection: TextSelection.collapsed(
            offset: caret.clamp(0, _visibleLimit),
          ),
        );
      }
      return;
    }
    // Both direct keyboard paste and Windows clipboard history eventually set
    // controller.value. Truncate before Flutter lays out the large paragraph.
    if (newValue.text.length > previewLimit) {
      setSource(newValue.text);
      return;
    }
    _fullSource = null;
    _fullLineCount = 0;
    _visibleLimit = newValue.text.length;
    super.value = newValue;
  }

  @override
  void clear() {
    _fullSource = null;
    _fullLineCount = 0;
    _visibleLimit = 0;
    super.clear();
  }

  static final _tokens = RegExp(
    r'(告警类型|报警包|报警|ERROR|FAIL)|'
    r'(ACC高|ACC开|ACC低|ACC关)|'
    r'(时间|纬度|经度|速度|定位状态|包类型)|'
    r'(<[^>]*第\s*\d+\s*条包[^>]*>)',
    caseSensitive: false,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _tokens.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      final alarm = RegExp(
        r'告警|报警|ERROR|FAIL',
        caseSensitive: false,
      ).hasMatch(token);
      final acc = token.startsWith('ACC');
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(
            color: alarm
                ? const Color(0xFFFF6B35)
                : acc
                ? const Color(0xFFFFB454)
                : const Color(0xFF00D4AA),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
