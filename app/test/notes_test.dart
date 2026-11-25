import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worknotes/core/api_client.dart';
import 'package:worknotes/features/notes/note.dart';
import 'package:worknotes/features/notes/note_text_controller.dart';

void main() {
  final noteJson = <String, dynamic>{
    'id': 7,
    'title': 'Идея',
    'content': [
      {
        'type': 'heading',
        'spans': [
          {
            'text': 'Текст',
            'font_family': 'serif',
            'font_size': 22,
            'bold': true,
            'color': '#4269EF',
          },
        ],
      },
    ],
    'created_at': '2026-11-19T10:00:00',
    'updated_at': '2026-11-19T10:00:00',
    'task_ids': [3],
    'attachments': <dynamic>[],
  };

  test('notes API sends blocks, task links and raw attachment bytes', () async {
    final paths = <String>[];
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((request) async {
        paths.add(
          '${request.method} ${request.url.path}${request.url.hasQuery ? '?${request.url.query}' : ''}',
        );
        if (request.url.path.endsWith('/attachments')) {
          expect(request.headers['content-type'], 'image/png');
          expect(request.bodyBytes, [137, 80, 78, 71]);
          return http.Response(
            jsonEncode({
              'id': 5,
              'note_id': 7,
              'filename': 'фото.png',
              'media_type': 'image/png',
              'size': 4,
            }),
            201,
          );
        }
        if (request.method == 'POST' && request.url.path == '/notes') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['title'], 'Идея');
          final block =
              (payload['content'] as List).first as Map<String, dynamic>;
          expect(block['type'], 'heading');
          expect((block['spans'] as List).first['font_family'], 'serif');
          return http.Response(jsonEncode(noteJson), 201);
        }
        if (request.url.path.endsWith('/create-task')) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['deadline'], '2026-11-25');
          expect(payload['priority'], 'high');
          return http.Response(
            jsonEncode({
              'id': 3,
              'title': 'Идея',
              'description': 'Текст',
              'status': 'todo',
              'priority': 'high',
            }),
            201,
          );
        }
        return http.Response(
          jsonEncode(request.url.path == '/notes' ? [noteJson] : noteJson),
          200,
        );
      }),
    );
    final notes = await client.getNotes(taskId: 3);
    expect(notes.single.taskIds, [3]);
    final created = await client.createNote('Идея', [
      const NoteBlock(
        type: 'heading',
        spans: [NoteSpan(text: 'Текст', fontFamily: 'serif', fontSize: 22)],
      ),
    ]);
    expect(created.content.single.spans.single.fontFamily, 'serif');
    await client.linkNoteTask(7, 3);
    await client.createTaskFromNote(
      7,
      deadline: '2026-11-25',
      priority: 'high',
    );
    await client.uploadNoteAttachment(7, 'фото.png', 'image/png', [
      137,
      80,
      78,
      71,
    ]);
    expect(paths, contains('GET /notes?task_id=3'));
    expect(paths, contains('PUT /notes/7/tasks/3'));
    expect(
      paths,
      contains(
        'POST /notes/7/attachments?filename=%D1%84%D0%BE%D1%82%D0%BE.png',
      ),
    );
    client.close();
  });

  test('formatting selected text survives typing elsewhere', () {
    final controller = NoteTextController([
      const NoteSpan(text: 'Начало конец'),
    ]);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    controller.format((span) => span.copyWith(bold: true, color: '#4269EF'));
    expect(controller.spans.first.bold, isTrue);
    expect(controller.spans.first.text, 'Начало');
    controller.value = const TextEditingValue(
      text: 'Начало и конец',
      selection: TextSelection.collapsed(offset: 8),
    );
    expect(controller.spans.map((span) => span.text).join(), 'Начало и конец');
    expect(controller.spans.first.bold, isTrue);
    expect(controller.spans.last.bold, isFalse);
    controller.dispose();
  });
}
