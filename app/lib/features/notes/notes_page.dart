import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../projects/project.dart';
import '../tasks/task.dart';
import 'note.dart';
import 'note_editor.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.api,
    required this.projects,
    required this.tasks,
    required this.onTasksChanged,
    this.showMenu = false,
    this.taskId,
    this.onClearTask,
  });
  final ApiClient api;
  final List<Project> projects;
  final List<Task> tasks;
  final VoidCallback onTasksChanged;
  final bool showMenu;
  final int? taskId;
  final VoidCallback? onClearTask;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  List<Note> _notes = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_update);
    _load();
  }

  void _update() => setState(() {});

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) _load();
  }

  @override
  void dispose() {
    _search.removeListener(_update);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final taskId = widget.taskId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await widget.api.getNotes(taskId: taskId);
      if (mounted && request == _request) setState(() => _notes = notes);
    } catch (error) {
      if (mounted && request == _request)
        setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(Note? note) async {
    Note? latest = note;
    try {
      if (note != null) latest = await widget.api.getNote(note.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditor(
          api: widget.api,
          projects: widget.projects,
          tasks: widget.tasks,
          note: latest,
          initialTaskId: widget.taskId,
          onTasksChanged: widget.onTasksChanged,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _delete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: Text(
          '«${note.title}» и её вложения будут удалены. Связанные задачи останутся.',
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
    try {
      await widget.api.deleteNote(note.id);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase().trim();
    final visible = _notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(query) ||
              note.preview.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 32, 26, 40),
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
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.taskId == null ? 'Заметки' : 'Заметки задачи',
                          style: const TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF192B45),
                          ),
                        ),
                        const Text(
                          'Идеи, записи и материалы в одном месте',
                          style: TextStyle(color: Color(0xFF78879C)),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: () => _open(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Новая заметка'),
                    ),
                  ],
                ),
                if (widget.taskId != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onClearTask,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Все заметки'),
                    ),
                  ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по заметкам',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_loading && visible.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 60,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE7ECF4)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          query.isEmpty
                              ? Icons.sticky_note_2_outlined
                              : Icons.search_off,
                          size: 44,
                          color: const Color(0xFF4269EF),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          query.isEmpty
                              ? 'Пока нет заметок'
                              : 'Ничего не найдено',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (query.isEmpty)
                          const Text(
                            'Создайте первую заметку для идей и материалов.',
                          ),
                      ],
                    ),
                  ),
                if (visible.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final columns = width > 900
                          ? 3
                          : width > 580
                          ? 2
                          : 1;
                      final itemWidth = (width - (columns - 1) * 14) / columns;
                      return Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (final note in visible)
                            SizedBox(
                              width: itemWidth,
                              child: Card(
                                color: Colors.white,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _open(note),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.description_outlined,
                                              color: Color(0xFF4269EF),
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                note.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Удалить заметку',
                                              onPressed: () => _delete(note),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          note.preview.isEmpty
                                              ? 'Пустая заметка'
                                              : note.preview,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF78879C),
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            if (note.taskIds.isNotEmpty)
                                              Chip(
                                                label: Text(
                                                  'Задач: ${note.taskIds.length}',
                                                ),
                                                avatar: const Icon(
                                                  Icons.link,
                                                  size: 16,
                                                ),
                                              ),
                                            if (note.attachments.isNotEmpty)
                                              Chip(
                                                label: Text(
                                                  'Файлов: ${note.attachments.length}',
                                                ),
                                                avatar: const Icon(
                                                  Icons.attach_file,
                                                  size: 16,
                                                ),
                                              ),
                                          ],
                                        ),
                                        Text(
                                          '${note.updatedAt.day.toString().padLeft(2, '0')}.'
                                          '${note.updatedAt.month.toString().padLeft(2, '0')}.'
                                          '${note.updatedAt.year}',
                                          style: const TextStyle(
                                            color: Color(0xFF78879C),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
