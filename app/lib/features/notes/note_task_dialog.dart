import 'package:material_ui/material_ui.dart';

import '../projects/project.dart';

class NoteTaskOptions {
  const NoteTaskOptions(
    this.projectId,
    this.status,
    this.priority,
    this.startDate,
    this.deadline,
  );
  final int? projectId;
  final String status;
  final String priority;
  final String startDate;
  final String? deadline;
}

class NoteTaskDialog extends StatefulWidget {
  const NoteTaskDialog({super.key, required this.projects});
  final List<Project> projects;

  @override
  State<NoteTaskDialog> createState() => _NoteTaskDialogState();
}

class _NoteTaskDialogState extends State<NoteTaskDialog> {
  int? _projectId;
  String _status = 'todo';
  String _priority = 'medium';
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  DateTime? _deadline;

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Задача из заметки'),
    scrollable: true,
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Название и текст задачи будут взяты из заметки.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: 0,
            decoration: const InputDecoration(labelText: 'Проект'),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Без проекта')),
              for (final project in widget.projects)
                DropdownMenuItem(value: project.id, child: Text(project.name)),
            ],
            onChanged: (value) =>
                setState(() => _projectId = value == 0 ? null : value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Статус'),
            items: const [
              DropdownMenuItem(value: 'todo', child: Text('Сделать')),
              DropdownMenuItem(value: 'in_progress', child: Text('В работе')),
              DropdownMenuItem(value: 'done', child: Text('Готово')),
            ],
            onChanged: (value) => setState(() => _status = value ?? _status),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Приоритет'),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Низкий')),
              DropdownMenuItem(value: 'medium', child: Text('Средний')),
              DropdownMenuItem(value: 'high', child: Text('Высокий')),
            ],
            onChanged: (value) =>
                setState(() => _priority = value ?? _priority),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null && mounted) setState(() => _start = date);
            },
            icon: const Icon(Icons.today_outlined),
            label: Text('Начало: ${_date(_start)}'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        _deadline != null && !_deadline!.isBefore(_start)
                        ? _deadline!
                        : _start,
                    firstDate: _start,
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) setState(() => _deadline = date);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _deadline == null ? 'Выбрать дедлайн' : _date(_deadline!),
                ),
              ),
              if (_deadline != null)
                IconButton(
                  tooltip: 'Убрать дедлайн',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_deadline != null && _deadline!.isBefore(_start))
            const Text(
              'Дедлайн раньше даты начала',
              style: TextStyle(color: Colors.red),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _deadline != null && _deadline!.isBefore(_start)
            ? null
            : () => Navigator.pop(
                context,
                NoteTaskOptions(
                  _projectId,
                  _status,
                  _priority,
                  _date(_start),
                  _deadline == null ? null : _date(_deadline!),
                ),
              ),
        child: const Text('Создать задачу'),
      ),
    ],
  );
}
