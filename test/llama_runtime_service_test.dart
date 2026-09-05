import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';

void main() {
  const assets = [
    'llama-b9957-bin-macos-arm64.tar.gz',
    'llama-b9957-bin-ubuntu-arm64.tar.gz',
    'llama-b9957-bin-ubuntu-vulkan-arm64.tar.gz',
    'llama-b9957-bin-ubuntu-vulkan-x64.tar.gz',
    'llama-b9957-bin-ubuntu-x64.tar.gz',
    'llama-b9957-bin-win-cpu-x64.zip',
    'llama-b9957-bin-win-cuda-12.4-x64.zip',
    'llama-b9957-bin-win-vulkan-x64.zip',
    'cudart-llama-bin-win-cuda-12.4-x64.zip',
  ];

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('assetNameFor picks the CPU build for each platform', () {
    expect(
      LlamaRuntimeService.assetNameFor(assets, os: 'linux', arch: 'x64'),
      'llama-b9957-bin-ubuntu-x64.tar.gz',
    );
    expect(
      LlamaRuntimeService.assetNameFor(assets, os: 'macos', arch: 'arm64'),
      'llama-b9957-bin-macos-arm64.tar.gz',
    );
    expect(
      LlamaRuntimeService.assetNameFor(assets, os: 'windows', arch: 'x64'),
      'llama-b9957-bin-win-cpu-x64.zip',
    );
    expect(
      LlamaRuntimeService.assetNameFor(assets, os: 'android', arch: 'x64'),
      isNull,
    );
  });

  test('assetNameFor picks the Vulkan build where one exists', () {
    expect(
      LlamaRuntimeService.assetNameFor(
        assets,
        os: 'linux',
        arch: 'x64',
        variant: LlamaBuildVariant.vulkan,
      ),
      'llama-b9957-bin-ubuntu-vulkan-x64.tar.gz',
    );
    expect(
      LlamaRuntimeService.assetNameFor(
        assets,
        os: 'linux',
        arch: 'arm64',
        variant: LlamaBuildVariant.vulkan,
      ),
      'llama-b9957-bin-ubuntu-vulkan-arm64.tar.gz',
    );
    expect(
      LlamaRuntimeService.assetNameFor(
        assets,
        os: 'windows',
        arch: 'x64',
        variant: LlamaBuildVariant.vulkan,
      ),
      'llama-b9957-bin-win-vulkan-x64.zip',
    );
  });

  test('no Vulkan build for macOS or Windows arm64', () {
    for (final arch in ['x64', 'arm64']) {
      expect(
        LlamaRuntimeService.assetNameFor(
          assets,
          os: 'macos',
          arch: arch,
          variant: LlamaBuildVariant.vulkan,
        ),
        isNull,
      );
    }
    expect(
      LlamaRuntimeService.assetNameFor(
        assets,
        os: 'windows',
        arch: 'arm64',
        variant: LlamaBuildVariant.vulkan,
      ),
      isNull,
    );
  });

  test('vulkanAvailable covers the platform matrix', () {
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'linux', arch: 'x64'),
      isTrue,
    );
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'linux', arch: 'arm64'),
      isTrue,
    );
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'windows', arch: 'x64'),
      isTrue,
    );
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'windows', arch: 'arm64'),
      isFalse,
    );
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'macos', arch: 'x64'),
      isFalse,
    );
    expect(
      LlamaRuntimeService.vulkanAvailable(os: 'macos', arch: 'arm64'),
      isFalse,
    );
  });

  test('selected variant defaults to cpu when nothing is stored', () async {
    final root = await Directory.systemTemp.createTemp('llama-prefs');
    addTearDown(() => root.delete(recursive: true));
    final service = LlamaRuntimeService(root: root);
    expect(await service.selectedVariant(), LlamaBuildVariant.cpu);
  });

  test(
    'switching variant invalidates the stored version so it re-downloads',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-variant');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(root: root);

      final runtimeDir = Directory('${root.path}/runtime');
      await runtimeDir.create(recursive: true);
      final name = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
      await File('${runtimeDir.path}/$name').writeAsString('stub');
      await File('${root.path}/VERSION').writeAsString('b9957');

      expect(await service.installedTag(), 'b9957');
      expect(await service.serverBinaryPath(), isNotNull);

      await service.setSelectedVariant(LlamaBuildVariant.vulkan);
      expect(await service.selectedVariant(), LlamaBuildVariant.vulkan);
      expect(await service.installedTag(), isNull);
      expect(await service.serverBinaryPath(), isNull);

      expect(await runtimeDir.exists(), isFalse);
      expect(await File('${root.path}/VERSION').exists(), isFalse);

      await service.setSelectedVariant(LlamaBuildVariant.cpu);
      expect(await service.installedTag(), isNull);
      expect(await service.serverBinaryPath(), isNull);
    },
  );

  test('switching variant does not touch installed models', () async {
    final root = await Directory.systemTemp.createTemp('llama-variant-models');
    addTearDown(() => root.delete(recursive: true));
    final service = LlamaRuntimeService(root: root);

    final model = LlamaRuntimeService.catalog.first;
    final modelsDir = Directory('${root.path}/models');
    await modelsDir.create(recursive: true);
    await File('${modelsDir.path}/${model.fileName}')
        .writeAsString('stub', flush: true);

    await service.setSelectedVariant(LlamaBuildVariant.vulkan);

    final installed = await service.installedModels();
    expect(installed, contains(model));
  });

  test('recommendedModel scales with RAM and defaults small', () {
    final smallest = LlamaRuntimeService.catalog.reduce(
      (a, b) => b.sizeBytes < a.sizeBytes ? b : a,
    );
    expect(LlamaRuntimeService.recommendedModel(null), smallest);
    expect(LlamaRuntimeService.recommendedModel(2), smallest);

    for (final ram in [4, 8, 16, 32]) {
      final pick = LlamaRuntimeService.recommendedModel(ram);
      expect(pick.minRamGb, lessThanOrEqualTo(ram));
      for (final other in LlamaRuntimeService.catalog) {
        if (other.minRamGb <= ram) {
          expect(pick.sizeBytes, greaterThanOrEqualTo(other.sizeBytes));
        }
      }
    }
  });

  test('catalog entries are unique and families group them', () {
    final names = LlamaRuntimeService.catalog.map((m) => m.fileName).toSet();
    expect(names.length, LlamaRuntimeService.catalog.length);
    final families = LlamaRuntimeService.families;
    expect(families.toSet().length, families.length);
    for (final model in LlamaRuntimeService.catalog) {
      expect(families, contains(model.family));
    }
  });

  test('cancelDownload aborts mid-stream and leaves no file', () async {
    final root = await Directory.systemTemp.createTemp('llama-cancel');
    addTearDown(() => root.delete(recursive: true));
    late LlamaRuntimeService service;
    final client = MockClient.streaming((request, bodyStream) async {
      Stream<List<int>> chunks() async* {
        yield List<int>.filled(1024, 1);
        service.cancelDownload();
        yield List<int>.filled(1024, 2);
        yield List<int>.filled(1024, 3);
      }

      return http.StreamedResponse(chunks(), 200, contentLength: 3072);
    });
    service = LlamaRuntimeService(client: client, root: root);

    final model = LlamaRuntimeService.catalog.first;
    await expectLater(
      service.downloadModel(model),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await service.isModelInstalled(model), isFalse);

    final leftovers = root.listSync(recursive: true).whereType<File>().toList();
    expect(leftovers, isEmpty);
  });

  test(
    'a second download while one runs is refused, not interleaved',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-serial');
      addTearDown(() => root.delete(recursive: true));
      final gate = Completer<void>();
      final client = MockClient.streaming((request, bodyStream) async {
        Stream<List<int>> chunks() async* {
          yield List<int>.filled(64, 1);
          await gate.future;
          yield List<int>.filled(64, 2);
        }

        return http.StreamedResponse(chunks(), 200);
      });
      final service = LlamaRuntimeService(client: client, root: root);

      final first = LlamaRuntimeService.catalog.first;
      final second = LlamaRuntimeService.catalog[1];
      final firstDownload = service.downloadModel(first);
      while (service.busyKey == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.busyKey, first.fileName);

      await expectLater(service.downloadModel(second), throwsStateError);
      expect(service.busyKey, first.fileName);

      gate.complete();
      await firstDownload;
      expect(service.busyKey, isNull);
      expect(await service.isModelInstalled(first), isTrue);
    },
  );

  test('fetchLatestRelease parses the tag and platform asset URL', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      return http.Response(
        jsonEncode({
          'tag_name': 'b9957',
          'assets': [
            for (final name in assets)
              {
                'name': name,
                'browser_download_url': 'https://example.com/$name',
              },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = LlamaRuntimeService(client: client);

    final release = await service.fetchLatestRelease();
    expect(release.tag, 'b9957');

    if (release.assetUrl != null) {
      expect(
        release.assetUrl,
        anyOf(
          contains('bin-ubuntu-'),
          contains('bin-macos-'),
          contains('bin-win-cpu-'),
        ),
      );
    }
  });
}
