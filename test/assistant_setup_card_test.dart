import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';
import 'package:spectrumstrategy/src/ui/model_chat_suitability.dart';

void main() {
  AssistantModel model(String repo, String file) =>
      AssistantModel(repoId: repo, path: file, sizeBytes: 1);

  group('which models get marked', () {
    test('a sub-billion model is marked', () {
      final small = model(
        'LiquidAI/LFM2.5-230M-GGUF',
        'LFM2.5-230M-Q4_K_M.gguf',
      );
      expect(small.parameterCountBillions, closeTo(0.23, 0.001));
      expect(small.smallForChat, isTrue);
    });

    test('a multi-billion model is not', () {
      final big = model('LiquidAI/LFM2.5-2.6B-GGUF', 'LFM2.5-2.6B-Q4_K_M.gguf');
      expect(big.parameterCountBillions, 2.6);
      expect(big.smallForChat, isFalse);
    });

    test('exactly at the threshold is not marked', () {
      final borderline = model(
        'meta/Llama-3.2-1B-GGUF',
        'Llama-3.2-1B-Q4_K_M.gguf',
      );
      expect(borderline.parameterCountBillions, 1);
      expect(
        borderline.parameterCountBillions,
        AssistantModel.chatCapableThresholdBillions,
      );
      expect(borderline.smallForChat, isFalse);
    });

    test('an id with no readable count is left alone, not called small', () {
      final unknown = model('someone/mystery-GGUF', 'mystery-Q4_K_M.gguf');
      expect(unknown.parameterCountBillions, isNull);
      expect(unknown.smallForChat, isFalse);
    });

    test('a quantization suffix is not read as a parameter count', () {
      final big = model('unsloth/Qwen3-4B-GGUF', 'Qwen3-4B-Q4_K_M.gguf');
      expect(big.parameterCountBillions, 4);
      expect(big.smallForChat, isFalse);
    });

    test('an MoE name is read by its total, not its active, parameters', () {
      final moe = model(
        'LiquidAI/LFM2.5-8B-A1B-GGUF',
        'LFM2.5-8B-A1B-Q4_K_M.gguf',
      );
      expect(moe.parameterCountBillions, 8);
      expect(moe.smallForChat, isFalse);
    });
  });

  group('what the marking says', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

    testWidgets('the chip names the case the model is good for', (
      tester,
    ) async {
      await pump(tester, const ModelChatSuitabilityChip());
      expect(find.text('Best for summaries'), findsOneWidget);
    });

    testWidgets('the note says what goes wrong, without calling the model '
        'broken', (tester) async {
      await pump(tester, const ModelChatSuitabilityNote());
      expect(find.textContaining('Reliable for a single'), findsOneWidget);
      expect(find.textContaining('lose the thread in a chat'), findsOneWidget);
    });
  });
}
