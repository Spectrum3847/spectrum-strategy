import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/document_attachment_actions.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_upload_service.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

const _section = ScoutConfigSection(
  name: 'General',
  fields: <ScoutConfigField>[
    ScoutConfigField(
      title: 'Field map',
      code: 'fieldMap',
      type: ScoutFieldType.document,
    ),
  ],
);

PitPhotoUploadService _uploaderReturning({
  String? uploadedKey,
  Uint8List? downloadBytes,
}) {
  return PitPhotoUploadService(
    baseUrlLoader: () async => 'https://photos.example.workers.dev',
    idTokenProvider: () async => 'fb-token',
    httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        return uploadedKey == null
            ? http.Response('', 500)
            : http.Response('{"key":"$uploadedKey"}', 201);
      }
      if (request.method == 'GET') {
        return downloadBytes == null
            ? http.Response('', 404)
            : http.Response.bytes(downloadBytes, 200);
      }
      return http.Response('', 204);
    }),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String value,
  required PitPhotoUploadService uploader,
  required ValueChanged<dynamic> onChanged,
  Future<PickedDocument?> Function()? pickDocument,
  Future<void> Function(Uint8List, String)? openDocument,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScoutFormSection(
          section: _section,
          keyPrefix: 'pit-field',
          values: <String, dynamic>{'fieldMap': value},
          textControllers: const <String, TextEditingController>{},
          onFieldChanged: (code, v) => onChanged(v),
          documentUploader: uploader,
          pickDocument: pickDocument ?? pickDocumentFile,
          openDocument: openDocument ?? openDocumentBytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty document field offers only Pick file', (tester) async {
    await _pump(
      tester,
      value: '',
      uploader: _uploaderReturning(),
      onChanged: (_) {},
    );

    expect(find.text('No file attached'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Pick file'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Open'), findsNothing);
  });

  testWidgets('picking a file uploads it and reports the Worker key', (
    tester,
  ) async {
    String? changed;
    await _pump(
      tester,
      value: '',
      uploader: _uploaderReturning(uploadedKey: 'abc123.pdf'),
      onChanged: (v) => changed = v as String,
      pickDocument: () async => PickedDocument(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        contentType: 'application/pdf',
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Pick file'));
    await tester.pumpAndSettle();

    expect(changed, 'abc123.pdf');
  });

  testWidgets(
    'a failed upload shows an inline error and does not report a key',
    (tester) async {
      var called = false;
      await _pump(
        tester,
        value: '',
        uploader: _uploaderReturning(),
        onChanged: (_) => called = true,
        pickDocument: () async => PickedDocument(
          bytes: Uint8List.fromList(<int>[1]),
          contentType: 'application/pdf',
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Pick file'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(
        find.text('Could not upload. Check your connection and try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('an attached document offers Open and Replace', (tester) async {
    await _pump(
      tester,
      value: 'abc123.pdf',
      uploader: _uploaderReturning(),
      onChanged: (_) {},
    );

    expect(find.textContaining('Attached'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);
  });

  testWidgets('replacing an attachment deletes the old Worker object', (
    tester,
  ) async {
    final deleted = <String>[];
    final uploader = PitPhotoUploadService(
      baseUrlLoader: () async => 'https://photos.example.workers.dev',
      idTokenProvider: () async => 'fb-token',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response('{"key":"new-key.pdf"}', 201);
        }
        if (request.method == 'DELETE') {
          deleted.add(request.url.pathSegments.last);
          return http.Response('', 204);
        }
        return http.Response('', 404);
      }),
    );
    String? changed;
    await _pump(
      tester,
      value: 'old-key.pdf',
      uploader: uploader,
      onChanged: (v) => changed = v as String,
      pickDocument: () async => PickedDocument(
        bytes: Uint8List.fromList(<int>[1]),
        contentType: 'application/pdf',
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Replace'));
    await tester.pumpAndSettle();

    expect(changed, 'new-key.pdf');
    expect(deleted, <String>['old-key.pdf']);
  });

  testWidgets('opening a document downloads it and hands it to openDocument', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(<int>[9, 9, 9]);
    Uint8List? opened;
    String? openedKey;
    await _pump(
      tester,
      value: 'abc123.pdf',
      uploader: _uploaderReturning(downloadBytes: bytes),
      onChanged: (_) {},
      openDocument: (b, key) async {
        opened = b;
        openedKey = key;
      },
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
    await tester.pumpAndSettle();

    expect(opened, bytes);
    expect(openedKey, 'abc123.pdf');
  });

  testWidgets('an unavailable Worker shows a message instead of controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoutFormSection(
            section: _section,
            keyPrefix: 'scout-field',
            values: const <String, dynamic>{'fieldMap': ''},
            textControllers: const <String, TextEditingController>{},
            onFieldChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Attachments are not available in this form.'),
      findsOneWidget,
    );
  });
}
