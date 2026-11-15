import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import 'task.dart';
import 'task_dialog.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _api = ApiClient();
  List<Task> _tasks = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _api.getTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) await _loadTasks();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createTask() async {
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (context) => const TaskDialog(),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await _api.createTask(draft.title, draft.description);
    });
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('«${task.title}» будет удалена из базы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() => _api.deleteTask(task.id));
  }

  Widget _taskCard(Task task) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: task.isDone,
              onChanged: _saving
                  ? null
                  : (_) {
                      _perform(() async {
                        await _api.updateStatus(
                          task.id,
                          task.isDone ? 'todo' : 'done',
                        );
                      });
                    },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: task.isDone ? colors.onSurfaceVariant : null,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Удалить задачу',
              onPressed: _saving ? null : () => _deleteTask(task),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tasks.where((task) => task.isDone).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkNotes'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading || _saving ? null : _loadTasks,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Задачи',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text('Всего: ${_tasks.length} · Выполнено: $completed'),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _saving ? null : _createTask,
                      icon: const Icon(Icons.add),
                      label: const Text('Новая задача'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: _loadTasks,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: _tasks.isEmpty && !_loading
                      ? Center(
                          child: Text(
                            _error == null
                                ? 'Задач пока нет. Создай первую.'
                                : 'Не удалось получить задачи.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _tasks.length,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _taskCard(_tasks[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
