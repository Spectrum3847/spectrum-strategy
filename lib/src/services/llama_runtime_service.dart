import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'huggingface_catalog_service.dart';
import 'model_catalog_cache.dart';

class AssistantModel {
  AssistantModel({
    required this.repoId,
    required this.path,
    required this.sizeBytes,
  });

  final String repoId;

  final String path;
  final int sizeBytes;

  String get id => '$repoId/$path';

  String get fileName {
    if (isAdopted) return path;
    final readable = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final digest = sha256.convert(utf8.encode(id)).toString().substring(0, 8);
    return '$digest-$readable';
  }

  bool get isAdopted => repoId.isEmpty;

  String get name => isAdopted
      ? path
      : repoId
            .split('/')
            .last
            .replaceAll(RegExp(r'-GGUF$', caseSensitive: false), '');

  String get owner => isAdopted ? 'On this machine' : repoId.split('/').first;

  String get downloadUrl => 'https://huggingface.co/$repoId/resolve/main/$path';

  double get sizeGb => sizeBytes / (1024 * 1024 * 1024);

  static final RegExp _paramCountPattern = RegExp(
    r'(?<![A-Za-z])(\d+(?:\.\d+)?)(B|M)(?![A-Za-z])',
    caseSensitive: false,
  );

  double? get parameterCountBillions {
    double? best;
    for (final match in _paramCountPattern.allMatches(id)) {
      final value = double.parse(match.group(1)!);
      final billions = match.group(2)!.toUpperCase() == 'M'
          ? value / 1000
          : value;
      if (best == null || billions > best) best = billions;
    }
    return best;
  }

  static const double chatCapableThresholdBillions = 1;

  bool get smallForChat {
    final billions = parameterCountBillions;
    return billions != null && billions < chatCapableThresholdBillions;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'repoId': repoId,
    'path': path,
    'sizeBytes': sizeBytes,
  };

  static AssistantModel fromJson(Map<String, dynamic> json) => AssistantModel(
    repoId: json['repoId'] as String,
    path: json['path'] as String,
    sizeBytes: json['sizeBytes'] as int,
  );

  @override
  bool operator ==(Object other) => other is AssistantModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class ModelCatalogResult {
  const ModelCatalogResult({
    required this.models,
    required this.fetchedAt,
    required this.stale,
    this.rateLimited = false,
  });

  final List<AssistantModel> models;
  final DateTime? fetchedAt;
  final bool stale;

  final bool rateLimited;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

enum LlamaBuildVariant { cpu, vulkan }

enum LlamaRuntimePreference { auto, forceCpu, forceVulkan }

class LlamaRuntimeService extends ChangeNotifier {
  LlamaRuntimeService({
    http.Client? client,
    Directory? root,
    Future<SharedPreferences> Function()? prefs,
    Future<LlamaBuildVariant> Function()? autoVariantDetector,
    String? os,
    String? arch,
    Future<void> Function(File archive, Directory dest)? extract,
    HuggingFaceCatalogService? catalogService,
    DateTime Function()? clock,
    Future<int?> Function()? ramProbe,
    Future<int?> Function()? vramProbe,
  }) : _extractOverride = extract,
       _client = client ?? http.Client(),
       _rootOverride = root,
       _prefsLoader = prefs ?? SharedPreferences.getInstance,
       _autoVariantDetectorOverride = autoVariantDetector,
       _os = os ?? Platform.operatingSystem,
       _arch = arch ?? _currentArch,
       _catalogServiceOverride = catalogService,
       _clock = clock ?? DateTime.now,
       _ramProbeOverride = ramProbe,
       _vramProbeOverride = vramProbe;

  static final LlamaRuntimeService shared = LlamaRuntimeService();

  final http.Client _client;
  final Directory? _rootOverride;
  final Future<SharedPreferences> Function() _prefsLoader;

  final Future<LlamaBuildVariant> Function()? _autoVariantDetectorOverride;

  final Future<void> Function(File archive, Directory dest)? _extractOverride;

  final String _os;
  final String _arch;
  LlamaBuildVariant? _autoVariantCache;

  final HuggingFaceCatalogService? _catalogServiceOverride;

  final DateTime Function() _clock;

  final Future<int?> Function()? _ramProbeOverride;
  final Future<int?> Function()? _vramProbeOverride;

  Future<String?> Function()? huggingFaceTokenLoader;

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

  static const String _releasesListUrl =
      'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10';

  static const int _gigabyte = 1024 * 1024 * 1024;

  static const Duration catalogRefreshThreshold = Duration(days: 1);

  static int sizeBudgetBytes({required int? ramGb, required int? vramGb}) {
    final ram = ramGb ?? 0;
    final vram = vramGb ?? 0;
    final gb = ram > vram ? ram : vram;
    if (gb <= 0) return 2 * _gigabyte;
    return (gb * 0.6 * _gigabyte).round();
  }

  Future<ModelCatalogResult> modelCatalog({bool force = false}) async {
    final cacheFile = await _catalogCacheFile();
    final cache = ModelCatalogCache(cacheFile);
    final cached = await cache.load();
    final now = _clock();
    if (cached != null && !force) {
      final age = now.difference(cached.fetchedAt);
      if (age < catalogRefreshThreshold) {
        return ModelCatalogResult(
          models: cached.models,
          fetchedAt: cached.fetchedAt,
          stale: false,
        );
      }
    }
    try {
      final budget = sizeBudgetBytes(
        ramGb: await totalRamGb(),
        vramGb: await totalVramGb(),
      );
      final catalogService =
          _catalogServiceOverride ?? HuggingFaceCatalogService(client: _client);
      final discovered = await catalogService.discover();
      final fitted = discovered.where((m) => m.sizeBytes <= budget).toList()
        ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      await cache.save(fitted, now);
      return ModelCatalogResult(models: fitted, fetchedAt: now, stale: false);
    } catch (error) {
      final rateLimited = error is HuggingFaceRateLimited;
      if (cached != null) {
        return ModelCatalogResult(
          models: cached.models,
          fetchedAt: cached.fetchedAt,
          stale: true,
          rateLimited: rateLimited,
        );
      }
      return ModelCatalogResult(
        models: const [],
        fetchedAt: null,
        stale: true,
        rateLimited: rateLimited,
      );
    }
  }

  static AssistantModel? recommendedModel(
    List<AssistantModel> models,
    int budgetBytes,
  ) {
    AssistantModel? best;
    for (final model in models) {
      if (model.sizeBytes <= budgetBytes &&
          (best == null || model.sizeBytes > best.sizeBytes)) {
        best = model;
      }
    }
    if (best != null) return best;
    if (models.isEmpty) return null;
    return models.reduce((a, b) => a.sizeBytes < b.sizeBytes ? a : b);
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

  static bool get isMacOS => Platform.isMacOS;

  static const String variantPrefsKey = 'llama_runtime_variant_v1';

  static const String preferencePrefsKey = 'llama_runtime_preference_v1';

  Future<LlamaRuntimePreference> runtimePreference() async {
    final prefs = await _prefsLoader();
    final stored = prefs.getString(preferencePrefsKey);
    for (final preference in LlamaRuntimePreference.values) {
      if (preference.name == stored) return preference;
    }

    final legacy = prefs.getString(variantPrefsKey);
    for (final variant in LlamaBuildVariant.values) {
      if (legacy != variant.name) continue;
      final migrated = variant == LlamaBuildVariant.vulkan
          ? LlamaRuntimePreference.forceVulkan
          : LlamaRuntimePreference.forceCpu;
      await prefs.setString(preferencePrefsKey, migrated.name);
      return migrated;
    }
    return LlamaRuntimePreference.auto;
  }

  Future<void> setRuntimePreference(LlamaRuntimePreference preference) async {
    final previous = await selectedVariant();
    final prefs = await _prefsLoader();
    await prefs.setString(preferencePrefsKey, preference.name);
    final next = await selectedVariant();
    if (previous == next) return;
    final oldDir = await _runtimeDirFor(previous);
    if (await oldDir.exists()) {
      await oldDir.delete(recursive: true);
    }
    final oldVersionFile = await _versionFileFor(previous);
    if (await oldVersionFile.exists()) {
      await oldVersionFile.delete();
    }
  }

  Future<void> setSelectedVariant(LlamaBuildVariant variant) =>
      setRuntimePreference(
        variant == LlamaBuildVariant.cpu
            ? LlamaRuntimePreference.forceCpu
            : LlamaRuntimePreference.forceVulkan,
      );

  Future<LlamaBuildVariant> selectedVariant() async {
    final preference = await runtimePreference();
    final variant = switch (preference) {
      LlamaRuntimePreference.forceCpu => LlamaBuildVariant.cpu,
      LlamaRuntimePreference.forceVulkan => LlamaBuildVariant.vulkan,
      LlamaRuntimePreference.auto => await _detectAutoVariant(),
    };
    if (variant == LlamaBuildVariant.vulkan &&
        !vulkanAvailable(os: _os, arch: _arch)) {
      return LlamaBuildVariant.cpu;
    }
    return variant;
  }

  static LlamaBuildVariant resolveVariant({
    required String os,
    required String arch,
    required bool loaderPresent,
    required bool icdPresent,
  }) {
    if (os == 'macos') return LlamaBuildVariant.cpu;
    if (!vulkanAvailable(os: os, arch: arch)) return LlamaBuildVariant.cpu;
    return loaderPresent && icdPresent
        ? LlamaBuildVariant.vulkan
        : LlamaBuildVariant.cpu;
  }

  Future<LlamaBuildVariant> _detectAutoVariant() async {
    final cached = _autoVariantCache;
    if (cached != null) return cached;
    final variant = _autoVariantDetectorOverride != null
        ? await _autoVariantDetectorOverride()
        : await _probeAutoVariant();
    _autoVariantCache = variant;
    return variant;
  }

  Future<LlamaBuildVariant> _probeAutoVariant() async {
    final os = _os;
    final arch = _arch;
    var loaderPresent = false;
    var icdPresent = false;

    try {
      if (os == 'linux') {
        final ldconfig = await Process.run('ldconfig', [
          '-p',
        ]).timeout(const Duration(seconds: 2));
        loaderPresent = (ldconfig.stdout as String).contains('libvulkan.so.1');

        icdPresent = await _hasIcdFiles(const [
          '/usr/share/vulkan/icd.d',
          '/etc/vulkan/icd.d',
        ]);
      } else if (os == 'windows') {
        final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        loaderPresent = await File('$systemRoot\\System32\\vulkan-1.dll')
            .exists()
            .timeout(const Duration(seconds: 2));
        icdPresent = loaderPresent;
      }
    } catch (_) {
      loaderPresent = false;
      icdPresent = false;
    }
    return resolveVariant(
      os: os,
      arch: arch,
      loaderPresent: loaderPresent,
      icdPresent: icdPresent,
    );
  }

  Future<bool> _hasIcdFiles(List<String> candidateDirs) async {
    for (final path in candidateDirs) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      final entries = await dir.list().toList().timeout(
        const Duration(seconds: 2),
      );
      for (final entry in entries) {
        if (entry is File && entry.path.endsWith('.json')) return true;
      }
    }
    return false;
  }

  static String get _currentArch =>
      Platform.version.contains('arm64') ? 'arm64' : 'x64';

  Future<int?> totalRamGb() async {
    if (_ramProbeOverride != null) return _ramProbeOverride();
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

  Future<int?> totalVramGb() async {
    if (_vramProbeOverride != null) return _vramProbeOverride();
    if (!Platform.isLinux && !Platform.isWindows) return null;
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=memory.total',
        '--format=csv,noheader,nounits',
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final firstLine = (result.stdout as String)
          .trim()
          .split('\n')
          .first
          .trim();
      final mib = int.tryParse(firstLine);
      if (mib == null) return null;
      return (mib / 1024).round();
    } catch (_) {
      return null;
    }
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

  Future<File> _catalogCacheFile() async => File(
    '${(await _root()).path}${Platform.pathSeparator}model_catalog_v1.json',
  );

  Future<File> _installedManifestFile() async => File(
    '${(await _modelsDir()).path}${Platform.pathSeparator}installed_v1.json',
  );

  Future<Map<String, AssistantModel>> _readManifest() async {
    final file = await _installedManifestFile();
    if (!await file.exists()) return <String, AssistantModel>{};
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          entry.key: AssistantModel.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } catch (_) {
      return <String, AssistantModel>{};
    }
  }

  Future<void> _writeManifest(Map<String, AssistantModel> manifest) async {
    final file = await _installedManifestFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        for (final entry in manifest.entries) entry.key: entry.value.toJson(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
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

  Future<String?> serverBinaryPath() async =>
      _serverBinaryIn(await _runtimeDir());

  static Future<String?> _serverBinaryIn(Directory dir) async {
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
        .get(Uri.parse(_releasesListUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GitHub answered HTTP ${response.statusCode} for the llama.cpp '
        'release list',
      );
    }
    final releases = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
    if (releases.isEmpty) {
      throw http.ClientException('GitHub returned no llama.cpp releases');
    }
    for (final release in releases) {
      if (release['draft'] == true) continue;
      final assets = (release['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final assetName = assetNameFor(
        assets.map((a) => a['name'] as String),
        os: _os,
        arch: _arch,
        variant: variant,
      );
      if (assetName == null) continue;
      final assetUrl =
          assets.firstWhere(
                (a) => a['name'] == assetName,
              )['browser_download_url']
              as String;
      return (tag: release['tag_name'] as String, assetUrl: assetUrl);
    }
    final newest = releases.firstWhere(
      (r) => r['draft'] != true,
      orElse: () => releases.first,
    );
    return (tag: newest['tag_name'] as String, assetUrl: null);
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
      await _markCheckSucceeded();
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
      throw UnsupportedError('llama.cpp has no build for $_os ($_arch)');
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

    final staging = Directory('${runtime.path}-staging');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await _extract(archive, staging);
      if (await _serverBinaryIn(staging) == null) {
        throw StateError('llama-server missing from the extracted runtime');
      }
      if (await runtime.exists()) await runtime.delete(recursive: true);
      await staging.rename(runtime.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    } finally {
      if (await archive.exists()) await archive.delete();
    }
    await (await _versionFile()).writeAsString(latest.tag);

    final binary = await serverBinaryPath();
    if (binary == null) {
      throw StateError('llama-server missing from the extracted runtime');
    }
    return binary;
  });

  static const String _lastCheckPrefsKey = 'llama_runtime_last_check_v1';

  static const Duration _checkThrottle = Duration(hours: 24);

  Future<bool> _checkDue() async {
    final prefs = await _prefsLoader();
    final lastMs = prefs.getInt(_lastCheckPrefsKey);
    if (lastMs == null) return true;
    final since = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastMs),
    );

    return since.isNegative || since > _checkThrottle;
  }

  Future<void> _markCheckSucceeded() async {
    final prefs = await _prefsLoader();
    await prefs.setInt(
      _lastCheckPrefsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String> ensureRuntimeReady() async {
    final installed = await serverBinaryPath();
    if (installed != null && !await _checkDue()) return installed;
    try {
      return await ensureLatestRuntime();
    } catch (_) {
      final current = await serverBinaryPath();
      if (current != null) return current;
      rethrow;
    }
  }

  Future<void> _extract(File archive, Directory dest) async {
    final override = _extractOverride;
    if (override != null) return override(archive, dest);

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
    final manifest = await _readManifest();
    final installed = <AssistantModel>[];
    final claimed = <String>{};
    for (final model in manifest.values) {
      if (await (await _modelFile(model)).exists()) {
        installed.add(model);
        claimed.add(model.fileName);
      }
    }
    installed.addAll(await _adoptedModels(claimed));
    return installed;
  }

  Future<List<AssistantModel>> _adoptedModels(Set<String> claimed) async {
    final dir = await _modelsDir();
    final adopted = <AssistantModel>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.toLowerCase().endsWith('.gguf')) continue;
      if (claimed.contains(name)) continue;
      adopted.add(
        AssistantModel(
          repoId: '',
          path: name,
          sizeBytes: await entity.length(),
        ),
      );
    }
    return adopted;
  }

  Future<void> downloadModel(
    AssistantModel model, {
    void Function(int received, int? total)? onProgress,
  }) => _withBusy(model.fileName, () async {
    await _download(Uri.parse(model.downloadUrl), await _modelFile(model), (
      received,
      total,
    ) {
      _setBusyStatus('Downloading', total == null ? null : received / total);
      onProgress?.call(received, total);
    });
    final manifest = await _readManifest();
    manifest[model.id] = model;
    await _writeManifest(manifest);
  });

  Future<void> deleteModel(AssistantModel model) async {
    final file = await _modelFile(model);
    if (await file.exists()) await file.delete();
    final manifest = await _readManifest();
    manifest.remove(model.id);
    await _writeManifest(manifest);

    notifyListeners();
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

    String binary;
    try {
      binary = await ensureRuntimeReady();
    } catch (_) {
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
