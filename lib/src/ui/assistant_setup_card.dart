import 'package:flutter/material.dart';

import '../services/llama_runtime_service.dart';
import '../theme/strategy_palette.dart';
import 'model_chat_suitability.dart';

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
  int? _vramGb;
  final Set<String> _installedModelIds = <String>{};
  List<AssistantModel> _installedModels = const <AssistantModel>[];
  LlamaRuntimePreference _preference = LlamaRuntimePreference.auto;
  LlamaBuildVariant _resolvedVariant = LlamaBuildVariant.cpu;

  ModelCatalogResult _catalog = const ModelCatalogResult(
    models: [],
    fetchedAt: null,
    stale: false,
  );
  bool _loaded = false;
  bool _catalogLoading = false;

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
    final vram = await _runtime.totalVramGb();
    final models = await _runtime.installedModels();
    final preference = await _runtime.runtimePreference();
    final resolved = await _runtime.selectedVariant();
    if (!mounted) return;
    setState(() {
      _installedTag = tag;
      _ramGb = ram;
      _vramGb = vram;
      _preference = preference;
      _resolvedVariant = resolved;
      _installedModels = models;
      _installedModelIds
        ..clear()
        ..addAll(models.map((m) => m.id));
      _loaded = true;
    });
    await _refreshCatalog();
  }

  Future<void> _refreshCatalog({bool force = false}) async {
    if (!mounted) return;
    setState(() => _catalogLoading = true);
    final catalog = await _runtime.modelCatalog(force: force);
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _catalogLoading = false;
    });
  }

  Future<void> _selectPreference(LlamaRuntimePreference preference) async {
    if (preference == _preference) return;
    await _runtime.setRuntimePreference(preference);
    if (!mounted) return;
    final resolved = await _runtime.selectedVariant();
    setState(() {
      _preference = preference;
      _resolvedVariant = resolved;
    });
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

  String _ago(DateTime then) {
    final elapsed = DateTime.now().difference(then);
    if (elapsed.inMinutes < 1) return 'moments ago';
    if (elapsed.inMinutes < 60) {
      final m = elapsed.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (elapsed.inHours < 48) {
      final h = elapsed.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final d = elapsed.inDays;
    return '$d day${d == 1 ? '' : 's'} ago';
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
    AssistantModel? recommended,
  ) {
    final installed = _installedModelIds.contains(model.id);
    final downloading = _runtime.busyKey == model.fileName;
    final idle = _runtime.busyKey == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${model.name} (${model.sizeGb.toStringAsFixed(1)} GB)',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (recommended != null && model.id == recommended.id) ...[
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
                    if (model.smallForChat) ...[
                      const SizedBox(width: 8),
                      const ModelChatSuitabilityChip(),
                    ],
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
          if (model.smallForChat) const ModelChatSuitabilityNote(),
          if (downloading) _progressLine(theme),
        ],
      ),
    );
  }

  Widget _ownerSection(
    ThemeData theme,
    String owner,
    List<AssistantModel> models,
    AssistantModel? recommended,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(owner, style: theme.textTheme.labelSmall),
          const Divider(height: 12),
          for (final model in models) _modelRow(theme, model, recommended),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final models = <AssistantModel>[
      ..._catalog.models,
      for (final model in _installedModels)
        if (!_catalog.models.contains(model)) model,
    ];
    final budget = LlamaRuntimeService.sizeBudgetBytes(
      ramGb: _ramGb,
      vramGb: _vramGb,
    );
    final recommended = LlamaRuntimeService.recommendedModel(models, budget);
    final byOwner = <String, List<AssistantModel>>{};
    for (final model in models) {
      (byOwner[model.owner] ??= []).add(model);
    }
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
                        ? 'llama.cpp runtime (${_resolvedVariant.name}): '
                              'not installed'
                        : 'llama.cpp runtime (${_resolvedVariant.name}): '
                              '$_installedTag installed',
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
            const SizedBox(height: 12),

            if (!LlamaRuntimeService.isMacOS) ...[
              SegmentedButton<LlamaRuntimePreference>(
                segments: [
                  const ButtonSegment(
                    value: LlamaRuntimePreference.auto,
                    label: Text('Automatic'),
                  ),
                  const ButtonSegment(
                    value: LlamaRuntimePreference.forceCpu,
                    label: Text('CPU'),
                  ),
                  if (LlamaRuntimeService.isVulkanAvailable)
                    const ButtonSegment(
                      value: LlamaRuntimePreference.forceVulkan,
                      label: Text('Vulkan (GPU)'),
                    ),
                ],
                selected: {_preference},
                onSelectionChanged: _runtime.busyKey == null
                    ? (selection) => _selectPreference(selection.single)
                    : null,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              LlamaRuntimeService.isMacOS
                  ? 'This Mac runs on Metal. llama.cpp builds Metal support '
                        'into its standard macOS build, so there is nothing '
                        'to choose and nothing extra to download.'
                  : 'Automatic resolved to '
                        '${_resolvedVariant == LlamaBuildVariant.vulkan ? 'Vulkan (GPU)' : 'CPU'}. '
                        'Vulkan offloads inference to a compatible GPU when '
                        'one is detected. Switching builds re-downloads the '
                        'runtime.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_catalog.rateLimited)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hugging Face is rate limiting this network, which '
                          'happens when several computers here look up models '
                          'at once. Wait a few minutes and refresh.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_catalog.stale && _catalog.fetchedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hugging Face is unreachable. Showing a cached '
                          'model list from ${_ago(_catalog.fetchedAt!)}.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_catalog.fetchedAt == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No model list yet. Connect to the internet once to '
                    'build one; it is then cached for offline use.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              for (final owner in byOwner.keys)
                _ownerSection(theme, owner, byOwner[owner]!, recommended),
              if (_catalogLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Looking up models that fit this computer',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _refreshCatalog(force: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh model list'),
                  ),
                ),
            ],
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
