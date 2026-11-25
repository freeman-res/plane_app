import 'package:material_ui/material_ui.dart';

import '../projects/project.dart';
import 'schedule_entry.dart';

class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({
    super.key,
    required this.projects,
    this.entry,
    this.projectId,
    this.initialDate,
  });

  final List<Project> projects;
  final ScheduleEntry? entry;
  final int? projectId;
  final DateTime? initialDate;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late DateTime _firstDate;
  DateTime? _endsOn;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _repeat;
  int? _projectId;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _title.text = entry?.title ?? '';
    _description.text = entry?.description ?? '';
    _firstDate =
        DateTime.tryParse(entry?.firstDate ?? '') ??
        widget.initialDate ??
        DateUtils.dateOnly(DateTime.now());
    _endsOn = DateTime.tryParse(entry?.endsOn ?? '');
    _startTime = _parseTime(
      entry?.startTime,
      const TimeOfDay(hour: 10, minute: 0),
    );
    _endTime = _parseTime(entry?.endTime, const TimeOfDay(hour: 11, minute: 0));
    _repeat = entry?.repeatEveryWeeks ?? 1;
    _projectId = entry?.projectId ?? widget.projectId;
  }

  TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    if (value == null || value.length < 5) return fallback;
    final hour = int.tryParse(value.substring(0, 2));
    final minute = int.tryParse(value.substring(3, 5));
    if (hour == null || minute == null) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _time(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _chooseDate({required bool end}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: end
          ? (_endsOn != null && !_endsOn!.isBefore(_firstDate)
                ? _endsOn!
                : _firstDate)
          : _firstDate,
      firstDate: end ? _firstDate : DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (end) {
        _endsOn = date;
      } else {
        _firstDate = date;
      }
      _dateError = null;
    });
  }

  Future<void> _chooseTime({required bool end}) async {
    final time = await showTimePicker(
      context: context,
      initialTime: end ? _endTime : _startTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (end) {
        _endTime = time;
      } else {
        _startTime = time;
      }
      _dateError = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_endsOn != null && _endsOn!.isBefore(_firstDate)) {
      setState(() => _dateError = 'Конец серии раньше первого занятия');
      return;
    }
    if (_startTime.hour * 60 + _startTime.minute >=
        _endTime.hour * 60 + _endTime.minute) {
      setState(() => _dateError = 'Время окончания должно быть позже начала');
      return;
    }
    Navigator.pop(
      context,
      ScheduleDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        projectId: _projectId,
        firstDate: _date(_firstDate),
        endsOn: _repeat == 0 || _endsOn == null ? null : _date(_endsOn!),
        startTime: _time(_startTime),
        endTime: _time(_endTime),
        repeatEveryWeeks: _repeat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.entry == null ? 'Новое занятие' : 'Изменить занятие'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Название занятия'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _description,
              maxLines: 2,
              maxLength: 5000,
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
              ),
            ),
            const SizedBox(height: 10),
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
              onChanged: (value) =>
                  setState(() => _projectId = value == 0 ? null : value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _chooseDate(end: false),
              icon: const Icon(Icons.event_outlined),
              label: Text('Первое занятие: ${_displayDate(_firstDate)}'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(end: false),
                    icon: const Icon(Icons.access_time),
                    label: Text('С ${_time(_startTime)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(end: true),
                    icon: const Icon(Icons.access_time),
                    label: Text('До ${_time(_endTime)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: 'Повторять'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Один раз')),
                DropdownMenuItem(value: 1, child: Text('Каждую неделю')),
                DropdownMenuItem(value: 2, child: Text('Раз в две недели')),
              ],
              onChanged: (value) => setState(() => _repeat = value ?? _repeat),
            ),
            if (_repeat != 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chooseDate(end: true),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(
                        _endsOn == null
                            ? 'Без даты окончания'
                            : 'До ${_displayDate(_endsOn!)}',
                      ),
                    ),
                  ),
                  if (_endsOn != null)
                    IconButton(
                      tooltip: 'Без даты окончания',
                      onPressed: () => setState(() {
                        _endsOn = null;
                        _dateError = null;
                      }),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ],
            if (_repeat == 2)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Для чередования недель создайте второе занятие с первой датой через 7 дней.',
                  style: TextStyle(color: Color(0xFF78879C), fontSize: 12),
                ),
              ),
            if (widget.entry?.excludedDates.isNotEmpty ?? false)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'При изменении первой даты, повтора или конца серии отменённые даты сбросятся.',
                  style: TextStyle(color: Color(0xFFB77925), fontSize: 12),
                ),
              ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _dateError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.entry == null ? 'Добавить' : 'Сохранить'),
      ),
    ],
  );
}
