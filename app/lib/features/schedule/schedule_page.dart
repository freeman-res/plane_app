import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../projects/project.dart';
import 'schedule_dialog.dart';
import 'schedule_entry.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.api,
    required this.projects,
    required this.onChanged,
    required this.onShowCalendar,
    this.showMenu = false,
    this.selectedProjectId,
  });

  final ApiClient api;
  final List<Project> projects;
  final VoidCallback onChanged;
  final VoidCallback onShowCalendar;
  final bool showMenu;
  final int? selectedProjectId;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<ScheduleEntry> _entries = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.api.getSchedule();
      if (mounted) setState(() => _entries = entries);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        await _load();
        widget.onChanged();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([ScheduleEntry? entry]) async {
    final draft = await showDialog<ScheduleDraft>(
      context: context,
      builder: (context) => ScheduleDialog(
        entry: entry,
        projects: widget.projects,
        projectId: widget.selectedProjectId,
      ),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      if (entry == null) {
        await widget.api.createSchedule(draft);
      } else {
        await widget.api.updateSchedule(entry.id, draft);
      }
    });
  }

  Future<void> _delete(ScheduleEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить занятие?'),
        content: Text(
          '«${entry.title}» и вся его серия будут удалены из расписания.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() => widget.api.deleteSchedule(entry.id));
  }

  Future<void> _restore(ScheduleEntry entry, String date) async {
    await _perform(() async {
      await widget.api.restoreScheduleDate(entry.id, date);
    });
  }

  String _repeatLabel(int value) => switch (value) {
    0 => 'Одно занятие',
    2 => 'Раз в две недели',
    _ => 'Каждую неделю',
  };

  String _projectLabel(int? id) {
    if (id == null) return 'Без проекта';
    for (final project in widget.projects) {
      if (project.id == id) return project.name;
    }
    return 'Проект #$id';
  }

  Widget _entryCard(ScheduleEntry entry) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat_outlined, color: Color(0xFF4269EF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Изменить занятие',
                onPressed: _saving ? null : () => _edit(entry),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Удалить серию',
                onPressed: _saving ? null : () => _delete(entry),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${scheduleTime(entry.startTime)}–${scheduleTime(entry.endTime)}  ·  '
            '${_repeatLabel(entry.repeatEveryWeeks)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'С ${entry.firstDate}${entry.endsOn == null ? '' : ' до ${entry.endsOn}'}'
            '  ·  ${_projectLabel(entry.projectId)}',
            style: const TextStyle(color: Color(0xFF78879C)),
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (entry.excludedDates.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Отменённые даты · нажмите ×, чтобы восстановить',
              style: TextStyle(fontSize: 12, color: Color(0xFF78879C)),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final date in entry.excludedDates)
                  InputChip(
                    label: Text(date),
                    onDeleted: _saving ? null : () => _restore(entry, date),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_loading || _saving) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
            children: [
              if (widget.showMenu)
                Builder(
                  builder: (context) => Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Разделы приложения',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Расписание',
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF192B45),
                        ),
                      ),
                      Text(
                        'Занятия и повторения по неделям',
                        style: TextStyle(color: Color(0xFF78879C)),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onShowCalendar,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Открыть календарь'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить занятие'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(child: Text(_error!)),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_loading && _entries.isEmpty && _error == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 58,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE7ECF4)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 46,
                        color: Color(0xFF4269EF),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Занятий пока нет',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text('Добавьте разовое или повторяющееся занятие.'),
                    ],
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 870),
                child: Column(
                  children: [for (final entry in _entries) _entryCard(entry)],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
