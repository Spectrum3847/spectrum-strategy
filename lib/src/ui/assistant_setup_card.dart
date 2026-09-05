import 'package:flutter/material.dart';

import '../services/llama_runtime_service.dart';
import '../theme/strategy_palette.dart';

class AssistantSetupCard extends StatefulWidget {
  const AssistantSetupCard({this.runtime, super.key});

  final LlamaRuntimeService? runtime;

  @override
  State<AssistantSetupCard> createState() => _AssistantSetupCardState();
}

class _AssistantSetupCardState extends State<AssistantSetupCard> {
  late final LlamaRuntimeService _runtime =
      widget.runtime ?? LlamaRuntimeService.shared;

  String? _installedTag;
  int? _ramGb;
  final Set<String> _installedModels = <String>{};
  LlamaBuildVariant _variant = LlamaBuildVariant.cpu;

  bool _loaded = false;

  String? _error;
  String? _lastBusyKey;

  @override
  void initState() {
    super.initState();
    _lastBusyKey = _runtime.busyKey;
    _runtime.addListener(_onRuntimeChanged);
    _refresh();
  }

  @override
  void dispose() {
    _runtime.removeListener(_onRuntimeChanged);
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;

    if (_lastBusyKey != null && _runtime.busyKey == null) _refresh();
    _lastBusyKey = _runtime.busyKey;
    setState(() {});
  }

  Future<void> _refresh() async {
    final tag = await _runtime.installedTag();
    final ram = await _runtime.totalRamGb();
    final models = await _runtime.installedModels();
    final variant = await _runtime.selectedVariant();
    if (!mounted) return;
    setState(() {
      _installedTag = tag;
      _ramGb = ram;
      _variant = variant;
      _installedModels
        ..clear()
        ..addAll(models.map((m) => m.fileName));
      _loaded = true;
    });
  }

  Future<void> _selectVariant(LlamaBuildVariant variant) async {
    if (variant == _variant) return;
    await _runtime.setSelectedVariant(variant);
    if (!mounted) return;
    setState(() => _variant = variant);
    if (_installedTag == null) return;

    await _guarded(() => _runtime.ensureLatestRuntime());
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_runtime.busyKey != null) return;
    setState(() => _error = null);
    try {
      await action();
    } on DownloadCancelled {
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    if (mounted) await _refresh();
  }

  Widget _progressLine(ThemeData theme) {
    final progress = _runtime.busyProgress;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 4),
          Text(
            progress == null
                ? _runtime.busyStatus
                : '${_runtime.busyStatus} '
                      '(${(progress * 100).toStringAsFixed(0)}%)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _modelRow(
    ThemeData theme,
    AssistantModel model,
    AssistantModel recommended,
  ) {
    final installed = _installedModels.contains(model.fileName);
    final downloading = _runtime.busyKey == model.fileName;
    final idle = _runtime.busyKey == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${model.name} '
                            '(${model.sizeGb.toStringAsFixed(1)} GB)',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (identical(model, recommended)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(
                                StrategyPalette.radiusSm,
                              ),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${model.description} '
                      'Needs about ${model.minRamGb} GB of memory.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (downloading)
                OutlinedButton(
                  onPressed: _runtime.cancelDownload,
                  child: const Text('Cancel'),
                )
              else if (installed)
                OutlinedButton(
                  onPressed: idle
                      ? () => _guarded(() => _runtime.deleteModel(model))
                      : null,
                  child: const Text('Delete'),
                )
              else
                OutlinedButton(
                  onPressed: idle
                      ? () => _guarded(() => _runtime.downloadModel(model))
                      : null,
                  child: const Text('Download'),
                ),
            ],
          ),
          if (downloading) _progressLine(theme),
        ],
      ),
    );
  }

  Widget _familySection(
    ThemeData theme,
    String family,
    AssistantModel recommended,
  ) {
    final models = LlamaRuntimeService.catalog
        .where((m) => m.family == family)
        .toList();
    final installedCount = models
        .where((m) => _installedModels.contains(m.fileName))
        .length;
    final active = models.any(
      (m) =>
          _runtime.busyKey == m.fileName ||
          _installedModels.contains(m.fileName),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
    );
    return ExpansionTile(
      key: PageStorageKey<String>('assistant-family-$family'),
      shape: shape,
      collapsedShape: shape,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      initiallyExpanded: active || models.contains(recommended),
      title: Text(family, style: theme.textTheme.titleSmall),
      subtitle: Text(
        '${models.length} ${models.length == 1 ? 'model' : 'models'}'
        '${installedCount > 0 ? ', $installedCount installed' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final model in models) _modelRow(theme, model, recommended),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommended = LlamaRuntimeService.recommendedModel(_ramGb);
    final runtimeBusy = _runtime.busyKey == LlamaRuntimeService.runtimeBusyKey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The assistant answers strategy questions using a model that '
              'runs entirely on this computer. It needs two optional '
              'downloads: the llama.cpp runtime (small, updated on each '
              'use) and at least one model.'
              '${_ramGb != null ? ' This computer has about $_ramGb GB of '
                        'memory.' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _installedTag == null
                        ? 'llama.cpp runtime (${_variant.name}): not installed'
                        : 'llama.cpp runtime (${_variant.name}): $_installedTag installed',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                if (runtimeBusy)
                  OutlinedButton(
                    onPressed: _runtime.cancelDownload,
                    child: const Text('Cancel'),
                  )
                else
                  OutlinedButton(
                    onPressed: _runtime.busyKey == null
                        ? () => _guarded(() => _runtime.ensureLatestRuntime())
                        : null,
                    child: Text(
                      _installedTag == null ? 'Download' : 'Check for update',
                    ),
                  ),
              ],
            ),
            if (runtimeBusy) _progressLine(theme),
            if (LlamaRuntimeService.isVulkanAvailable) ...[
              const SizedBox(height: 12),
              SegmentedButton<LlamaBuildVariant>(
                segments: const [
                  ButtonSegment(
                    value: LlamaBuildVariant.cpu,
                    label: Text('CPU'),
                  ),
                  ButtonSegment(
                    value: LlamaBuildVariant.vulkan,
                    label: Text('Vulkan (GPU)'),
                  ),
                ],
                selected: {_variant},
                onSelectionChanged: _runtime.busyKey == null
                    ? (selection) => _selectVariant(selection.single)
                    : null,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              Text(
                'Vulkan offloads inference to a compatible GPU. Switching '
                'builds re-downloads the runtime.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final family in LlamaRuntimeService.families)
                _familySection(theme, family, recommended),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
