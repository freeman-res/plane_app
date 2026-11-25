import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../projects/project.dart';
import '../projects/project_dialog.dart';
import '../notes/notes_page.dart';
import '../schedule/schedule_dialog.dart';
import '../schedule/schedule_entry.dart';
import '../schedule/schedule_page.dart';
import 'calendar_month.dart';
import 'task_calendar.dart';
import 'task.dart';
import 'task_dialog.dart';
import 'task_matrix_board.dart';
import 'task_moscow_board.dart';

const _ink = Color(0xFF1A2B47);
const _muted = Color(0xFF7B8BA2);
const _blue = Color(0xFF3267D5);
const _line = Color(0xFFE4EAF2);
const _navy = Color(0xFF172B49);
const _navMuted = Color(0xFF9CADC6);

enum _TaskView { board, list, matrix, moscow, calendar }

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _api = ApiClient();
  final _search = TextEditingController();
  List<Task> _tasks = [];
  List<Task>? _filteredTasks;
  List<Project> _projects = [];
  int? _selectedProjectId;
  bool _notesMode = false;
  bool _scheduleMode = false;
  bool _showSchedule = false;
  int? _notesTaskId;
  _TaskView _view = _TaskView.board;
  String? _sortBy;
  bool _descending = false;
  String? _statusFilter;
  String? _priorityFilter;
  String? _tagFilter;
  bool _overdueOnly = false;
  int _taskRequest = 0;
  Timer? _midnightRefresh;
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int? _selectedDay = DateTime.now().day;
  CalendarMonth? _calendar;
  bool _calendarLoading = false;
  String? _calendarError;
  int _calendarRequest = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _scheduleMidnightRefresh();
    _loadTasks();
  }

  void _scheduleMidnightRefresh() {
    _midnightRefresh?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).add(const Duration(seconds: 2));
    _midnightRefresh = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      _refresh();
      _scheduleMidnightRefresh();
    });
  }

  void _onSearchChanged() => setState(() {});

  bool get _hasFilters =>
      _statusFilter != null ||
      _priorityFilter != null ||
      _tagFilter != null ||
      _overdueOnly;

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _midnightRefresh?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final request = ++_taskRequest;
    final projectId = _selectedProjectId;
    final status = _statusFilter;
    final priority = _priorityFilter;
    final tag = _tagFilter;
    final overdue = _overdueOnly;
    final sortBy = _sortBy;
    final descending = _descending;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _api.getProjects();
      final tasks = await _api.getTasks(sortBy: sortBy, descending: descending);
      List<Task>? filtered;
      if (status != null || priority != null || tag != null || overdue) {
        final selectedProject = projectId != null && projectId > 0
            ? projectId
            : null;
        filtered =
            overdue &&
                status == null &&
                priority == null &&
                tag == null &&
                sortBy == null
            ? await _api.getOverdueTasks(projectId: selectedProject)
            : await _api.getTasks(
                projectId: selectedProject,
                sortBy: sortBy,
                descending: descending,
                status: status,
                priority: priority,
                tag: tag,
                overdue: overdue ? true : null,
              );
      }
      if (mounted && request == _taskRequest) {
        setState(() {
          _projects = projects;
          _tasks = tasks;
          _filteredTasks = filtered;
        });
      }
    } catch (error) {
      if (mounted && request == _taskRequest) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _taskRequest) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadCalendar() async {
    final request = ++_calendarRequest;
    final month = _displayMonth;
    final projectId = _selectedProjectId;
    final showSchedule = _showSchedule;
    setState(() {
      _calendarLoading = true;
      _calendarError = null;
    });
    try {
      final calendar = await _api.getCalendar(
        year: month.year,
        month: month.month,
        projectId: projectId != null && projectId > 0 ? projectId : null,
        includeSchedule: showSchedule,
      );
      if (mounted &&
          request == _calendarRequest &&
          _displayMonth.year == month.year &&
          _displayMonth.month == month.month &&
          _selectedProjectId == projectId &&
          _showSchedule == showSchedule) {
        setState(() => _calendar = calendar);
      }
    } catch (error) {
      if (mounted && request == _calendarRequest) {
        setState(() => _calendarError = error.toString());
      }
    } finally {
      if (mounted && request == _calendarRequest) {
        setState(() => _calendarLoading = false);
      }
    }
  }

  void _changeMonth(DateTime month) {
    final today = DateTime.now();
    setState(() {
      _displayMonth = DateTime(month.year, month.month);
      _selectedDay = month.year == today.year && month.month == today.month
          ? today.day
          : null;
      _calendar = null;
    });
    _loadCalendar();
  }

  void _changeSort(String? sortBy) {
    setState(() => _sortBy = sortBy);
    _loadTasks();
  }

  void _changeFilters({
    String? status,
    String? priority,
    String? tag,
    bool? overdue,
    bool changeStatus = false,
    bool changePriority = false,
    bool changeTag = false,
  }) {
    setState(() {
      if (changeStatus) _statusFilter = status;
      if (changePriority) _priorityFilter = priority;
      if (changeTag) _tagFilter = tag;
      if (overdue != null) _overdueOnly = overdue;
    });
    _loadTasks();
  }

  void _changeView(_TaskView view) {
    setState(() => _view = view);
    if (view == _TaskView.calendar) _loadCalendar();
  }

  Future<void> _moveTaskInMatrix(Task task, String quadrant) async {
    await _perform(() async {
      await _api.moveTaskInMatrix(
        task,
        important:
            quadrant == 'urgent_important' ||
            quadrant == 'not_urgent_important',
        urgent: quadrant.startsWith('urgent_'),
      );
    });
  }

  Future<void> _setMoscow(Task task, String category) async {
    await _perform(() async {
      await _api.setMoscow(task.id, category == 'unassigned' ? null : category);
    });
  }

  Future<void> _refresh() async {
    await _loadTasks();
    if (mounted && _view == _TaskView.calendar) await _loadCalendar();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) {
        await _loadTasks();
        if (mounted && _view == _TaskView.calendar) await _loadCalendar();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createTask({String status = 'todo'}) async {
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (context) => TaskDialog(
        projects: _projects,
        selectedProjectId: _selectedProjectId != null && _selectedProjectId! > 0
            ? _selectedProjectId
            : null,
        selectedStatus: status,
      ),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await _api.createTask(
        draft.title,
        draft.description,
        projectId: draft.projectId,
        startDate: draft.startDate,
        status: draft.status,
        deadline: draft.deadline,
        priority: draft.priority,
        urgent: draft.urgent,
        moscow: draft.moscow,
        tags: draft.tags,
      );
    });
  }

  Future<void> _editTask(Task task) async {
    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (context) => TaskDialog(task: task, projects: _projects),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await _api.editTask(
        task.id,
        draft.title,
        draft.description,
        projectId: draft.projectId,
        startDate: draft.startDate,
        status: draft.status,
        deadline: draft.deadline,
        updateDeadline: true,
        priority: draft.priority,
        urgent: draft.urgent,
        updateUrgent: true,
        moscow: draft.moscow,
        updateMoscow: true,
        tags: draft.tags,
      );
    });
  }

  Future<void> _createProject() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const ProjectDialog(),
    );
    if (name == null || !mounted) return;
    int? createdId;
    await _perform(() async {
      createdId = (await _api.createProject(name)).id;
    });
    if (mounted && _projects.any((project) => project.id == createdId)) {
      setState(() => _selectedProjectId = createdId);
    }
  }

  Future<void> _deleteProject(Project project) async {
    final taskCount = _tasks
        .where((task) => task.projectId == project.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text(
          'Проект «${project.name}» будет удалён. '
          'Задачи ($taskCount) останутся в списке «Без проекта».',
        ),
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
    await _perform(() async {
      await _api.deleteProject(project.id);
      if (mounted && _selectedProjectId == project.id) {
        setState(() => _selectedProjectId = null);
      }
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

  Future<void> _setStatus(Task task, String status) async {
    if (task.status == status) return;
    await _perform(() => _api.updateStatus(task.id, status));
  }

  Future<void> _reschedule(Task task) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = DateTime.tryParse(task.startDate ?? '') ?? today;
    final earliest = start.isAfter(today) ? start : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: earliest,
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    final date =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    await _perform(() => _api.updateDeadline(task.id, date));
  }

  void _openOverdue(bool drawer) {
    setState(() {
      _notesMode = false;
      _scheduleMode = false;
      _selectedProjectId = null;
      _overdueOnly = true;
      _statusFilter = null;
      _priorityFilter = null;
      _tagFilter = null;
      _view = _TaskView.list;
    });
    _loadTasks();
    if (drawer) Navigator.of(context).pop();
  }

  void _selectProject(int? id, bool drawer) {
    setState(() {
      _notesMode = false;
      _scheduleMode = false;
      _selectedProjectId = id;
      _overdueOnly = false;
      if (_view == _TaskView.calendar) _calendar = null;
    });
    if (_hasFilters) _loadTasks();
    if (_view == _TaskView.calendar) _loadCalendar();
    if (drawer) Navigator.of(context).pop();
  }

  void _openNotes(bool drawer) {
    setState(() {
      _notesMode = true;
      _scheduleMode = false;
      _notesTaskId = null;
    });
    if (drawer) Navigator.of(context).pop();
  }

  void _openTaskNotes(Task task) {
    setState(() {
      _notesMode = true;
      _scheduleMode = false;
      _notesTaskId = task.id;
    });
  }

  void _openSchedule(bool drawer) {
    setState(() {
      _notesMode = false;
      _scheduleMode = true;
    });
    if (drawer) Navigator.of(context).pop();
  }

  void _openScheduleCalendar() {
    setState(() {
      _scheduleMode = false;
      _view = _TaskView.calendar;
      _showSchedule = true;
    });
    _loadCalendar();
  }

  void _toggleSchedule(bool enabled) {
    setState(() {
      _showSchedule = enabled;
      _calendar = null;
    });
    _loadCalendar();
  }

  Future<void> _createSchedule() async {
    final initialDate = _selectedDay == null
        ? DateTime(_displayMonth.year, _displayMonth.month, 1)
        : DateTime(_displayMonth.year, _displayMonth.month, _selectedDay!);
    final draft = await showDialog<ScheduleDraft>(
      context: context,
      builder: (context) => ScheduleDialog(
        projects: _projects,
        projectId: _selectedProjectId != null && _selectedProjectId! > 0
            ? _selectedProjectId
            : null,
        initialDate: initialDate,
      ),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await _api.createSchedule(draft);
    });
  }

  Future<void> _cancelOccurrence(ScheduleOccurrence occurrence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить занятие?'),
        content: Text(
          '«${occurrence.title}» ${occurrence.date} будет отменено. '
          'Остальные занятия в серии останутся. '
          'Восстановить дату можно в разделе «Расписание».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить занятие'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      await _api.skipScheduleDate(occurrence.scheduleId, occurrence.date);
    });
  }

  List<Task> get _visibleTasks {
    final query = _search.text.trim().toLowerCase();
    return (_hasFilters ? _filteredTasks ?? const <Task>[] : _tasks).where((
      task,
    ) {
      final matchesProject =
          _selectedProjectId == null ||
          (_selectedProjectId == -1
              ? task.projectId == null
              : task.projectId == _selectedProjectId);
      return matchesProject &&
          (query.isEmpty ||
              task.title.toLowerCase().contains(query) ||
              task.description.toLowerCase().contains(query) ||
              task.tags.any((tag) => tag.toLowerCase().contains(query)));
    }).toList();
  }

  Map<int, List<Task>> get _calendarTasksByDay {
    final result = <int, List<Task>>{};
    final query = _search.text.trim().toLowerCase();
    for (final day in _calendar?.days ?? const <CalendarDay>[]) {
      final date = DateTime.tryParse(day.date);
      if (date == null) continue;
      result[date.day] = day.tasks.where((task) {
        return (_selectedProjectId != -1 || task.projectId == null) &&
            (_statusFilter == null || task.status == _statusFilter) &&
            (_priorityFilter == null || task.priority == _priorityFilter) &&
            (_tagFilter == null ||
                task.tags.any(
                  (tag) => tag.toLowerCase() == _tagFilter!.toLowerCase(),
                )) &&
            (!_overdueOnly || task.isOverdue) &&
            (query.isEmpty ||
                task.title.toLowerCase().contains(query) ||
                task.description.toLowerCase().contains(query) ||
                task.tags.any((tag) => tag.toLowerCase().contains(query)));
      }).toList();
    }
    return result;
  }

  Map<int, List<ScheduleOccurrence>> get _calendarScheduleByDay {
    final result = <int, List<ScheduleOccurrence>>{};
    if (!_showSchedule) return result;
    for (final day in _calendar?.days ?? const <CalendarDay>[]) {
      final date = DateTime.tryParse(day.date);
      if (date == null) continue;
      result[date.day] = day.schedule
          .where((item) => _selectedProjectId != -1 || item.projectId == null)
          .toList();
    }
    return result;
  }

  List<String> get _availableTags {
    final names = <String, String>{};
    for (final task in _tasks) {
      for (final tag in task.tags) {
        names.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    if (_tagFilter != null) {
      names.putIfAbsent(_tagFilter!.toLowerCase(), () => _tagFilter!);
    }
    return names.values.toList()..sort(
      (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
    );
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _priorityFilter = null;
      _tagFilter = null;
      _overdueOnly = false;
    });
    _loadTasks();
  }

  String get _pageTitle {
    if (_overdueOnly && _selectedProjectId == null) return 'Просрочено';
    if (_selectedProjectId == null) return 'Все задачи';
    if (_selectedProjectId == -1) return 'Без проекта';
    for (final project in _projects) {
      if (project.id == _selectedProjectId) return project.name;
    }
    return 'Все задачи';
  }

  Widget _sidebar(bool drawer) {
    return Container(
      width: 252,
      color: _navy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 22, 15, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5D91FF), Color(0xFF416DD9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'WorkNotes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 42),
              const Text(
                'РАБОЧЕЕ ПРОСТРАНСТВО',
                style: TextStyle(
                  color: _navMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              _navigationRow(
                'Все задачи',
                Icons.grid_view_rounded,
                !_notesMode &&
                    !_scheduleMode &&
                    _selectedProjectId == null &&
                    !_overdueOnly,
                _tasks.length,
                () => _selectProject(null, drawer),
              ),
              _navigationRow(
                'Просрочено',
                Icons.warning_amber_rounded,
                !_notesMode &&
                    !_scheduleMode &&
                    _overdueOnly &&
                    _selectedProjectId == null,
                _tasks.where((task) => task.isOverdue).length,
                () => _openOverdue(drawer),
              ),
              _navigationRow(
                'Без проекта',
                Icons.inbox_outlined,
                !_notesMode && !_scheduleMode && _selectedProjectId == -1,
                _tasks.where((task) => task.projectId == null).length,
                () => _selectProject(-1, drawer),
              ),
              _navigationRow(
                'Заметки',
                Icons.sticky_note_2_outlined,
                _notesMode,
                null,
                () => _openNotes(drawer),
              ),
              _navigationRow(
                'Расписание',
                Icons.event_note_outlined,
                _scheduleMode,
                null,
                () => _openSchedule(drawer),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ПРОЕКТЫ',
                      style: TextStyle(
                        color: _navMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Новый проект',
                    onPressed: _saving ? null : _createProject,
                    icon: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF78ACFF),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _projects.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: Text(
                          'Здесь появятся ваши проекты',
                          style: TextStyle(color: _navMuted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _projects.length,
                        itemBuilder: (context, index) {
                          final project = _projects[index];
                          return _navigationRow(
                            project.name,
                            Icons.folder_outlined,
                            !_notesMode &&
                                !_scheduleMode &&
                                _selectedProjectId == project.id,
                            _tasks
                                .where((task) => task.projectId == project.id)
                                .length,
                            () => _selectProject(project.id, drawer),
                            accent: _projectAccent(project.id),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Действия с проектом',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: _navMuted,
                              ),
                              onSelected: (value) {
                                if (value == 'delete') _deleteProject(project);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить проект'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(color: Color(0xFF344B6A)),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Место для ваших идей и дел',
                  style: TextStyle(color: _navMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _projectAccent(int id) => const [
    Color(0xFF6EA9FF),
    Color(0xFFFFBC70),
    Color(0xFF73D4B7),
    Color(0xFFD09DF3),
    Color(0xFFFF8FA4),
  ][id.abs() % 5];

  Widget _navigationRow(
    String title,
    IconData icon,
    bool selected,
    int? count,
    VoidCallback onTap, {
    Widget? trailing,
    Color? accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFF294C7C) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 43,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(
                  icon,
                  size: 19,
                  color:
                      accent ??
                      (selected ? const Color(0xFF87B5FF) : _navMuted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFDCE6F4),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3B6094)
                          : const Color(0xFF243B5B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Color(0xFFC7D7EB),
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (trailing != null) trailing,
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityColor(String priority) => switch (priority) {
    'high' => const Color(0xFFDA5262),
    'low' => const Color(0xFF358E83),
    _ => const Color(0xFFB77925),
  };

  String _priorityLabel(String priority) => switch (priority) {
    'high' => 'Высокий',
    'low' => 'Низкий',
    _ => 'Средний',
  };

  String _statusLabel(String status) => switch (status) {
    'in_progress' => 'В работе',
    'done' => 'Готово',
    _ => 'Сделать',
  };

  Widget _tag(IconData icon, String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(Task task) {
    final project = _projects.where((item) => item.id == task.projectId);
    final started = DateTime.tryParse(task.startDate ?? '');
    final due = DateTime.tryParse(task.deadline ?? '');
    final today = DateTime.now();
    final overdue =
        due != null &&
        !task.isDone &&
        DateTime(
          due.year,
          due.month,
          due.day,
        ).isBefore(DateTime(today.year, today.month, today.day));
    final dueLabel = due == null
        ? null
        : '${due.day.toString().padLeft(2, '0')}.'
              '${due.month.toString().padLeft(2, '0')}.'
              '${due.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 12, 7, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09263C63),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsets.only(top: 8, right: 4),
            decoration: BoxDecoration(
              color: task.isDone
                  ? const Color(0xFF52B99A)
                  : _priorityColor(task.priority),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Checkbox(
            value: task.isDone,
            onChanged: _saving
                ? null
                : (_) => _setStatus(task, task.isDone ? 'todo' : 'done'),
          ),
          Expanded(
            child: InkWell(
              onTap: _saving ? null : () => _editTask(task),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        color: task.isDone ? _muted : _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        decoration: task.isDone
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        task.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 7,
                      children: [
                        if (task.isOverdue)
                          _tag(
                            Icons.warning_amber_rounded,
                            'Просрочено',
                            const Color(0xFFCD4354),
                            const Color(0xFFFFECEF),
                          ),
                        if (started != null)
                          _tag(
                            Icons.play_arrow_rounded,
                            'С ${started.day.toString().padLeft(2, '0')}.'
                            '${started.month.toString().padLeft(2, '0')}.'
                            '${started.year}',
                            _muted,
                            const Color(0xFFF0F3F8),
                          ),
                        _tag(
                          Icons.flag_outlined,
                          _priorityLabel(task.priority),
                          _priorityColor(task.priority),
                          _priorityColor(task.priority).withValues(alpha: 0.10),
                        ),
                        if (dueLabel != null)
                          _tag(
                            Icons.calendar_today_outlined,
                            overdue ? 'Просрочено · $dueLabel' : dueLabel,
                            overdue ? const Color(0xFFDA5262) : _muted,
                            overdue
                                ? const Color(0xFFFFECEF)
                                : const Color(0xFFF0F3F8),
                          ),
                        if (project.isNotEmpty)
                          _tag(
                            Icons.folder_outlined,
                            project.first.name,
                            _blue,
                            const Color(0xFFEDF2FF),
                          ),
                        for (final tag in task.tags)
                          _tag(
                            Icons.sell_outlined,
                            tag,
                            const Color(0xFF6558A6),
                            const Color(0xFFF2EFFF),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    PopupMenuButton<String>(
                      tooltip: 'Изменить статус',
                      enabled: !_saving,
                      onSelected: (value) => _setStatus(task, value),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'todo', child: Text('Сделать')),
                        PopupMenuItem(
                          value: 'in_progress',
                          child: Text('В работе'),
                        ),
                        PopupMenuItem(value: 'done', child: Text('Готово')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _statusLabel(task.status),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: _muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (task.isOverdue) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: _saving ? null : () => _reschedule(task),
                            icon: const Icon(Icons.event_repeat, size: 16),
                            label: const Text('Перенести срок'),
                          ),
                          TextButton.icon(
                            onPressed: _saving ? null : () => _deleteTask(task),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Удалить'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия с задачей',
            icon: const Icon(Icons.more_horiz_rounded, color: _muted),
            onSelected: (value) {
              if (value == 'edit') _editTask(task);
              if (value == 'notes') _openTaskNotes(task);
              if (value == 'delete') _deleteTask(task);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Редактировать')),
              PopupMenuItem(value: 'notes', child: Text('Заметки задачи')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boardColumn(
    String title,
    String status,
    List<Task> tasks,
    Color accent,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FB),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(11, 5, 4, 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 5, backgroundColor: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Добавить задачу в «$title»',
                    onPressed: _saving
                        ? null
                        : () => _createTask(status: status),
                    icon: Icon(Icons.add_rounded, color: accent, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              SizedBox(
                height: 180,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 28,
                      color: accent.withValues(alpha: 0.65),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Здесь пока пусто',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            for (final task in tasks) _taskCard(task),
          ],
        ),
      ),
    );
  }

  Widget _viewSelector() => SegmentedButton<_TaskView>(
    showSelectedIcon: false,
    style: ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      ),
      side: const WidgetStatePropertyAll(BorderSide(color: _line)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFFEAF0FF)
            : Colors.white,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _blue : _muted,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    segments: const [
      ButtonSegment(
        value: _TaskView.board,
        icon: Icon(Icons.view_kanban_outlined),
        label: Text('Доска'),
      ),
      ButtonSegment(
        value: _TaskView.list,
        icon: Icon(Icons.view_list_rounded),
        label: Text('Список'),
      ),
      ButtonSegment(
        value: _TaskView.matrix,
        icon: Icon(Icons.grid_4x4_outlined),
        label: Text('Матрица'),
      ),
      ButtonSegment(
        value: _TaskView.moscow,
        icon: Icon(Icons.category_outlined),
        label: Text('MoSCoW'),
      ),
      ButtonSegment(
        value: _TaskView.calendar,
        icon: Icon(Icons.calendar_month_outlined),
        label: Text('Календарь'),
      ),
    ],
    selected: {_view},
    onSelectionChanged: (value) => _changeView(value.first),
  );

  Widget _content(double width, bool mobile) {
    final tasks = _visibleTasks;
    final done = tasks.where((task) => task.isDone).toList();
    final pending = tasks.where((task) => task.status == 'todo').toList();
    final inProgress = tasks
        .where((task) => task.status == 'in_progress')
        .toList();
    final padding = mobile ? 18.0 : 32.0;
    final available = width - 2 * padding;
    final toolbarWidth = available - 32;
    final columnWidth = mobile
        ? 300.0
        : ((available - 32) / 3).clamp(290.0, 480.0);

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(padding, 26, padding, 32),
            children: [
              if (mobile)
                Builder(
                  builder: (context) => Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Открыть проекты',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'РАБОЧЕЕ ПРОСТРАНСТВО  /  ${_pageTitle.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                _pageTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: mobile ? 27 : 34,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${tasks.length} задач · ${done.length} выполнено',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: mobile ? toolbarWidth : 300,
                          child: TextField(
                            controller: _search,
                            decoration: const InputDecoration(
                              hintText: 'Поиск задач',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: mobile
                              ? toolbarWidth
                              : (toolbarWidth < 620 ? toolbarWidth : 620.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _viewSelector(),
                          ),
                        ),
                        if (_view != _TaskView.calendar)
                          SizedBox(
                            width: 195,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_sortBy),
                              initialValue: _sortBy ?? 'none',
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Сортировка',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('По умолчанию'),
                                ),
                                DropdownMenuItem(
                                  value: 'priority',
                                  child: Text('По приоритету'),
                                ),
                                DropdownMenuItem(
                                  value: 'deadline',
                                  child: Text('По дедлайну'),
                                ),
                              ],
                              onChanged: _loading
                                  ? null
                                  : (value) => _changeSort(
                                      value == 'none' ? null : value,
                                    ),
                            ),
                          ),
                        if (_view != _TaskView.calendar)
                          IconButton(
                            tooltip: _descending
                                ? 'Обратный порядок'
                                : 'Основной порядок',
                            onPressed: _sortBy == null || _loading
                                ? null
                                : () {
                                    setState(() => _descending = !_descending);
                                    _loadTasks();
                                  },
                            icon: Icon(
                              _descending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _createTask,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Новая задача'),
                        ),
                        if (_view == _TaskView.calendar) ...[
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _createSchedule,
                            icon: const Icon(Icons.event_note_outlined),
                            label: const Text('Добавить занятие'),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Показывать расписание'),
                              const SizedBox(width: 5),
                              Switch(
                                value: _showSchedule,
                                onChanged: _calendarLoading
                                    ? null
                                    : _toggleSchedule,
                              ),
                            ],
                          ),
                        ],
                        IconButton(
                          tooltip: 'Обновить',
                          onPressed: _loading || _saving ? null : _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 158,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('status-\$_statusFilter'),
                            initialValue: _statusFilter ?? 'all',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Статус',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('Все'),
                              ),
                              DropdownMenuItem(
                                value: 'todo',
                                child: Text('Сделать'),
                              ),
                              DropdownMenuItem(
                                value: 'in_progress',
                                child: Text('В работе'),
                              ),
                              DropdownMenuItem(
                                value: 'done',
                                child: Text('Готово'),
                              ),
                            ],
                            onChanged: _loading
                                ? null
                                : (value) => _changeFilters(
                                    status: value == 'all' ? null : value,
                                    changeStatus: true,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: 158,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('priority-\$_priorityFilter'),
                            initialValue: _priorityFilter ?? 'all',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Приоритет',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('Все'),
                              ),
                              DropdownMenuItem(
                                value: 'high',
                                child: Text('Высокий'),
                              ),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('Средний'),
                              ),
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Низкий'),
                              ),
                            ],
                            onChanged: _loading
                                ? null
                                : (value) => _changeFilters(
                                    priority: value == 'all' ? null : value,
                                    changePriority: true,
                                  ),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('tag-\$_tagFilter'),
                            initialValue: _tagFilter ?? '',
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Тег'),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Все теги'),
                              ),
                              for (final tag in _availableTags)
                                DropdownMenuItem(value: tag, child: Text(tag)),
                            ],
                            onChanged: _loading
                                ? null
                                : (value) => _changeFilters(
                                    tag: value == '' ? null : value,
                                    changeTag: true,
                                  ),
                          ),
                        ),
                        FilterChip(
                          label: const Text('Просроченные'),
                          avatar: const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                          ),
                          selected: _overdueOnly,
                          onSelected: _loading
                              ? null
                              : (value) => _changeFilters(overdue: value),
                        ),
                        if (_hasFilters)
                          TextButton(
                            onPressed: _loading ? null : _clearFilters,
                            child: const Text('Сбросить фильтры'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_view == _TaskView.list && !_loading && tasks.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 60,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.task_alt_rounded,
                        color: _blue,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _search.text.isNotEmpty
                            ? 'По запросу ничего не найдено'
                            : 'Здесь пока нет задач',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_view == _TaskView.board)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _boardColumn(
                        'Сделать',
                        'todo',
                        pending,
                        const Color(0xFF5E83F5),
                        columnWidth,
                      ),
                      const SizedBox(width: 16),
                      _boardColumn(
                        'В работе',
                        'in_progress',
                        inProgress,
                        const Color(0xFFEAAC56),
                        columnWidth,
                      ),
                      const SizedBox(width: 16),
                      _boardColumn(
                        'Готово',
                        'done',
                        done,
                        const Color(0xFF38B990),
                        columnWidth,
                      ),
                    ],
                  ),
                )
              else if (_view == _TaskView.matrix)
                TaskMatrixBoard(
                  tasks: tasks,
                  taskBuilder: _taskCard,
                  onMove: _moveTaskInMatrix,
                )
              else if (_view == _TaskView.moscow)
                TaskMoscowBoard(
                  tasks: tasks,
                  taskBuilder: _taskCard,
                  onMove: _setMoscow,
                )
              else if (_view == _TaskView.calendar)
                TaskCalendar(
                  month: _displayMonth,
                  tasksByDay: _calendarTasksByDay,
                  scheduleByDay: _calendarScheduleByDay,
                  showSchedule: _showSchedule,
                  selectedDay: _selectedDay,
                  mobile: mobile,
                  loading: _calendarLoading,
                  error: _calendarError,
                  onMonthChanged: _changeMonth,
                  onDaySelected: (day) => setState(() => _selectedDay = day),
                  onRetry: _loadCalendar,
                  taskBuilder: _taskCard,
                  onCancelOccurrence: _cancelOccurrence,
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    children: [for (final task in tasks) _taskCard(task)],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 800;
        return Scaffold(
          drawer: mobile ? Drawer(width: 252, child: _sidebar(true)) : null,
          body: Row(
            children: [
              if (!mobile) _sidebar(false),
              Expanded(
                child: _scheduleMode
                    ? SchedulePage(
                        api: _api,
                        projects: _projects,
                        onChanged: () {
                          if (_showSchedule) _loadCalendar();
                        },
                        onShowCalendar: _openScheduleCalendar,
                        showMenu: mobile,
                        selectedProjectId:
                            _selectedProjectId != null &&
                                _selectedProjectId! > 0
                            ? _selectedProjectId
                            : null,
                      )
                    : _notesMode
                    ? NotesPage(
                        api: _api,
                        projects: _projects,
                        tasks: _tasks,
                        onTasksChanged: _loadTasks,
                        showMenu: mobile,
                        taskId: _notesTaskId,
                        onClearTask: () => setState(() => _notesTaskId = null),
                      )
                    : _content(
                        mobile
                            ? constraints.maxWidth
                            : constraints.maxWidth - 252,
                        mobile,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
