import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AssistantModel {
  const AssistantModel({
    required this.family,
    required this.name,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.minRamGb,
    required this.description,
  });

  final String family;
  final String name;
  final String fileName;
  final String url;
  final int sizeBytes;
  final int minRamGb;
  final String description;

  double get sizeGb => sizeBytes / (1024 * 1024 * 1024);
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

enum LlamaBuildVariant { cpu, vulkan }

class LlamaRuntimeService extends ChangeNotifier {
  LlamaRuntimeService({
    http.Client? client,
    Directory? root,
    Future<SharedPreferences> Function()? prefs,
  }) : _client = client ?? http.Client(),
       _rootOverride = root,
       _prefsLoader = prefs ?? SharedPreferences.getInstance;

  static final LlamaRuntimeService shared = LlamaRuntimeService();

  final http.Client _client;
  final Directory? _rootOverride;
  final Future<SharedPreferences> Function() _prefsLoader;

  String? get busyKey => _busyKey;
  String? _busyKey;

  String get busyStatus => _busyStatus;
  String _busyStatus = '';

  double? get busyProgress => _busyProgress;
  double? _busyProgress;

  static const String runtimeBusyKey = 'runtime';

  void _setBusyStatus(String status, double? progress) {
    final oldPct = _busyProgress == null ? -1 : (_busyProgress! * 100).floor();
    final newPct = progress == null ? -1 : (progress * 100).floor();
    final changed = status != _busyStatus || newPct != oldPct;
    _busyStatus = status;
    _busyProgress = progress;
    if (changed) notifyListeners();
  }

  Future<T> _withBusy<T>(String key, Future<T> Function() body) async {
    if (_busyKey != null) {
      throw StateError('Another download is running; wait for it to finish');
    }
    _busyKey = key;
    _cancelRequested = false;
    _setBusyStatus('Starting', null);
    try {
      return await body();
    } finally {
      _busyKey = null;
      _busyStatus = '';
      _busyProgress = null;
      notifyListeners();
    }
  }

  static const int serverPort = 8178;

  static const String _releasesLatestUrl =
      'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest';

  static const List<AssistantModel> catalog = <AssistantModel>[
    AssistantModel(
      family: 'Qwen 3.5',
      name: 'Qwen 3.5 0.8B',
      fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
      sizeBytes: 532517120,
      minRamGb: 4,
      description: 'Small and quick with decent quality.',
    ),
    AssistantModel(
      family: 'Qwen 3.5',
      name: 'Qwen 3.5 2B',
      fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
      sizeBytes: 1280835840,
      minRamGb: 6,
      description: 'Solid quality on modest hardware.',
    ),
    AssistantModel(
      family: 'Qwen 3.5',
      name: 'Qwen 3.5 4B',
      fileName: 'Qwen3.5-4B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
      sizeBytes: 2740937888,
      minRamGb: 8,
      description: 'Great quality for the size; a safe default.',
    ),
    AssistantModel(
      family: 'Gemma 4',
      name: 'Gemma 4 E2B',
      fileName: 'gemma-4-E2B-it-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
      sizeBytes: 3106736256,
      minRamGb: 8,
      description: 'Google efficient model; strong for its footprint.',
    ),
    AssistantModel(
      family: 'Gemma 4',
      name: 'Gemma 4 E4B',
      fileName: 'gemma-4-E4B-it-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf',
      sizeBytes: 4977169568,
      minRamGb: 16,
      description: 'Bigger Gemma; near-flagship answers on a strong laptop.',
    ),
    AssistantModel(
      family: 'Nemotron 3',
      name: 'Nemotron 3 Nano 4B',
      fileName: 'NVIDIA-Nemotron-3-Nano-4B-Q4_K_M.gguf',
      url: 'https://huggingface.co/lmstudio-community/NVIDIA-Nemotron-3-Nano-4B-GGUF/resolve/main/NVIDIA-Nemotron-3-Nano-4B-Q4_K_M.gguf',
      sizeBytes: 2837072896,
      minRamGb: 8,
      description: 'NVIDIA small reasoning model.',
    ),
    AssistantModel(
      family: 'Granite 4.1',
      name: 'Granite 4.1 3B',
      fileName: 'granite-4.1-3b-Q4_K_M.gguf',
      url: 'https://huggingface.co/ibm-granite/granite-4.1-3b-GGUF/resolve/main/granite-4.1-3b-Q4_K_M.gguf',
      sizeBytes: 2099501664,
      minRamGb: 8,
      description: 'IBM small model; reliable instruction following.',
    ),
    AssistantModel(
      family: 'Ornith 1.0',
      name: 'Ornith 1.0 9B',
      fileName: 'ornith-1.0-9b-Q4_K_M.gguf',
      url: 'https://huggingface.co/deepreinforce-ai/Ornith-1.0-9B-GGUF/resolve/main/ornith-1.0-9b-Q4_K_M.gguf',
      sizeBytes: 5629108704,
      minRamGb: 16,
      description: 'Largest option; best answers when hardware allows.',
    ),
    AssistantModel(
      family: 'LFM 2.5',
      name: 'LFM 2.5 230M',
      fileName: 'LFM2.5-230M-Q4_K_M.gguf',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf',
      sizeBytes: 153406304,
      minRamGb: 4,
      description: 'Liquid nano; the fastest possible, weakest answers.',
    ),
    AssistantModel(
      family: 'LFM 2.5',
      name: 'LFM 2.5 1.2B',
      fileName: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      sizeBytes: 730895168,
      minRamGb: 4,
      description: 'Liquid efficient model; very fast on CPU.',
    ),
    AssistantModel(
      family: 'LFM 2.5',
      name: 'LFM 2.5 8B A1B',
      fileName: 'LFM2.5-8B-A1B-Q4_K_M.gguf',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-GGUF/resolve/main/LFM2.5-8B-A1B-Q4_K_M.gguf',
      sizeBytes: 5155564768,
      minRamGb: 16,
      description: 'Mixture of experts: quick answers, 8B-sized memory.',
    ),
  ];

  static List<String> get families {
    final seen = <String>[];
    for (final model in catalog) {
      if (!seen.contains(model.family)) seen.add(model.family);
    }
    return seen;
  }

  static AssistantModel recommendedModel(int? ramGb) {
    AssistantModel smallest = catalog.first;
    AssistantModel? best;
    for (final model in catalog) {
      if (model.sizeBytes < smallest.sizeBytes) smallest = model;
      if (ramGb != null &&
          ramGb >= model.minRamGb &&
          (best == null || model.sizeBytes > best.sizeBytes)) {
        best = model;
      }
    }
    return best ?? smallest;
  }

  static String? assetNameFor(
    Iterable<String> assetNames, {
    required String os,
    required String arch,
    LlamaBuildVariant variant = LlamaBuildVariant.cpu,
  }) {
    final suffix = switch ((variant, os, arch)) {
      (LlamaBuildVariant.vulkan, 'linux', 'x64') =>
        'bin-ubuntu-vulkan-x64.tar.gz',
      (LlamaBuildVariant.vulkan, 'linux', 'arm64') =>
        'bin-ubuntu-vulkan-arm64.tar.gz',
      (LlamaBuildVariant.vulkan, 'windows', 'x64') => 'bin-win-vulkan-x64.zip',
      (LlamaBuildVariant.vulkan, _, _) => null,
      (LlamaBuildVariant.cpu, 'linux', 'x64') => 'bin-ubuntu-x64.tar.gz',
      (LlamaBuildVariant.cpu, 'linux', 'arm64') => 'bin-ubuntu-arm64.tar.gz',
      (LlamaBuildVariant.cpu, 'macos', 'arm64') => 'bin-macos-arm64.tar.gz',
      (LlamaBuildVariant.cpu, 'macos', 'x64') => 'bin-macos-x64.tar.gz',
      (LlamaBuildVariant.cpu, 'windows', 'x64') => 'bin-win-cpu-x64.zip',
      (LlamaBuildVariant.cpu, 'windows', 'arm64') => 'bin-win-cpu-arm64.zip',
      _ => null,
    };
    if (suffix == null) return null;
    for (final name in assetNames) {
      if (name.endsWith(suffix)) return name;
    }
    return null;
  }

  static bool vulkanAvailable({required String os, required String arch}) {
    return switch ((os, arch)) {
      ('linux', 'x64') || ('linux', 'arm64') || ('windows', 'x64') => true,
      _ => false,
    };
  }

  static bool get isVulkanAvailable =>
      vulkanAvailable(os: Platform.operatingSystem, arch: _currentArch);

  static const String variantPrefsKey = 'llama_runtime_variant_v1';

  Future<LlamaBuildVariant> selectedVariant() async {
    final prefs = await _prefsLoader();
    final stored = prefs.getString(variantPrefsKey);
    for (final variant in LlamaBuildVariant.values) {
      if (variant.name == stored) return variant;
    }
    return LlamaBuildVariant.cpu;
  }

  Future<void> setSelectedVariant(LlamaBuildVariant variant) async {
    final previous = await selectedVariant();
    final prefs = await _prefsLoader();
    await prefs.setString(variantPrefsKey, variant.name);
    if (previous == variant) return;
    final oldDir = await _runtimeDirFor(previous);
    if (await oldDir.exists()) {
      await oldDir.delete(recursive: true);
    }
    final oldVersionFile = await _versionFileFor(previous);
    if (await oldVersionFile.exists()) {
      await oldVersionFile.delete();
    }
  }

  static String get _currentArch =>
      Platform.version.contains('arm64') ? 'arm64' : 'x64';

  Future<int?> totalRamGb() async {
    try {
      if (Platform.isLinux) {
        final memInfo = await File('/proc/meminfo').readAsString();
        final match = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(memInfo);
        if (match == null) return null;
        return (int.parse(match.group(1)!) / (1024 * 1024)).round();
      }
      if (Platform.isMacOS) {
        final result = await Process.run('sysctl', ['-n', 'hw.memsize']);
        return (int.parse((result.stdout as String).trim()) /
                (1024 * 1024 * 1024))
            .round();
      }
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ]);
        return (int.parse((result.stdout as String).trim()) /
                (1024 * 1024 * 1024))
            .round();
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _root() async {
    final root =
        _rootOverride ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}llama',
        );
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _runtimeDir() async =>
      _runtimeDirFor(await selectedVariant());

  Future<Directory> _runtimeDirFor(LlamaBuildVariant variant) async {
    final dirName = variant == LlamaBuildVariant.cpu
        ? 'runtime'
        : 'runtime-${variant.name}';
    return Directory(
      '${(await _root()).path}${Platform.pathSeparator}$dirName',
    );
  }

  Future<Directory> _modelsDir() async {
    final dir = Directory(
      '${(await _root()).path}${Platform.pathSeparator}models',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _versionFile() async => _versionFileFor(await selectedVariant());

  Future<File> _versionFileFor(LlamaBuildVariant variant) async {
    final fileName = variant == LlamaBuildVariant.cpu
        ? 'VERSION'
        : 'VERSION-${variant.name}';
    return File('${(await _root()).path}${Platform.pathSeparator}$fileName');
  }

  Future<String?> installedTag() async {
    final file = await _versionFile();
    if (!await file.exists()) return null;
    final tag = (await file.readAsString()).trim();
    return tag.isEmpty ? null : tag;
  }

  Future<String?> serverBinaryPath() async {
    final dir = await _runtimeDir();
    if (!await dir.exists()) return null;
    final wanted = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File && entry.uri.pathSegments.last == wanted) {
        return entry.path;
      }
    }
    return null;
  }

  Future<({String tag, String? assetUrl})> fetchLatestRelease() async {
    final variant = await selectedVariant();
    final response = await _client
        .get(Uri.parse(_releasesLatestUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GitHub answered HTTP ${response.statusCode} for the latest '
        'llama.cpp release',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final tag = decoded['tag_name'] as String;
    final assets = (decoded['assets'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final assetName = assetNameFor(
      assets.map((a) => a['name'] as String),
      os: Platform.operatingSystem,
      arch: _currentArch,
      variant: variant,
    );
    final assetUrl =
        assets.firstWhere(
              (a) => a['name'] == assetName,
              orElse: () => const <String, dynamic>{},
            )['browser_download_url']
            as String?;
    return (tag: tag, assetUrl: assetUrl);
  }

  Future<String> ensureLatestRuntime({
    void Function(String status, double? progress)? onProgress,
  }) => _withBusy(runtimeBusyKey, () async {
    void report(String status, double? progress) {
      _setBusyStatus(status, progress);
      onProgress?.call(status, progress);
    }

    report('Checking for llama.cpp updates', null);
    final installed = await serverBinaryPath();
    ({String tag, String? assetUrl}) latest;
    try {
      latest = await fetchLatestRelease();
    } catch (_) {
      if (installed != null) return installed;
      rethrow;
    }
    if (installed != null && await installedTag() == latest.tag) {
      return installed;
    }
    final assetUrl = latest.assetUrl;
    if (assetUrl == null) {
      if (installed != null) return installed;
      throw UnsupportedError(
        'llama.cpp has no build for ${Platform.operatingSystem} '
        '($_currentArch)',
      );
    }

    final root = await _root();
    final archive = File(
      '${root.path}${Platform.pathSeparator}'
      '${Uri.parse(assetUrl).pathSegments.last}',
    );
    await _download(
      Uri.parse(assetUrl),
      archive,
      (received, total) => report(
        'Downloading llama.cpp ${latest.tag}',
        total == null ? null : received / total,
      ),
    );

    report('Installing llama.cpp ${latest.tag}', null);
    final runtime = await _runtimeDir();
    if (await runtime.exists()) await runtime.delete(recursive: true);
    await runtime.create(recursive: true);
    await _extract(archive, runtime);
    await archive.delete();
    await (await _versionFile()).writeAsString(latest.tag);

    final binary = await serverBinaryPath();
    if (binary == null) {
      throw StateError('llama-server missing from the extracted runtime');
    }
    return binary;
  });

  Future<void> _extract(File archive, Directory dest) async {
    final result = archive.path.endsWith('.zip')
        ? await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Expand-Archive -Path "${archive.path}" '
                '-DestinationPath "${dest.path}" -Force',
          ])
        : await Process.run('tar', ['-xzf', archive.path, '-C', dest.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'extract',
        [archive.path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }

  bool _cancelRequested = false;

  void cancelDownload() => _cancelRequested = true;

  Future<void> _download(
    Uri url,
    File dest,
    void Function(int received, int? total) onProgress,
  ) async {
    if (_cancelRequested) throw const DownloadCancelled();
    final response = await _client.send(http.Request('GET', url));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Download failed with HTTP ${response.statusCode}',
        url,
      );
    }

    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (_cancelRequested) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, response.contentLength);
      }
      await sink.flush();
      await sink.close();
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<File> _modelFile(AssistantModel model) async => File(
    '${(await _modelsDir()).path}${Platform.pathSeparator}${model.fileName}',
  );

  Future<bool> isModelInstalled(AssistantModel model) async =>
      (await _modelFile(model)).exists();

  Future<List<AssistantModel>> installedModels() async {
    final installed = <AssistantModel>[];
    for (final model in catalog) {
      if (await isModelInstalled(model)) installed.add(model);
    }
    return installed;
  }

  Future<void> downloadModel(
    AssistantModel model, {
    void Function(int received, int? total)? onProgress,
  }) => _withBusy(model.fileName, () async {
    await _download(Uri.parse(model.url), await _modelFile(model), (
      received,
      total,
    ) {
      _setBusyStatus('Downloading', total == null ? null : received / total);
      onProgress?.call(received, total);
    });
  });

  Future<void> deleteModel(AssistantModel model) async {
    final file = await _modelFile(model);
    if (await file.exists()) await file.delete();
  }

  Process? _server;
  String? _servedModel;

  bool get serverRunning => _server != null;

  Future<String> startServer(
    AssistantModel model, {
    void Function(String status)? onProgress,
  }) async {
    const endpoint = 'http://127.0.0.1:$serverPort';
    if (_server != null && _servedModel == model.fileName) {
      if (await _healthy(endpoint)) return endpoint;
    }
    await stopServer();

    final binary = await serverBinaryPath();
    if (binary == null) {
      throw StateError('llama.cpp is not installed; download it in Settings');
    }
    final modelFile = await _modelFile(model);
    if (!await modelFile.exists()) {
      throw StateError('${model.name} is not downloaded');
    }

    onProgress?.call('Loading ${model.name}');
    _server = await Process.start(
      binary,
      [
        '-m',
        modelFile.path,
        '--host',
        '127.0.0.1',
        '--port',
        '$serverPort',
        '-c',
        '8192',

        '--jinja',
        '--reasoning-budget',
        '0',
      ],
      environment: {
        if (Platform.isLinux) 'LD_LIBRARY_PATH': File(binary).parent.path,
      },
    );

    final started = _server!;
    started.stdout.drain<void>();
    started.stderr.drain<void>();
    _servedModel = model.fileName;

    started.exitCode.then((_) {
      if (!identical(_server, started)) return;
      _server = null;
      _servedModel = null;
    });

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (_server == null) {
        throw StateError(
          'llama-server exited during startup; try a smaller model',
        );
      }
      if (await _healthy(endpoint)) return endpoint;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await stopServer();
    throw TimeoutException('llama-server never became healthy');
  }

  Future<bool> _healthy(String endpoint) async {
    try {
      final response = await _client
          .get(Uri.parse('$endpoint/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopServer() async {
    _server?.kill();
    _server = null;
    _servedModel = null;
  }
}
