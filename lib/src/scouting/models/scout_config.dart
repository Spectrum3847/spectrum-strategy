import 'action_tracker.dart';

enum ScoutFieldType {
  text,
  number,
  boolean,
  select,
  range,
  counter,
  multiCounter,
  actionTracker,

  tbaMatchNumber,

  tbaTeamAndRobot,

  checkboxSelect;

  String get displayName {
    switch (this) {
      case ScoutFieldType.text:
        return 'Text';
      case ScoutFieldType.number:
        return 'Number';
      case ScoutFieldType.boolean:
        return 'Boolean';
      case ScoutFieldType.select:
        return 'Select';
      case ScoutFieldType.range:
        return 'Range';
      case ScoutFieldType.counter:
        return 'Counter';
      case ScoutFieldType.multiCounter:
        return 'Multi-Counter';
      case ScoutFieldType.actionTracker:
        return 'Action Tracker';
      case ScoutFieldType.tbaMatchNumber:
        return 'Match Number (schedule)';
      case ScoutFieldType.tbaTeamAndRobot:
        return 'Team and Station (schedule)';
      case ScoutFieldType.checkboxSelect:
        return 'Multi-select';
    }
  }

  static String normalizeTypeName(String s) =>
      s.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  static ScoutFieldType fromString(String s) {
    final n = normalizeTypeName(s);
    switch (n) {
      case 'number':
        return number;
      case 'boolean':
      case 'checkbox':
        return boolean;
      case 'select':
      case 'dropdown':
        return select;
      case 'range':
      case 'slider':
        return range;
      case 'counter':
        return counter;
      case 'multicounter':
        return multiCounter;
      case 'actiontracker':
        return actionTracker;
      case 'tbamatchnumber':
        return tbaMatchNumber;
      case 'tbateamandrobot':
        return tbaTeamAndRobot;

      case 'checkboxselect':
      case 'multiselect':
        return checkboxSelect;
      default:
        return text;
    }
  }
}

enum ResetBehavior {
  reset,
  preserve,
  increment;

  static ResetBehavior fromString(String s) {
    switch (s) {
      case 'preserve':
        return preserve;
      case 'increment':
        return increment;
      default:
        return reset;
    }
  }
}

class ScoutConfigField {
  const ScoutConfigField({
    required this.title,
    this.description = '',
    required this.type,
    this.required = false,
    required this.code,
    this.formResetBehavior = ResetBehavior.reset,
    this.defaultValue,
    this.choices,
    this.min,
    this.max,
    this.step,
    this.buttons,
    this.rawType = '',
    this.actions = const <TrackedAction>[],
    this.trackerMode = ActionTrackerMode.hold,
    this.timerDuration,
    this.autoStopSeconds,
    this.retiredChoiceKeys = const <String>{},
  });

  final String title;
  final String description;
  final ScoutFieldType type;
  final bool required;
  final String code;
  final ResetBehavior formResetBehavior;
  final dynamic defaultValue;

  final Map<String, String>? choices;

  final Set<String> retiredChoiceKeys;

  final double? min;
  final double? max;
  final double? step;

  final List<int>? buttons;

  final String rawType;

  final List<TrackedAction> actions;

  final ActionTrackerMode trackerMode;

  final double? timerDuration;

  final double? autoStopSeconds;

  bool get typeIsUnsupported =>
      rawType.isNotEmpty &&
      type == ScoutFieldType.text &&
      ScoutFieldType.normalizeTypeName(rawType) != 'text';

  dynamic get effectiveDefault {
    if (type == ScoutFieldType.checkboxSelect) {
      return joinKeys(selectedKeys(defaultValue));
    }
    if (defaultValue != null) return defaultValue;
    switch (type) {
      case ScoutFieldType.text:
        return '';
      case ScoutFieldType.number:
      case ScoutFieldType.counter:
      case ScoutFieldType.range:
      case ScoutFieldType.multiCounter:
        return 0;
      case ScoutFieldType.boolean:
        return false;
      case ScoutFieldType.select:
        return activeChoices.keys.firstOrNull ??
            choices?.keys.firstOrNull ??
            '';
      case ScoutFieldType.actionTracker:
        return null;
      case ScoutFieldType.tbaMatchNumber:
        return 0;
      case ScoutFieldType.tbaTeamAndRobot:
        return null;
      case ScoutFieldType.checkboxSelect:
        return '';
    }
  }

  static List<String> selectedKeys(dynamic value) {
    if (value is List) {
      return <String>[
        for (final v in value)
          if (v.toString().trim().isNotEmpty) v.toString().trim(),
      ];
    }
    final text = value?.toString() ?? '';
    if (text.trim().isEmpty) return const <String>[];
    return <String>[
      for (final part in text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String joinKeys(Iterable<String> keys) => keys.join(',');

  Map<String, String> get activeChoices {
    final choices = this.choices;
    if (choices == null) return const <String, String>{};
    if (retiredChoiceKeys.isEmpty) return choices;
    return <String, String>{
      for (final e in choices.entries)
        if (!retiredChoiceKeys.contains(e.key)) e.key: e.value,
    };
  }

  Map<String, String> choiceOptions(Iterable<String> keepKeys) {
    final choices = this.choices;
    if (choices == null) return const <String, String>{};
    final active = activeChoices;
    final extras = <String, String>{
      for (final key in keepKeys)
        if (!active.containsKey(key) && choices.containsKey(key))
          key: choices[key]!,
    };
    if (extras.isEmpty) return active;
    return <String, String>{...active, ...extras};
  }

  String serializeValue(dynamic value) {
    if (value == null) return '';

    if (value is Map) return value['teamNumber']?.toString() ?? '';

    if (value is List) return joinKeys(selectedKeys(value));
    return value.toString();
  }

  ScoutConfigField copyWith({
    String? title,
    String? description,
    Map<String, String>? choices,
    Set<String>? retiredChoiceKeys,
  }) {
    return ScoutConfigField(
      title: title ?? this.title,
      description: description ?? this.description,
      type: type,
      required: required,
      code: code,
      formResetBehavior: formResetBehavior,
      defaultValue: defaultValue,
      choices: choices ?? this.choices,
      retiredChoiceKeys: retiredChoiceKeys ?? this.retiredChoiceKeys,
      min: min,
      max: max,
      step: step,
      buttons: buttons,

      rawType: rawType,
      actions: actions,
      trackerMode: trackerMode,
      timerDuration: timerDuration,
      autoStopSeconds: autoStopSeconds,
    );
  }

  String get _typeString {
    switch (type) {
      case ScoutFieldType.text:
        return 'text';
      case ScoutFieldType.number:
        return 'number';
      case ScoutFieldType.boolean:
        return 'boolean';
      case ScoutFieldType.select:
        return 'select';
      case ScoutFieldType.range:
        return 'range';
      case ScoutFieldType.counter:
        return 'counter';
      case ScoutFieldType.multiCounter:
        return 'multi-counter';
      case ScoutFieldType.actionTracker:
        return 'action-tracker';
      case ScoutFieldType.tbaMatchNumber:
        return 'TBA-match-number';
      case ScoutFieldType.tbaTeamAndRobot:
        return 'TBA-team-and-robot';
      case ScoutFieldType.checkboxSelect:
        return 'checkbox-select';
    }
  }

  String? resolveStoredChoice(Object? stored) {
    final choices = this.choices;
    if (choices == null || choices.isEmpty) return null;
    final value = stored?.toString() ?? '';
    if (value.isEmpty) return null;
    if (choices.containsKey(value)) return value;
    for (final entry in choices.entries) {
      if (entry.value == value) return entry.key;
    }
    return null;
  }

  String labelForStored(Object? stored) {
    final value = stored?.toString() ?? '';
    final key = resolveStoredChoice(value);
    if (key == null) return value;
    return choices?[key] ?? value;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      if (description.isNotEmpty) 'description': description,

      'type': typeIsUnsupported ? rawType : _typeString,
      'required': required,
      'code': code,
      'formResetBehavior': formResetBehavior.name,
      'defaultValue': defaultValue,
      if (choices != null) 'choices': choices,

      if (retiredChoiceKeys.isNotEmpty)
        'retiredChoiceKeys': retiredChoiceKeys.toList(growable: false),
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (step != null) 'step': step,
      if (buttons != null && buttons!.isNotEmpty) 'buttons': buttons,
      if (type == ScoutFieldType.actionTracker) ...<String, dynamic>{
        'mode': trackerMode.name,
        'actions': <Map<String, dynamic>>[
          for (final action in actions)
            <String, dynamic>{
              'code': action.code,
              'label': action.label,
              if (action.icon != null) 'icon': action.icon,
            },
        ],
        if (timerDuration != null) 'timerDuration': timerDuration,
        if (autoStopSeconds != null) 'autoStopSeconds': autoStopSeconds,
      },
    };
  }

  factory ScoutConfigField.fromJson(Map<String, dynamic> json) {
    Map<String, String>? choices;
    final rawChoices = json['choices'];
    if (rawChoices is Map) {
      choices = <String, String>{
        for (final e in rawChoices.entries)
          e.key.toString(): e.value.toString(),
      };
    } else if (rawChoices is List) {
      choices = <String, String>{
        for (final v in rawChoices) v.toString(): v.toString(),
      };
    }
    return ScoutConfigField(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rawType: json['type'] as String? ?? '',
      type: ScoutFieldType.fromString(json['type'] as String? ?? 'text'),
      required: json['required'] as bool? ?? false,
      code: json['code'] as String? ?? '',
      formResetBehavior: ResetBehavior.fromString(
        json['formResetBehavior'] as String? ?? 'reset',
      ),
      defaultValue: json['defaultValue'],
      choices: choices,
      retiredChoiceKeys: <String>{
        for (final k in (json['retiredChoiceKeys'] as List?) ?? const [])
          k.toString(),
      },
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      step: (json['step'] as num?)?.toDouble(),
      buttons: (json['buttons'] as List?)
          ?.whereType<num>()
          .map((n) => n.toInt())
          .toList(growable: false),
      actions: <TrackedAction>[
        for (final raw in (json['actions'] as List?) ?? const <dynamic>[])
          if (raw is Map)
            TrackedAction.fromJson(Map<String, dynamic>.from(raw)),
      ],
      trackerMode: ActionTrackerMode.fromString(json['mode'] as String?),
      timerDuration: (json['timerDuration'] as num?)?.toDouble(),
      autoStopSeconds: (json['autoStopSeconds'] as num?)?.toDouble(),
    );
  }
}

class ScoutConfigSection {
  const ScoutConfigSection({required this.name, required this.fields});

  final String name;
  final List<ScoutConfigField> fields;

  ScoutConfigSection copyWith({String? name, List<ScoutConfigField>? fields}) {
    return ScoutConfigSection(
      name: name ?? this.name,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'fields': fields.map((f) => f.toJson()).toList(growable: false),
    };
  }

  factory ScoutConfigSection.fromJson(Map<String, dynamic> json) {
    final rawFields = (json['fields'] as List?) ?? <dynamic>[];
    return ScoutConfigSection(
      name: json['name'] as String? ?? '',
      fields: rawFields
          .whereType<Map>()
          .map((f) => ScoutConfigField.fromJson(f.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class ScoutConfig {
  const ScoutConfig({
    required this.title,
    this.pageTitle = '',
    this.delimiter = '\t',
    required this.sections,
    this.revision = 0,
  });

  final String title;
  final String pageTitle;
  final String delimiter;
  final List<ScoutConfigSection> sections;

  final int revision;

  List<ScoutConfigField> get allFields =>
      sections.expand((s) => s.fields).toList(growable: false);

  static const Map<String, String> knownUnsupportedTypes = <String, String>{
    'timer': 'the cycle logger covers timing instead',
    'image': 'photos are pit-only for now',
  };

  List<String> get unsupportedFieldTypes {
    final seen = <String>{};
    final types = <String>[];
    for (final field in allFields) {
      if (!field.typeIsUnsupported) continue;
      if (seen.add(ScoutFieldType.normalizeTypeName(field.rawType))) {
        types.add(field.rawType);
      }
    }
    return List<String>.unmodifiable(types);
  }

  ({List<String> known, List<String> unrecognised}) get unsupportedTypesSplit {
    final known = <String>[];
    final unrecognised = <String>[];
    for (final type in unsupportedFieldTypes) {
      if (knownUnsupportedTypes.containsKey(
        ScoutFieldType.normalizeTypeName(type),
      )) {
        known.add(type);
      } else {
        unrecognised.add(type);
      }
    }
    return (
      known: List<String>.unmodifiable(known),
      unrecognised: List<String>.unmodifiable(unrecognised),
    );
  }

  static String? reasonUnsupported(String type) =>
      knownUnsupportedTypes[ScoutFieldType.normalizeTypeName(type)];

  ScoutConfig copyWith({
    String? title,
    String? pageTitle,
    String? delimiter,
    List<ScoutConfigSection>? sections,
    int? revision,
  }) {
    return ScoutConfig(
      title: title ?? this.title,
      pageTitle: pageTitle ?? this.pageTitle,
      delimiter: delimiter ?? this.delimiter,
      sections: sections ?? this.sections,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'page_title': pageTitle,
      'delimiter': delimiter,
      'sections': sections.map((s) => s.toJson()).toList(growable: false),
      'revision': revision,
    };
  }

  factory ScoutConfig.fromJson(Map<String, dynamic> json) {
    final rawSections = (json['sections'] as List?) ?? <dynamic>[];

    final rawDelimiter = json['delimiter'] as String? ?? '\t';
    final delimiter = (rawDelimiter.isEmpty || rawDelimiter.length > 4)
        ? '\t'
        : rawDelimiter;
    return ScoutConfig(
      title: json['title'] as String? ?? 'Scout',
      pageTitle: json['page_title'] as String? ?? '',
      delimiter: delimiter,
      sections: rawSections
          .whereType<Map>()
          .map((s) => ScoutConfigSection.fromJson(s.cast<String, dynamic>()))
          .toList(growable: false),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );
  }

  String? get validationError {
    for (final field in allFields) {
      final choices = field.choices;
      if (field.type != ScoutFieldType.select || choices == null) continue;
      final values = choices.values.toList(growable: false);
      if (values.toSet().length != values.length) {
        return 'Select field "${field.code}" has duplicate option values; '
            'each option must map to a unique value.';
      }
    }
    final trackers = allFields
        .where((f) => f.type == ScoutFieldType.actionTracker)
        .toList(growable: false);
    if (trackers.isEmpty) return null;
    if (delimiter == ',') {
      return 'This config uses "," as its delimiter and has an action tracker, '
          'which joins its timestamps with commas. One would destroy the other, '
          'so use a tab delimiter or drop the tracker.';
    }
    if (delimiter == '-' &&
        trackers.any((f) => f.trackerMode == ActionTrackerMode.hold)) {
      return 'This config uses "-" as its delimiter and has a hold-mode action '
          'tracker, which writes each span as start-end. One would destroy the '
          'other, so use a tab delimiter or switch the tracker to tap mode.';
    }
    return null;
  }

  List<ScoutPayloadColumn> get payloadColumns {
    final columns = <ScoutPayloadColumn>[];
    for (final field in allFields) {
      if (field.type != ScoutFieldType.actionTracker) {
        columns.add(ScoutPayloadColumn(code: field.code, field: field));
        continue;
      }
      for (final action in field.actions) {
        columns.add(
          ScoutPayloadColumn(
            code: '${field.code}_${action.code}_count',
            field: field,
            derivedKind: ScoutPayloadDerived.count,
          ),
        );
        columns.add(
          ScoutPayloadColumn(
            code: '${field.code}_${action.code}_times',
            field: field,
            derivedKind: ScoutPayloadDerived.times,
          ),
        );
      }
    }
    return List<ScoutPayloadColumn>.unmodifiable(columns);
  }

  String encodeValues(Map<String, dynamic> values) {
    return payloadColumns
        .map((c) => _sanitizeValue(c.serialize(values[c.code])))
        .join(delimiter);
  }

  String _sanitizeValue(String value) {
    return value
        .replaceAll(delimiter, ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  Map<String, dynamic> decodeValues(String payload) {
    final columns = payloadColumns;
    final parts = payload.split(delimiter);
    final result = <String, dynamic>{};
    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      if (i < parts.length) {
        result[column.code] = column.derivedKind == null
            ? _parseValue(parts[i], column.field)
            : column.parseDerived(parts[i]);
        continue;
      }

      if (column.derivedKind != null) {
        result[column.code] = column.parseDerived('');
      }
    }
    return result;
  }

  static dynamic _parseValue(String raw, ScoutConfigField field) {
    switch (field.type) {
      case ScoutFieldType.number:
      case ScoutFieldType.counter:
      case ScoutFieldType.multiCounter:
        return num.tryParse(raw) ?? field.effectiveDefault;
      case ScoutFieldType.tbaMatchNumber:
        return num.tryParse(raw) ?? field.effectiveDefault;
      case ScoutFieldType.tbaTeamAndRobot:
        final team = int.tryParse(raw.trim());
        return team == null
            ? null
            : <String, dynamic>{'teamNumber': team, 'robotPosition': ''};
      case ScoutFieldType.range:
        return double.tryParse(raw) ?? field.effectiveDefault;
      case ScoutFieldType.boolean:
        return raw.toLowerCase() == 'true';
      default:
        return raw;
    }
  }
}

enum ScoutPayloadDerived { count, times }

class ScoutPayloadColumn {
  const ScoutPayloadColumn({
    required this.code,
    required this.field,
    this.derivedKind,
  });

  final String code;

  final ScoutConfigField field;

  final ScoutPayloadDerived? derivedKind;

  String serialize(dynamic value) {
    switch (derivedKind) {
      case null:
        return field.serializeValue(value);
      case ScoutPayloadDerived.count:
        return value == null ? '0' : value.toString();
      case ScoutPayloadDerived.times:
        return value?.toString() ?? '';
    }
  }

  dynamic parseDerived(String raw) {
    switch (derivedKind) {
      case ScoutPayloadDerived.count:
        return int.tryParse(raw.trim()) ?? 0;
      case ScoutPayloadDerived.times:
        return raw;
      case null:
        return raw;
    }
  }
}
