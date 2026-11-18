import 'package:material_ui/material_ui.dart';

import '../projects/project.dart';
import 'task.dart';

class TaskDraft {
  const TaskDraft(this.title, this.description, this.projectId);

  final String title;
  final String description;
  final int? projectId;
}

class TaskDialog extends StatefulWidget {
  const TaskDialog({
    super.key,
    this.task,
    this.projects = const [],
    this.selectedProjectId,
  });

  final Task? task;
  final List<Project> projects;
  final int? selectedProjectId;

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _projectId;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.task?.title ?? '';
    _descriptionController.text = widget.task?.description ?? '';
    _projectId = widget.task == null
        ? widget.selectedProjectId
        : widget.task!.projectId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TaskDraft(
        _titleController.text.trim(),
        _descriptionController.text.trim(),
        _projectId,
      ),
    );
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
