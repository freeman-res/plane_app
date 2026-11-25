import 'package:material_ui/material_ui.dart';

import 'task.dart';

/// Planning groups for active tasks in the selected project/filter.
class TaskMoscowBoard extends StatelessWidget {
  const TaskMoscowBoard({
    super.key,
    required this.tasks,
    required this.taskBuilder,
    required this.onMove,
  });

  final List<Task> tasks;
  final Widget Function(Task) taskBuilder;
  final Future<void> Function(Task, String) onMove;

  static const _groups = [
    ('must', 'Must · обязательно', Color(0xFFE25468)),
    ('should', 'Should · важно', Color(0xFFE5A04B)),
    ('could', 'Could · желательно', Color(0xFF4269EF)),
    ('wont', 'Won’t · отложено', Color(0xFF7E8B9D)),
    ('unassigned', 'Без категории', Color(0xFF9BA8B8)),
  ];

  Widget _panel((String, String, Color) group, List<Task> items) {
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
              Icon(Icons.circle, size: 12, color: group.$3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: group.$3.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: group.$3,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 25),
          if (items.isEmpty)
            const Text(
              'Задач пока нет',
              style: TextStyle(color: Color(0xFF78879C)),
            ),
          for (final task in items) ...[
            taskBuilder(task),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Изменить категорию MoSCoW',
                onSelected: (value) => onMove(task, value),
                itemBuilder: (_) => [
                  for (final target in _groups)
                    if (target.$1 != group.$1)
                      PopupMenuItem(value: target.$1, child: Text(target.$2)),
                ],
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 6, 14),
                  child: Text(
                    'Изменить категорию',
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
      for (final group in _groups)
        group.$1: active
            .where((task) => (task.moscow ?? 'unassigned') == group.$1)
            .toList(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 680 ? 1 : 2;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 14) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите проект, чтобы спланировать его задачи. '
              'Завершённые задачи остаются в списке и на доске.',
              style: TextStyle(color: Color(0xFF78879C)),
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < _groups.length; index += columns) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var offset = 0; offset < columns; offset++) ...[
                    if (offset > 0) const SizedBox(width: 14),
                    if (index + offset < _groups.length)
                      SizedBox(
                        width: width,
                        child: _panel(
                          _groups[index + offset],
                          groups[_groups[index + offset].$1]!,
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}
