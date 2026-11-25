import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:worknotes/core/api_client.dart';
import 'package:worknotes/features/tasks/task.dart';
import 'package:worknotes/features/tasks/task_moscow_board.dart';

void main() {
  testWidgets('MoSCoW groups active tasks and allows changing a category', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TaskMoscowBoard(
              tasks: const [
                Task(
                  id: 1,
                  title: 'Required',
                  description: '',
                  status: 'todo',
                  moscow: 'must',
                ),
                Task(
                  id: 2,
                  title: 'Unclassified',
                  description: '',
                  status: 'todo',
                ),
                Task(
                  id: 3,
                  title: 'Completed',
                  description: '',
                  status: 'done',
                  moscow: 'must',
                ),
              ],
              taskBuilder: (task) => Text(task.title),
              onMove: (task, category) async =>
                  selected.add('${task.id}:$category'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Unclassified'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    await tester.tap(find.text('Изменить категорию').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Could · желательно').last);
    await tester.pumpAndSettle();
    expect(selected, ['1:could']);
  });

  test(
    'MoSCoW updates are sent independently of status and priority',
    () async {
      final requests = <Map<String, dynamic>>[];
      final api = ApiClient(
        client: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 7,
                'title': 'Plan',
                'description': '',
                'status': 'in_progress',
                'priority': 'high',
                'moscow': requests.last['moscow'],
              }),
            ),
            200,
          );
        }),
      );
      final changed = await api.setMoscow(7, 'must');
      expect(changed.moscow, 'must');
      expect(changed.status, 'in_progress');
      expect(requests.single, {'moscow': 'must'});
      final cleared = await api.setMoscow(7, null);
      expect(cleared.moscow, isNull);
      expect(requests.last, {'moscow': null});
      api.close();
    },
  );
}
