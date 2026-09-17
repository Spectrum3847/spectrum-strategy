import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/huggingface_catalog_service.dart';
import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';

AssistantModel _model({
  String repoId = 'unsloth/Qwen3-4B-GGUF',
  String path = 'Qwen3-4B-Q4_K_M.gguf',
  int sizeBytes = 2740937888,
}) => AssistantModel(repoId: repoId, path: path, sizeBytes: sizeBytes);

Map<String, dynamic> _listingEntry(
  String id, {
  Object gated = false,
  bool private = false,
}) => {'id': id, 'gated': gated, 'private': private, 'downloads': 1000};

Map<String, dynamic> _treeFile(String path, int size) => {
  'type': 'file',
  'path': path,
  'size': size,
};

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

  test(
    'selected variant defaults to auto, resolved from detected hardware',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-prefs');
      addTearDown(() => root.delete(recursive: true));

      final service = LlamaRuntimeService(
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
      );
      expect(await service.runtimePreference(), LlamaRuntimePreference.auto);
      expect(await service.selectedVariant(), LlamaBuildVariant.cpu);
    },
  );

  test('resolveVariant is a pure function of the probe results', () {
    expect(
      LlamaRuntimeService.resolveVariant(
        os: 'macos',
        arch: 'arm64',
        loaderPresent: true,
        icdPresent: true,
      ),
      LlamaBuildVariant.cpu,
    );

    expect(
      LlamaRuntimeService.resolveVariant(
        os: 'linux',
        arch: 'x64',
        loaderPresent: true,
        icdPresent: true,
      ),
      LlamaBuildVariant.vulkan,
    );

    expect(
      LlamaRuntimeService.resolveVariant(
        os: 'linux',
        arch: 'x64',
        loaderPresent: true,
        icdPresent: false,
      ),
      LlamaBuildVariant.cpu,
    );
    expect(
      LlamaRuntimeService.resolveVariant(
        os: 'linux',
        arch: 'x64',
        loaderPresent: false,
        icdPresent: true,
      ),
      LlamaBuildVariant.cpu,
    );

    expect(
      LlamaRuntimeService.resolveVariant(
        os: 'windows',
        arch: 'arm64',
        loaderPresent: true,
        icdPresent: true,
      ),
      LlamaBuildVariant.cpu,
    );
  });

  test(
    'runtimePreference migrates an explicit legacy Vulkan choice once',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LlamaRuntimeService.variantPrefsKey: LlamaBuildVariant.vulkan.name,
      });
      final root = await Directory.systemTemp.createTemp('llama-migrate');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(root: root);

      expect(
        await service.runtimePreference(),
        LlamaRuntimePreference.forceVulkan,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(LlamaRuntimeService.variantPrefsKey),
        LlamaBuildVariant.vulkan.name,
      );
    },
  );

  test(
    'setRuntimePreference forces cpu or vulkan, bypassing detection',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-force');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(
        root: root,

        autoVariantDetector: () async => LlamaBuildVariant.vulkan,

        os: 'linux',
        arch: 'x64',
      );

      await service.setRuntimePreference(LlamaRuntimePreference.forceCpu);
      expect(await service.selectedVariant(), LlamaBuildVariant.cpu);

      await service.setRuntimePreference(LlamaRuntimePreference.forceVulkan);
      expect(await service.selectedVariant(), LlamaBuildVariant.vulkan);

      await service.setRuntimePreference(LlamaRuntimePreference.auto);
      expect(await service.selectedVariant(), LlamaBuildVariant.vulkan);
    },
  );

  test(
    'switching variant invalidates the stored version so it re-downloads',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-variant');
      addTearDown(() => root.delete(recursive: true));

      final service = LlamaRuntimeService(
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
        os: 'linux',
        arch: 'x64',
      );

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

  test(
    'a forced Vulkan choice falls back where no Vulkan asset exists',
    () async {
      for (final (os, arch) in const [
        ('macos', 'arm64'),
        ('windows', 'arm64'),
      ]) {
        final root = await Directory.systemTemp.createTemp('llama-clamp');
        addTearDown(() => root.delete(recursive: true));
        final service = LlamaRuntimeService(root: root, os: os, arch: arch);

        await service.setRuntimePreference(LlamaRuntimePreference.forceVulkan);

        expect(
          await service.selectedVariant(),
          LlamaBuildVariant.cpu,
          reason: 'no Vulkan asset for $os $arch',
        );
      }
    },
  );

  test('switching variant does not touch installed models', () async {
    final root = await Directory.systemTemp.createTemp('llama-variant-models');
    addTearDown(() => root.delete(recursive: true));
    final service = LlamaRuntimeService(root: root, os: 'linux', arch: 'x64');

    final model = _model();
    final modelsDir = Directory('${root.path}/models');
    await modelsDir.create(recursive: true);
    await File('${modelsDir.path}/${model.fileName}')
        .writeAsString('stub', flush: true);
    await File('${modelsDir.path}/installed_v1.json')
        .writeAsString(jsonEncode({model.id: model.toJson()}));

    await service.setSelectedVariant(LlamaBuildVariant.vulkan);

    final installed = await service.installedModels();
    expect(installed, contains(model));
  });

  test(
    'an unclaimed gguf on disk is adopted so it can be seen and deleted',
    () async {
      final root = await Directory.systemTemp.createTemp('llama-adopt');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(root: root, os: 'linux', arch: 'x64');

      final modelsDir = Directory('${root.path}/models');
      await modelsDir.create(recursive: true);
      await File('${modelsDir.path}/stray-Q4_K_M.gguf')
          .writeAsString('stub', flush: true);

      final installed = await service.installedModels();
      expect(installed, hasLength(1));
      expect(installed.single.isAdopted, isTrue);
      expect(installed.single.path, 'stray-Q4_K_M.gguf');

      await service.deleteModel(installed.single);
      expect(
        await File('${modelsDir.path}/stray-Q4_K_M.gguf').exists(),
        isFalse,
      );
    },
  );

  group('AssistantModel identity', () {
    test('two repos shipping the same file name never collide on disk', () {
      final unsloth = AssistantModel(
        repoId: 'unsloth/Ornith-1.0-9B-GGUF',
        path: 'Ornith-1.0-9B-Q4_K_M.gguf',
        sizeBytes: 5629108704,
      );
      final ornithAi = AssistantModel(
        repoId: 'ornith-ai/Ornith-1.0-9B-GGUF',
        path: 'Ornith-1.0-9B-Q4_K_M.gguf',
        sizeBytes: 5629108704,
      );
      expect(unsloth.fileName, isNot(ornithAi.fileName));
      expect(unsloth.id, isNot(ornithAi.id));
      expect(unsloth, isNot(ornithAi));
    });

    test('sanitizing alone would collide, the digest prefix does not', () {
      final slash = AssistantModel(
        repoId: 'owner/a',
        path: 'b_c.gguf',
        sizeBytes: 1,
      );
      final underscore = AssistantModel(
        repoId: 'owner/a_b',
        path: 'c.gguf',
        sizeBytes: 1,
      );
      expect(
        slash.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
        underscore.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
      );
      expect(slash.fileName, isNot(underscore.fileName));
    });

    test('an adopted model keeps its on-disk file name', () {
      final adopted = AssistantModel(
        repoId: '',
        path: 'some-model-Q4_K_M.gguf',
        sizeBytes: 1,
      );
      expect(adopted.isAdopted, isTrue);
      expect(adopted.fileName, 'some-model-Q4_K_M.gguf');
      expect(adopted.name, 'some-model-Q4_K_M.gguf');
    });

    test('round-trips through toJson/fromJson', () {
      final model = _model();
      final restored = AssistantModel.fromJson(model.toJson());
      expect(restored, model);
      expect(restored.fileName, model.fileName);
    });
  });

  group('AssistantModel.smallForChat', () {
    test('below the threshold is marked (the measured failing case)', () {
      final model = _model(
        repoId: 'LiquidAI/LFM2.5-230M-GGUF',
        path: 'LFM2.5-230M-Q4_K_M.gguf',
      );
      expect(model.parameterCountBillions, closeTo(0.23, 1e-9));
      expect(model.smallForChat, isTrue);
    });

    test('above the threshold is not marked (the measured passing case)', () {
      final model = _model(
        repoId: 'LiquidAI/LFM2.5-2.6B-GGUF',
        path: 'LFM2.5-2.6B-Q4_K_M.gguf',
      );
      expect(model.parameterCountBillions, closeTo(2.6, 1e-9));
      expect(model.smallForChat, isFalse);
    });

    test('exactly at the threshold is not marked', () {
      final model = _model(
        repoId: 'Some/Model-1B-GGUF',
        path: 'Model-1B-Q4_K_M.gguf',
      );
      expect(model.parameterCountBillions, 1.0);
      expect(model.smallForChat, isFalse);
    });

    test('an unparseable name is never marked small', () {
      final model = _model(
        repoId: 'someone/custom-weights-GGUF',
        path: 'custom-weights-Q4_K_M.gguf',
      );
      expect(model.parameterCountBillions, isNull);
      expect(model.smallForChat, isFalse);
    });

    test('an MoE tag is read by total size, not active params', () {
      final model = _model(
        repoId: 'LiquidAI/LFM2.5-8B-A1B-GGUF',
        path: 'LFM2.5-8B-A1B-Q4_K_M.gguf',
      );
      expect(model.parameterCountBillions, 8.0);
      expect(model.smallForChat, isFalse);
    });
  });

  group('sizeBudgetBytes', () {
    const gb = 1024 * 1024 * 1024;

    test('budgets a fraction of the larger of RAM and VRAM', () {
      expect(
        LlamaRuntimeService.sizeBudgetBytes(ramGb: 16, vramGb: null),
        (16 * 0.6 * gb).round(),
      );

      expect(
        LlamaRuntimeService.sizeBudgetBytes(ramGb: 8, vramGb: 24),
        (24 * 0.6 * gb).round(),
      );
    });

    test('falls back to a conservative floor when nothing is known', () {
      expect(
        LlamaRuntimeService.sizeBudgetBytes(ramGb: null, vramGb: null),
        2 * gb,
      );
    });
  });

  group('recommendedModel', () {
    test('picks the largest model that fits the budget', () {
      final small = _model(path: 'a.gguf', sizeBytes: 1 * 1024 * 1024 * 1024);
      final medium = _model(path: 'b.gguf', sizeBytes: 4 * 1024 * 1024 * 1024);
      final large = _model(path: 'c.gguf', sizeBytes: 8 * 1024 * 1024 * 1024);
      final models = [small, medium, large];

      expect(
        LlamaRuntimeService.recommendedModel(models, 5 * 1024 * 1024 * 1024),
        medium,
      );
    });

    test('falls back to the smallest model when none fits', () {
      final small = _model(path: 'a.gguf', sizeBytes: 4 * 1024 * 1024 * 1024);
      final large = _model(path: 'b.gguf', sizeBytes: 8 * 1024 * 1024 * 1024);
      expect(LlamaRuntimeService.recommendedModel([small, large], 1024), small);
    });

    test('is null for an empty list', () {
      expect(LlamaRuntimeService.recommendedModel(const [], 999), isNull);
    });
  });

  group('HuggingFaceCatalogService discovery filters', () {
    for (final marker in blockedModelNameMarkers) {
      test('rejects "$marker" in a repo id regardless of case', () {
        expect(isBlockedModelName('someone/Cool-Model-$marker-GGUF'), isTrue);
        expect(
          isBlockedModelName('someone/Cool-Model-${marker.toUpperCase()}-GGUF'),
          isTrue,
        );
      });
    }

    test(
      'isGatedOrPrivate reads the string forms the API actually returns',
      () {
        expect(isGatedOrPrivate(_listingEntry('a/b')), isFalse);
        expect(isGatedOrPrivate(_listingEntry('a/b', gated: 'auto')), isTrue);
        expect(isGatedOrPrivate(_listingEntry('a/b', gated: 'manual')), isTrue);
        expect(isGatedOrPrivate(_listingEntry('a/b', gated: true)), isTrue);
        expect(isGatedOrPrivate(_listingEntry('a/b', private: true)), isTrue);
        expect(isGatedOrPrivate(<String, dynamic>{'id': 'a/b'}), isFalse);
      },
    );

    test('a repo gated with a string never reaches a tree request', () async {
      var treeRequests = 0;
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('someone/Gated-GGUF', gated: 'manual')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        treeRequests++;
        return http.Response(
          jsonEncode([_treeFile('model-Q4_K_M.gguf', 4000000000)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        await HuggingFaceCatalogService(client: client).discover(),
        isEmpty,
      );
      expect(treeRequests, 0);
    });

    test('a 429 on the listing ends the run as a rate limit, not an empty '
        'list', () async {
      final client = MockClient(
        (request) async => http.Response('{"error":"rate limited"}', 429),
      );

      await expectLater(
        HuggingFaceCatalogService(client: client).discover(),
        throwsA(isA<HuggingFaceRateLimited>()),
      );
    });

    test('a 429 on a tree request stops the run instead of burning the rest '
        'of the budget on requests that can only fail', () async {
      var treeRequests = 0;
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([
              for (var i = 0; i < 60; i++) _listingEntry('owner/Model$i-GGUF'),
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        treeRequests++;
        return http.Response('{"error":"rate limited"}', 429);
      });

      await expectLater(
        HuggingFaceCatalogService(client: client).discover(),
        throwsA(isA<HuggingFaceRateLimited>()),
      );

      expect(treeRequests, lessThanOrEqualTo(6));
    });

    test(
      'stops once enough models resolve rather than scanning every repo',
      () async {
        var treeRequests = 0;
        final client = MockClient((request) async {
          if (!request.url.path.contains('/tree/')) {
            return http.Response(
              jsonEncode([
                for (var i = 0; i < 100; i++)
                  _listingEntry('owner/Model$i-GGUF'),
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          treeRequests++;
          return http.Response(
            jsonEncode([_treeFile('model-Q4_K_M.gguf', 4000000000)]),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final models = await HuggingFaceCatalogService(
          client: client,
          wanted: 12,
          concurrency: 4,
        ).discover();
        expect(models, hasLength(12));
        expect(treeRequests, lessThanOrEqualTo(16));
      },
    );

    test('a team token is sent on every discovery request', () async {
      final seen = <String?>[];
      final client = MockClient((request) async {
        seen.add(request.headers['Authorization']);
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('owner/Model-GGUF')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([_treeFile('model-Q4_K_M.gguf', 4000000000)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await HuggingFaceCatalogService(
        client: client,
        tokenLoader: () async => 'hf_secret',
      ).discover();

      expect(seen, isNotEmpty);
      expect(seen, everyElement('Bearer hf_secret'));
    });

    test(
      'no token means an anonymous run, not an empty Authorization header',
      () async {
        final seen = <Map<String, String>>[];
        final client = MockClient((request) async {
          seen.add(request.headers);
          return http.Response('[]', 200);
        });

        await HuggingFaceCatalogService(
          client: client,
          tokenLoader: () async => '  ',
        ).discover();

        expect(seen, isNotEmpty);
        expect(seen.every((h) => !h.containsKey('Authorization')), isTrue);
      },
    );

    test('an ordinary repo id is not blocked', () {
      expect(isBlockedModelName('unsloth/Qwen3-4B-GGUF'), isFalse);
    });

    test('sharded gguf paths are recognised', () {
      expect(shardedGgufPattern.hasMatch('model-00001-of-00005.gguf'), isTrue);
      expect(shardedGgufPattern.hasMatch('model-Q4_K_M.gguf'), isFalse);
    });

    test('discover drops gated, private and denylisted repos before ever '
        'making a per-repo request', () async {
      var treeRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path.startsWith('/api/models') &&
            !request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([
              _listingEntry('good/Model-GGUF'),
              _listingEntry('bad/Gated-GGUF', gated: true),
              _listingEntry('bad/Private-GGUF', private: true),
              _listingEntry('bad/Model-Uncensored-GGUF'),
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        treeRequests++;
        return http.Response(
          jsonEncode([_treeFile('model-Q4_K_M.gguf', 4000000000)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = HuggingFaceCatalogService(client: client);

      final models = await service.discover();
      expect(treeRequests, 1);
      expect(models, hasLength(1));
      expect(models.single.repoId, 'good/Model-GGUF');
    });

    test('skips a repo whose only gguf files are sharded', () async {
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('someone/Sharded-GGUF')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            _treeFile('model-Q4_K_M-00001-of-00002.gguf', 3000000000),
            _treeFile('model-Q4_K_M-00002-of-00002.gguf', 3000000000),
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = HuggingFaceCatalogService(client: client);

      expect(await service.discover(), isEmpty);
    });

    test('skips a repo with no single-file Q4_K_M rather than guessing at '
        'another quantization', () async {
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('someone/NoQ4-GGUF')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([_treeFile('model-Q8_0.gguf', 6000000000)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = HuggingFaceCatalogService(client: client);

      expect(await service.discover(), isEmpty);
    });

    test('a gated repo missing from the listing flag is still dropped when '
        'its tree request fails', () async {
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('someone/ActuallyGated-GGUF')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Forbidden', 403);
      });
      final service = HuggingFaceCatalogService(client: client);

      expect(await service.discover(), isEmpty);
    });

    test('reads size from lfs.size when size is absent', () async {
      final client = MockClient((request) async {
        if (!request.url.path.contains('/tree/')) {
          return http.Response(
            jsonEncode([_listingEntry('someone/Lfs-GGUF')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {
              'type': 'file',
              'path': 'model-Q4_K_M.gguf',
              'lfs': {'size': 1234567},
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = HuggingFaceCatalogService(client: client);

      final models = await service.discover();
      expect(models.single.sizeBytes, 1234567);
    });
  });

  group('modelCatalog cache', () {
    test('serves the cache without a network call when it is fresh', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-fresh');
      addTearDown(() => root.delete(recursive: true));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('[]', 200);
      });
      final now = DateTime.utc(2026, 1, 2, 12);
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        clock: () => now,
      );
      await File('${root.path}/model_catalog_v1.json').writeAsString(
        jsonEncode({
          'fetchedAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'models': [_model().toJson()],
        }),
      );

      final result = await service.modelCatalog();
      expect(requests, 0);
      expect(result.stale, isFalse);
      expect(result.models, [_model()]);
    });

    test(
      'reports a rate limit as its own state, not as an empty model list',
      () async {
        final root = await Directory.systemTemp.createTemp('llama-catalog-429');
        addTearDown(() => root.delete(recursive: true));
        final service = LlamaRuntimeService(
          root: root,
          catalogService: _RateLimitedCatalogService(),
          ramProbe: () async => 16,
          vramProbe: () async => null,
        );

        final result = await service.modelCatalog();
        expect(result.rateLimited, isTrue);
        expect(result.models, isEmpty);
      },
    );

    test('an ordinary failure is not reported as a rate limit', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-err');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(
        root: root,
        catalogService: _ThrowingCatalogService(),
        ramProbe: () async => 16,
        vramProbe: () async => null,
      );

      expect((await service.modelCatalog()).rateLimited, isFalse);
    });

    test('force re-fetches even when the cache is still fresh', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-force');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 1, 2, 12);
      await File('${root.path}/model_catalog_v1.json').writeAsString(
        jsonEncode({
          'fetchedAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'models': [_model().toJson()],
        }),
      );
      final service = LlamaRuntimeService(
        root: root,
        clock: () => now,
        catalogService: _ThrowingCatalogService(),
        ramProbe: () async => 16,
        vramProbe: () async => null,
      );

      expect((await service.modelCatalog()).stale, isFalse);

      final forced = await service.modelCatalog(force: true);
      expect(forced.stale, isTrue);
      expect(forced.models, [_model()]);
    });

    test('discovery goes through the injected client, so a test never '
        'reaches the live API', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-inj');
      addTearDown(() => root.delete(recursive: true));
      var hits = 0;
      final client = MockClient((request) async {
        hits++;
        expect(request.url.host, 'huggingface.co');
        return http.Response('[]', 200);
      });
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        ramProbe: () async => 16,
        vramProbe: () async => null,
      );

      expect((await service.modelCatalog()).models, isEmpty);
      expect(hits, greaterThan(0));
    });

    test('falls back to the stale cache when the live fetch throws', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-stale');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 1, 2, 12);
      final cachedAt = now.subtract(const Duration(days: 3));
      await File('${root.path}/model_catalog_v1.json').writeAsString(
        jsonEncode({
          'fetchedAt': cachedAt.toIso8601String(),
          'models': [_model().toJson()],
        }),
      );
      final service = LlamaRuntimeService(
        root: root,
        clock: () => now,
        catalogService: _ThrowingCatalogService(),
        ramProbe: () async => null,
        vramProbe: () async => null,
      );

      final result = await service.modelCatalog();
      expect(result.stale, isTrue);
      expect(result.fetchedAt, cachedAt);
      expect(result.models, [_model()]);
    });

    test('refreshes and caches when the cache is older than a day', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-due');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 1, 2, 12);
      final cachedAt = now.subtract(const Duration(days: 3));
      await File('${root.path}/model_catalog_v1.json').writeAsString(
        jsonEncode({
          'fetchedAt': cachedAt.toIso8601String(),
          'models': <dynamic>[],
        }),
      );
      final fresh = _model(path: 'fresh.gguf', sizeBytes: 1024);
      final service = LlamaRuntimeService(
        root: root,
        clock: () => now,
        catalogService: _StaticCatalogService([fresh]),
        ramProbe: () async => null,
        vramProbe: () async => null,
      );

      final result = await service.modelCatalog();
      expect(result.stale, isFalse);
      expect(result.fetchedAt, now);
      expect(result.models, [fresh]);

      final onDisk = jsonDecode(
        await File('${root.path}/model_catalog_v1.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(onDisk['fetchedAt'], now.toIso8601String());
    });

    test('an empty result with no prior cache is not an error', () async {
      final root = await Directory.systemTemp.createTemp('llama-catalog-none');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(
        root: root,
        catalogService: _ThrowingCatalogService(),
        ramProbe: () async => null,
        vramProbe: () async => null,
      );

      final result = await service.modelCatalog();
      expect(result.models, isEmpty);
      expect(result.fetchedAt, isNull);
      expect(result.stale, isTrue);
    });

    test(
      'filters discovered models to the RAM budget before caching',
      () async {
        final root = await Directory.systemTemp.createTemp('llama-catalog-fit');
        addTearDown(() => root.delete(recursive: true));

        final fits = _model(
          path: 'fits.gguf',
          sizeBytes: 4 * 1024 * 1024 * 1024,
        );
        final tooBig = _model(
          path: 'big.gguf',
          sizeBytes: 50 * 1024 * 1024 * 1024,
        );
        final service = LlamaRuntimeService(
          root: root,
          catalogService: _StaticCatalogService([fits, tooBig]),
          ramProbe: () async => 16,
          vramProbe: () async => null,
        );

        final result = await service.modelCatalog();
        expect(result.models, [fits]);
      },
    );
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

    final model = _model();
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

      final first = _model(path: 'first.gguf');
      final second = _model(path: 'second.gguf');
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

  Map<String, dynamic> release(
    String tag, {
    bool draft = false,
    List<String> assetNames = const [],
  }) => {
    'tag_name': tag,
    'draft': draft,
    'assets': [
      for (final name in assetNames)
        {'name': name, 'browser_download_url': 'https://example.com/$name'},
    ],
  };

  test('fetchLatestRelease parses the tag and platform asset URL', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.url.path, '/repos/ggml-org/llama.cpp/releases');
      return http.Response(
        jsonEncode([release('b9957', assetNames: assets)]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = LlamaRuntimeService(client: client);

    final result = await service.fetchLatestRelease();
    expect(result.tag, 'b9957');

    if (result.assetUrl != null) {
      expect(
        result.assetUrl,
        anyOf(
          contains('bin-ubuntu-'),
          contains('bin-macos-'),
          contains('bin-win-cpu-'),
        ),
      );
    }
  });

  test('fetchLatestRelease skips an assetless releases/latest-style entry and '
      'resolves the next real build', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          release('v0.4.0', assetNames: const ['nightly-tag.txt']),
          release(
            'b10819',
            assetNames: const [
              'llama-b10819-bin-macos-arm64.tar.gz',
              'llama-b10819-bin-macos-x64.tar.gz',
              'llama-b10819-bin-ubuntu-vulkan-x64.tar.gz',
              'llama-b10819-bin-ubuntu-vulkan-arm64.tar.gz',
              'llama-b10819-bin-ubuntu-x64.tar.gz',
              'llama-b10819-bin-ubuntu-arm64.tar.gz',
              'llama-b10819-bin-win-cpu-x64.zip',
              'llama-b10819-bin-win-cpu-arm64.zip',
              'llama-b10819-bin-win-vulkan-x64.zip',
              'llama-b10819-xcframework.zip',
            ],
          ),
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = LlamaRuntimeService(client: client);

    final result = await service.fetchLatestRelease();
    expect(result.tag, 'b10819');
    expect(result.assetUrl, isNotNull);
    expect(result.assetUrl, isNot(contains('nightly-tag')));
  });

  test('fetchLatestRelease skips drafts and reports no build when none of the '
      'checked releases has a matching asset', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          release(
            'b10820',
            draft: true,
            assetNames: const ['llama-b10820-bin-ubuntu-x64.tar.gz'],
          ),
          release('b10819', assetNames: const ['cudart-only.zip']),
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = LlamaRuntimeService(client: client);

    final result = await service.fetchLatestRelease();
    expect(result.tag, 'b10819');
    expect(result.assetUrl, isNull);
  });

  group('ensureRuntimeReady', () {
    Future<void> writeStubRuntime(Directory root, String tag) async {
      final runtimeDir = Directory('${root.path}/runtime');
      await runtimeDir.create(recursive: true);
      final name = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
      await File('${runtimeDir.path}/$name').writeAsString('stub');
      await File('${root.path}/VERSION').writeAsString(tag);
    }

    test('checks GitHub when nothing is installed yet', () async {
      final root = await Directory.systemTemp.createTemp('llama-ensure-empty');
      addTearDown(() => root.delete(recursive: true));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode([release('b1', assetNames: assets)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
      );

      await expectLater(service.ensureRuntimeReady(), throwsA(anything));
      expect(requests, greaterThanOrEqualTo(1));
    });

    test('skips a fresh check and reuses the installed binary', () async {
      final root = await Directory.systemTemp.createTemp('llama-ensure-fresh');
      addTearDown(() => root.delete(recursive: true));
      await writeStubRuntime(root, 'b1');
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode([release('b1', assetNames: assets)]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
      );

      await service.ensureRuntimeReady();
      expect(requests, 1);
      final binary = await service.ensureRuntimeReady();
      expect(requests, 1);
      expect(binary, isNotNull);
    });

    test('a failed extraction leaves the working runtime in place', () async {
      final root = await Directory.systemTemp.createTemp('llama-extract-fail');
      addTearDown(() => root.delete(recursive: true));
      await writeStubRuntime(root, 'b1');
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode([release('b2', assetNames: assets)]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('archive bytes', 200);
      });
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
        os: 'linux',
        arch: 'x64',
        extract: (archive, dest) async =>
            throw const FileSystemException('corrupt archive'),
      );

      final binary = await service.ensureRuntimeReady();

      expect(binary, isNotNull, reason: 'the old runtime still answers');
      expect(await File(binary).exists(), isTrue);
      expect(await service.installedTag(), 'b1');
      expect(
        await Directory('${root.path}/runtime-staging').exists(),
        isFalse,
        reason: 'staging is cleaned up on failure',
      );
    });

    test('a legacy forced cpu choice survives the migration', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LlamaRuntimeService.variantPrefsKey: LlamaBuildVariant.cpu.name,
      });
      final root = await Directory.systemTemp.createTemp('llama-legacy-cpu');
      addTearDown(() => root.delete(recursive: true));
      final service = LlamaRuntimeService(
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.vulkan,
        os: 'linux',
        arch: 'x64',
      );

      expect(
        await service.runtimePreference(),
        LlamaRuntimePreference.forceCpu,
      );
      expect(await service.selectedVariant(), LlamaBuildVariant.cpu);
    });

    test('falls back to the installed binary on a network failure', () async {
      final root = await Directory.systemTemp.createTemp('llama-ensure-fail');
      addTearDown(() => root.delete(recursive: true));
      await writeStubRuntime(root, 'b1');
      final client = MockClient((request) async {
        throw const SocketException('offline');
      });
      final service = LlamaRuntimeService(
        client: client,
        root: root,
        autoVariantDetector: () async => LlamaBuildVariant.cpu,
      );

      final binary = await service.ensureRuntimeReady();
      expect(binary, contains('llama-server'));
    });

    test(
      'skips the check rather than colliding with a running download',
      () async {
        final root = await Directory.systemTemp.createTemp('llama-ensure-busy');
        addTearDown(() => root.delete(recursive: true));
        await writeStubRuntime(root, 'b1');
        final gate = Completer<void>();
        final client = MockClient.streaming((request, bodyStream) async {
          Stream<List<int>> chunks() async* {
            await gate.future;
            yield List<int>.filled(16, 1);
          }

          return http.StreamedResponse(chunks(), 200);
        });
        final service = LlamaRuntimeService(
          client: client,
          root: root,
          autoVariantDetector: () async => LlamaBuildVariant.cpu,
        );

        final busyDownload = service.downloadModel(_model());
        while (service.busyKey == null) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        final binary = await service.ensureRuntimeReady();
        expect(binary, contains('llama-server'));

        gate.complete();
        await busyDownload;
      },
    );
  });
}

class _ThrowingCatalogService implements HuggingFaceCatalogService {
  @override
  Future<List<AssistantModel>> discover() async =>
      throw http.ClientException('offline');
}

class _RateLimitedCatalogService implements HuggingFaceCatalogService {
  @override
  Future<List<AssistantModel>> discover() async =>
      throw const HuggingFaceRateLimited();
}

class _StaticCatalogService implements HuggingFaceCatalogService {
  _StaticCatalogService(this._models);

  final List<AssistantModel> _models;

  @override
  Future<List<AssistantModel>> discover() async => _models;
}
