import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:worknotes/core/api_client.dart';
import 'package:worknotes/features/tasks/task.dart';
import 'package:worknotes/features/tasks/task_matrix_board.dart';

void main() {
  testWidgets('четыре квадрата, готовые задачи скрыты, перенос доступен', (
    tester,
  ) async {
    final moved = <String>[];
    const tasks = [
      Task(
        id: 1,
        title: 'Сейчас',
        description: '',
        status: 'todo',
        priority: 'high',
        urgent: true,
      ),
      Task(
        id: 2,
        title: 'Позже',
        description: '',
        status: 'todo',
        priority: 'high',
        urgent: false,
      ),
      Task(
        id: 3,
        title: 'Поручить',
        description: '',
        status: 'todo',
        priority: 'low',
        urgent: true,
      ),
      Task(
        id: 4,
        title: 'Отложить',
        description: '',
        status: 'todo',
        priority: 'medium',
        urgent: false,
      ),
      Task(
        id: 5,
        title: 'Готово',
        description: '',
        status: 'done',
        priority: 'high',
        urgent: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TaskMatrixBoard(
              tasks: tasks,
              taskBuilder: (task) => Text(task.title),
              onMove: (task, target) async {
                moved.add('${task.id}:$target');
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('Сейчас'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget);
    expect(find.text('Поручить'), findsOneWidget);
    expect(find.text('Отложить'), findsOneWidget);
    expect(find.text('Готово'), findsNothing);
    await tester.tap(find.text('Переместить ▾').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Важно, не срочно').last);
    await tester.pumpAndSettle();
    expect(moved, ['1:not_urgent_important']);
  });

  test('перемещение меняет приоритет и срочность через PATCH', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/tasks/6');
        expect(jsonDecode(request.body), {'priority': 'high', 'urgent': true});
        return http.Response(
          jsonEncode({
            'id': 6,
            'title': 'Перенесена',
            'description': '',
            'status': 'todo',
            'priority': 'high',
            'urgent': true,
            'is_urgent': true,
          }),
          200,
        );
      }),
    );
    const task = Task(
      id: 6,
      title: 'Перенесена',
      description: '',
      status: 'todo',
      priority: 'medium',
    );
    final moved = await api.moveTaskInMatrix(
      task,
      important: true,
      urgent: true,
    );
    expect(moved.matrixQuadrant, 'urgent_important');
    api.close();
  });
}
