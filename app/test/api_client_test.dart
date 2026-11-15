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
          expect(jsonDecode(request.body)['title'], 'Новая');
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
          expect(jsonDecode(request.body)['status'], 'done');
          return http.Response(
            jsonEncode({
              'id': 1,
              'title': 'Test',
              'description': '',
              'status': 'done',
            }),
            200,
          );
        }
        return http.Response('', 204);
      });
      final api = ApiClient(client: client, baseUrl: 'http://localhost:8000');

      expect((await api.getTasks()).single.id, 1);
      expect((await api.createTask('Новая', '')).id, 2);
      expect((await api.updateStatus(1, 'done')).isDone, true);
      await api.deleteTask(1);
      expect(requests, [
        'GET /tasks',
        'POST /tasks',
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
}
