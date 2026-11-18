import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worknotes/core/api_client.dart';

void main() {
  test(
    'создание, чтение, смена статуса и удаление используют API задач',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {'id': 1, 'title': 'Test', 'description': '', 'status': 'todo'},
            ]),
            200,
          );
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], 'Новая');
          expect(body['project_id'], isNull);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 2,
                'title': 'Новая',
                'description': '',
                'status': 'todo',
              }),
            ),
            201,
          );
        }
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body.containsKey('title')) {
            expect(body, {
              'title': 'Edited',
              'description': 'New details',
              'project_id': null,
            });
          } else {
            expect(body['status'], 'done');
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 1,
                'title': body['title'] ?? 'Test',
                'description': body['description'] ?? '',
                'status': 'done',
              }),
            ),
            200,
          );
        }
        return http.Response('', 204);
      });
      final api = ApiClient(client: client, baseUrl: 'http://localhost:8000');

      expect((await api.getTasks()).single.id, 1);
      expect((await api.createTask('Новая', '')).id, 2);
      expect((await api.updateStatus(1, 'done')).isDone, true);
      final edited = await api.editTask(1, 'Edited', 'New details');
      expect(edited.title, 'Edited');
      expect(edited.description, 'New details');
      expect(edited.isDone, true);
      await api.deleteTask(1);
      expect(requests, [
        'GET /tasks',
        'POST /tasks',
        'PATCH /tasks/1',
        'PATCH /tasks/1',
        'DELETE /tasks/1',
      ]);
      api.close();
    },
  );

  test('ошибка сервера не выглядит как успешный ответ', () async {
    final api = ApiClient(
      client: MockClient((request) async => http.Response('Not found', 404)),
    );
    await expectLater(api.getTasks(), throwsA(isA<ApiException>()));
    api.close();
  });

  test('проекты и привязка задачи используют API', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' && request.url.path == '/projects') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {'id': 5, 'name': 'Учёба'},
            ]),
          ),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/projects') {
        expect(jsonDecode(request.body)['name'], 'Работа');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'id': 6, 'name': 'Работа'})),
          201,
        );
      }
      if (request.method == 'GET') {
        expect(request.url.queryParameters['project_id'], '5');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'id': 7,
                'title': 'Курсовая',
                'description': '',
                'status': 'todo',
                'project_id': 5,
              },
            ]),
          ),
          200,
        );
      }
      if (request.method == 'DELETE' && request.url.path == '/projects/5') {
        return http.Response('', 204);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['project_id'], request.method == 'PATCH' ? null : 5);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'id': 7,
            'title': body['title'] ?? 'Курсовая',
            'description': body['description'] ?? '',
            'status': 'todo',
            'project_id': body['project_id'],
          }),
        ),
        200,
      );
    });
    final api = ApiClient(client: client, baseUrl: 'http://localhost:8000');
    expect((await api.getProjects()).single.name, 'Учёба');
    expect((await api.createProject('Работа')).id, 6);
    await api.deleteProject(5);
    expect((await api.getTasks(projectId: 5)).single.projectId, 5);
    expect((await api.createTask('Курсовая', '', projectId: 5)).projectId, 5);
    expect(
      (await api.editTask(7, 'Курсовая', '', projectId: null)).projectId,
      isNull,
    );
    expect(requests, [
      'GET /projects',
      'POST /projects',
      'DELETE /projects/5',
      'GET /tasks',
      'POST /tasks',
      'PATCH /tasks/7',
    ]);
    api.close();
  });
}
