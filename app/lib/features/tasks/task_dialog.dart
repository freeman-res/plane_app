import 'package:material_ui/material_ui.dart';

import '../projects/project.dart';
import 'task.dart';

class TaskDraft {
  const TaskDraft(
    this.title,
    this.description,
    this.projectId, {
    required this.status,
    required this.priority,
    required this.urgent,
    required this.moscow,
    required this.startDate,
    required this.tags,
    this.deadline,
  });

  final String title;
  final String description;
  final int? projectId;
  final String status;
  final String priority;
  final bool? urgent;
  final String? moscow;
  final String startDate;
  final List<String> tags;
  final String? deadline;
}

class TaskDialog extends StatefulWidget {
  const TaskDialog({
    super.key,
    this.task,
    this.projects = const [],
    this.selectedProjectId,
    this.selectedStatus = 'todo',
  });

  final Task? task;
  final List<Project> projects;
  final int? selectedProjectId;
  final String selectedStatus;

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  int? _projectId;
  late String _status;
  late String _priority;
  late String _urgency;
  late String _moscow;
  late DateTime _startDate;
  DateTime? _deadline;
  bool _invalidDates = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.task?.title ?? '';
    _descriptionController.text = widget.task?.description ?? '';
    _tagsController.text = widget.task?.tags.join(', ') ?? '';
    _projectId = widget.task == null
        ? widget.selectedProjectId
        : widget.task!.projectId;
    _status = widget.task?.status ?? widget.selectedStatus;
    _priority = widget.task?.priority ?? 'medium';
    _moscow = widget.task?.moscow ?? 'unassigned';
    _urgency = switch (widget.task?.urgent) {
      true => 'urgent',
      false => 'not_urgent',
      null => 'auto',
    };
    _startDate =
        DateTime.tryParse(widget.task?.startDate ?? '') ??
        DateUtils.dateOnly(DateTime.now());
    _deadline = DateTime.tryParse(widget.task?.deadline ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_deadline != null && _deadline!.isBefore(_startDate)) {
      setState(() => _invalidDates = true);
      return;
    }
    Navigator.of(context).pop(
      TaskDraft(
        _titleController.text.trim(),
        _descriptionController.text.trim(),
        _projectId,
        status: _status,
        priority: _priority,
        urgent: switch (_urgency) {
          'urgent' => true,
          'not_urgent' => false,
          _ => null,
        },
        moscow: _moscow == 'unassigned' ? null : _moscow,
        startDate: _isoDate(_startDate),
        tags: _parseTags(),
        deadline: _deadline == null ? null : _isoDate(_deadline!),
      ),
    );
  }

  List<String> _parseTags() => _tagsController.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();

  String? _validateTags(String? value) {
    final tags = _parseTags();
    if (tags.length > 20) return 'Не больше 20 тегов';
    if (tags.any((tag) => tag.length > 32)) {
      return 'Название тега — не больше 32 символов';
    }
    final unique = tags.map((tag) => tag.toLowerCase()).toSet();
    if (unique.length != tags.length) return 'Уберите повторяющиеся теги';
    return null;
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.'
      '${date.year}';

  Future<void> _chooseStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        _startDate = selected;
        _invalidDates = false;
      });
    }
  }

  Future<void> _chooseDeadline() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _deadline != null && !_deadline!.isBefore(_startDate)
          ? _deadline!
          : _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() {
        _deadline = selected;
        _invalidDates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.task == null ? 'Новая задача' : 'Редактировать задачу',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Напиши название задачи'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Описание (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Теги',
                  hintText: 'Например: учёба, важно',
                  helperText: 'Разделяйте теги запятой',
                  prefixIcon: Icon(Icons.sell_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: _validateTags,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _projectId ?? 0,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Проект'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Без проекта')),
                  for (final project in widget.projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _projectId = value == 0 ? null : value;
                }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Статус'),
                items: const [
                  DropdownMenuItem(value: 'todo', child: Text('Сделать')),
                  DropdownMenuItem(
                    value: 'in_progress',
                    child: Text('В работе'),
                  ),
                  DropdownMenuItem(value: 'done', child: Text('Готово')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Приоритет'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Низкий')),
                  DropdownMenuItem(value: 'medium', child: Text('Средний')),
                  DropdownMenuItem(value: 'high', child: Text('Высокий')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _moscow,
                decoration: const InputDecoration(
                  labelText: 'MoSCoW для проекта',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'unassigned',
                    child: Text('Без категории'),
                  ),
                  DropdownMenuItem(
                    value: 'must',
                    child: Text('Must · обязательно'),
                  ),
                  DropdownMenuItem(
                    value: 'should',
                    child: Text('Should · важно'),
                  ),
                  DropdownMenuItem(
                    value: 'could',
                    child: Text('Could · желательно'),
                  ),
                  DropdownMenuItem(
                    value: 'wont',
                    child: Text('Won’t · отложено'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _moscow = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _urgency,
                decoration: const InputDecoration(
                  labelText: 'Срочность для матрицы',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text('По дедлайну (за 2 дня)'),
                  ),
                  DropdownMenuItem(value: 'urgent', child: Text('Срочно')),
                  DropdownMenuItem(
                    value: 'not_urgent',
                    child: Text('Не срочно'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _urgency = value);
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Сроки задачи',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _chooseStartDate,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('Начало: ${_displayDate(_startDate)}'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _chooseDeadline,
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(
                        _deadline == null
                            ? 'Добавить дедлайн'
                            : 'До ${_displayDate(_deadline!)}',
                      ),
                    ),
                  ),
                  if (_deadline != null)
                    IconButton(
                      tooltip: 'Убрать дедлайн',
                      onPressed: () => setState(() => _deadline = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              if (_invalidDates)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Дедлайн не может быть раньше даты начала',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}
