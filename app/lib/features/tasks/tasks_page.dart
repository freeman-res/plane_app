import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../projects/project.dart';
import '../projects/project_dialog.dart';
import 'task.dart';
import 'task_dialog.dart';

const _ink = Color(0xFF192B45);
const _muted = Color(0xFF78879C);
const _blue = Color(0xFF4269EF);
const _line = Color(0xFFE7ECF4);

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _api = ApiClient();
  final _search = TextEditingController();
  List<Task> _tasks = [];
  List<Project> _projects = [];
  int? _selectedProjectId;
  bool _boardView = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _loadTasks();
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _api.getProjects();
      final tasks = await _api.getTasks();
      if (mounted) {
        setState(() {
          _projects = projects;
          _tasks = tasks;
        });
      }
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
      builder: (context) => TaskDialog(
        projects: _projects,
        selectedProjectId: _selectedProjectId != null && _selectedProjectId! > 0
            ? _selectedProjectId
            : null,
      ),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await _api.createTask(
        draft.title,
        draft.description,
        projectId: draft.projectId,
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

  void _selectProject(int? id, bool drawer) {
    setState(() => _selectedProjectId = id);
    if (drawer) Navigator.of(context).pop();
  }

  List<Task> get _visibleTasks {
    final query = _search.text.trim().toLowerCase();
    return _tasks.where((task) {
      final matchesProject =
          _selectedProjectId == null ||
          (_selectedProjectId == -1
              ? task.projectId == null
              : task.projectId == _selectedProjectId);
      return matchesProject &&
          (query.isEmpty ||
              task.title.toLowerCase().contains(query) ||
              task.description.toLowerCase().contains(query));
    }).toList();
  }

  String get _pageTitle {
    if (_selectedProjectId == null) return 'Все задачи';
    if (_selectedProjectId == -1) return 'Без проекта';
    for (final project in _projects) {
      if (project.id == _selectedProjectId) return project.name;
    }
    return 'Все задачи';
  }

  Widget _sidebar(bool drawer) {
    return Container(
      width: 260,
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'WorkNotes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 38),
              const Text(
                'РАБОЧЕЕ ПРОСТРАНСТВО',
                style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              _navigationRow(
                'Все задачи',
                Icons.grid_view_rounded,
                _selectedProjectId == null,
                _tasks.length,
                () => _selectProject(null, drawer),
              ),
              _navigationRow(
                'Без проекта',
                Icons.inbox_outlined,
                _selectedProjectId == -1,
                _tasks.where((task) => task.projectId == null).length,
                () => _selectProject(-1, drawer),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ПРОЕКТЫ',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Новый проект',
                    onPressed: _saving ? null : _createProject,
                    icon: const Icon(Icons.add_rounded, color: _blue),
                  ),
                ],
              ),
              Expanded(
                child: _projects.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: Text(
                          'Здесь появятся ваши проекты',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _projects.length,
                        itemBuilder: (context, index) {
                          final project = _projects[index];
                          return _navigationRow(
                            project.name,
                            Icons.folder_outlined,
                            _selectedProjectId == project.id,
                            _tasks
                                .where((task) => task.projectId == project.id)
                                .length,
                            () => _selectProject(project.id, drawer),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Действия с проектом',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
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
              const Divider(color: _line),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Место для ваших идей и дел',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationRow(
    String title,
    IconData icon,
    bool selected,
    int count,
    VoidCallback onTap, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFFEBF0FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(icon, size: 19, color: selected ? _blue : _muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _blue : _ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text('$count', style: const TextStyle(color: _muted)),
                if (trailing != null) trailing,
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskCard(Task task) {
    final project = _projects.where((item) => item.id == task.projectId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 12, 7, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A263C63),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: task.isDone,
            onChanged: _saving
                ? null
                : (_) => _perform(
                    () => _api.updateStatus(
                      task.id,
                      task.isDone ? 'todo' : 'done',
                    ),
                  ),
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
                        fontSize: 15,
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
                    if (project.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Chip(
                        label: Text(
                          project.first.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        backgroundColor: const Color(0xFFEDF2FF),
                        labelStyle: const TextStyle(color: _blue, fontSize: 11),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
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
              if (value == 'delete') _deleteTask(task);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Редактировать')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boardColumn(
    String title,
    List<Task> tasks,
    Color accent,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FC),
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 5, backgroundColor: accent),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${tasks.length}', style: const TextStyle(color: _muted)),
                const Spacer(),
                if (title == 'Сделать')
                  IconButton(
                    tooltip: 'Добавить задачу',
                    onPressed: _saving ? null : _createTask,
                    icon: const Icon(Icons.add_rounded, color: _muted),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Здесь пока пусто',
                  style: TextStyle(color: _muted),
                ),
              ),
            for (final task in tasks) _taskCard(task),
          ],
        ),
      ),
    );
  }

  Widget _content(double width, bool mobile) {
    final tasks = _visibleTasks;
    final done = tasks.where((task) => task.isDone).toList();
    final pending = tasks.where((task) => !task.isDone).toList();
    final padding = mobile ? 18.0 : 32.0;
    final available = width - 2 * padding;
    final columnWidth = mobile ? 300.0 : (available - 16) / 2;

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
                _pageTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: mobile ? 27 : 31,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${tasks.length} задач · ${done.length} выполнено',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 26),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: mobile ? available : 300,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Поиск задач',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.view_kanban_outlined),
                        label: Text('Доска'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_list_rounded),
                        label: Text('Список'),
                      ),
                    ],
                    selected: {_boardView},
                    onSelectionChanged: (value) =>
                        setState(() => _boardView = value.first),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _createTask,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Новая задача'),
                  ),
                  IconButton(
                    tooltip: 'Обновить',
                    onPressed: _loading || _saving ? null : _loadTasks,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
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
              if (!_loading && tasks.isEmpty)
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
              else if (_boardView)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _boardColumn(
                        'Сделать',
                        pending,
                        const Color(0xFF5E83F5),
                        columnWidth,
                      ),
                      const SizedBox(width: 16),
                      _boardColumn(
                        'Готово',
                        done,
                        const Color(0xFF38B990),
                        columnWidth,
                      ),
                    ],
                  ),
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
          drawer: mobile ? Drawer(width: 260, child: _sidebar(true)) : null,
          body: Row(
            children: [
              if (!mobile) _sidebar(false),
              Expanded(
                child: _content(
                  mobile ? constraints.maxWidth : constraints.maxWidth - 260,
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
