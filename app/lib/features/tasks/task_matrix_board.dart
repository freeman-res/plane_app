import 'package:material_ui/material_ui.dart';

import 'task.dart';

/// Four quadrants of the Eisenhower matrix. Completed tasks stay in the board/list.
class TaskMatrixBoard extends StatelessWidget {
  const TaskMatrixBoard({
    super.key,
    required this.tasks,
    required this.taskBuilder,
    required this.onMove,
  });

  final List<Task> tasks;
  final Widget Function(Task) taskBuilder;
  final Future<void> Function(Task, String) onMove;

  static const _quadrants = [
    ('urgent_important', 'Срочно и важно', 'Сделать сейчас', Color(0xFFE25468)),
    (
      'not_urgent_important',
      'Важно, не срочно',
      'Запланировать',
      Color(0xFF4269EF),
    ),
    (
      'urgent_not_important',
      'Срочно, не важно',
      'Перепоручить или упростить',
      Color(0xFFE5A04B),
    ),
    (
      'not_urgent_not_important',
      'Не срочно и не важно',
      'Отложить или убрать',
      Color(0xFF7E8B9D),
    ),
  ];

  Widget _panel((String, String, String, Color) quadrant, List<Task> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        border: Border.all(color: const Color(0xFFE4EAF4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: quadrant.$4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  quadrant.$2,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: quadrant.$4.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: quadrant.$4,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(quadrant.$3, style: const TextStyle(color: Color(0xFF78879C))),
          const Divider(height: 25),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Задач пока нет',
                style: TextStyle(color: Color(0xFF78879C)),
              ),
            ),
          for (final task in items) ...[
            taskBuilder(task),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Переместить в другой квадрат',
                onSelected: (value) => onMove(task, value),
                itemBuilder: (_) => [
                  for (final target in _quadrants)
                    if (target.$1 != quadrant.$1)
                      PopupMenuItem(value: target.$1, child: Text(target.$2)),
                ],
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 6, 14),
                  child: Text(
                    'Переместить ▾',
                    style: TextStyle(color: Color(0xFF4269EF), fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = tasks.where((task) => !task.isDone).toList();
    final groups = {
      for (final quadrant in _quadrants)
        quadrant.$1: active
            .where((task) => task.matrixQuadrant == quadrant.$1)
            .toList(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget panel(int index) =>
            _panel(_quadrants[index], groups[_quadrants[index].$1]!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Важное = высокий приоритет. Срочность определяется дедлайном '
              '(сегодня или в ближайшие 2 дня), её можно изменить вручную. '
              'Готовые задачи остаются в списке и на доске.',
              style: TextStyle(color: Color(0xFF78879C)),
            ),
            const SizedBox(height: 16),
            if (constraints.maxWidth < 700)
              for (var i = 0; i < 4; i++) ...[
                panel(i),
                const SizedBox(height: 14),
              ]
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: panel(0)),
                  const SizedBox(width: 14),
                  Expanded(child: panel(1)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: panel(2)),
                  const SizedBox(width: 14),
                  Expanded(child: panel(3)),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
