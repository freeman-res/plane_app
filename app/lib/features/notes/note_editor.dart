import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../projects/project.dart';
import '../tasks/task.dart';
import 'note.dart';
import 'note_file_dialog.dart';
import 'note_task_dialog.dart';
import 'note_text_controller.dart';

const _accent = Color(0xFF4269EF);
const _muted = Color(0xFF78879C);

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.api,
    required this.projects,
    required this.tasks,
    this.note,
    this.initialTaskId,
    required this.onTasksChanged,
  });
  final ApiClient api;
  final List<Project> projects;
  final List<Task> tasks;
  final Note? note;
  final int? initialTaskId;
  final VoidCallback onTasksChanged;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _EditableBlock {
  _EditableBlock(NoteBlock block)
    : type = block.type,
      controller = NoteTextController(block.spans);
  String type;
  final NoteTextController controller;
  NoteBlock get value => NoteBlock(type: type, spans: controller.spans);
  void dispose() => controller.dispose();
}

class _NoteEditorState extends State<NoteEditor> {
  final _title = TextEditingController();
  final _blocks = <_EditableBlock>[];
  Note? _note;
  int _active = 0;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  final Map<int, String> _createdTaskTitles = {};
  final _colors = const [
    '#192B45',
    '#4269EF',
    '#7C4BD2',
    '#DB5366',
    '#299178',
    '#B77925',
  ];

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _title.text = widget.note?.title ?? '';
    for (final block in widget.note?.content ?? const <NoteBlock>[]) {
      _append(block);
    }
    if (_blocks.isEmpty) _append(const NoteBlock());
  }

  void _append(NoteBlock block) {
    final item = _EditableBlock(block);
    _blocks.add(item);
  }

  @override
  void dispose() {
    _title.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      return await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Note?> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название заметки');
      return null;
    }
    if (title.length > 200) {
      setState(() => _error = 'Название не длиннее 200 символов');
      return null;
    }
    final content = _blocks.map((block) => block.value).toList();
    if (content.length > 500 ||
        content.any(
          (block) =>
              block.spans.length > 100 ||
              block.spans.any((span) => span.text.length > 10000),
        ) ||
        content.fold<int>(
              0,
              (sum, block) =>
                  sum +
                  block.spans.fold<int>(
                    0,
                    (length, span) => length + span.text.length,
                  ),
            ) >
            100000) {
      setState(() => _error = 'Заметка слишком длинная для сохранения');
      return null;
    }
    return _run(() async {
      var saved = _note == null
          ? await widget.api.createNote(title, content)
          : await widget.api.updateNote(_note!.id, title, content);
      if (widget.initialTaskId != null &&
          !saved.taskIds.contains(widget.initialTaskId)) {
        saved = await widget.api.linkNoteTask(saved.id, widget.initialTaskId!);
      }
      if (mounted)
        setState(() {
          _note = saved;
          _dirty = false;
        });
      return saved;
    });
  }

  Future<Note?> _ensureSaved() async {
    if (_note != null && !_dirty) return _note;
    return _save();
  }

  void _format(NoteSpan Function(NoteSpan) update) {
    setState(() {
      _blocks[_active].controller.format(update);
      _dirty = true;
    });
  }

  Future<void> _attach() async {
    final note = await _ensureSaved();
    if (note == null || !mounted) return;
    try {
      final file = await NoteFileDialog.pick();
      if (file == null || !mounted) return;
      final extension = file.name.split('.').last.toLowerCase();
      final mediaType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        'm4a' || 'mp4' => 'audio/mp4',
        'webm' => 'audio/webm',
        _ => null,
      };
      if (mediaType == null) return;
      final limit = mediaType.startsWith('image/')
          ? 10 * 1024 * 1024
          : 25 * 1024 * 1024;
      if (file.bytes.length > limit) {
        setState(() => _error = 'Файл больше разрешённого размера');
        return;
      }
      if (!mounted) return;
      await _run(() async {
        await widget.api.uploadNoteAttachment(
          note.id,
          file.name,
          mediaType,
          file.bytes,
        );
        final updated = await widget.api.getNote(note.id);
        if (mounted) setState(() => _note = updated);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _removeAttachment(NoteAttachment item) async {
    final note = _note;
    if (note == null) return;
    await _run(() async {
      await widget.api.deleteNoteAttachment(note.id, item.id);
      final updated = await widget.api.getNote(note.id);
      if (mounted) setState(() => _note = updated);
    });
  }

  Future<void> _download(NoteAttachment item) async {
    final note = _note;
    if (note == null) return;
    try {
      await _run(() async {
        final bytes = await widget.api.downloadNoteAttachment(note.id, item.id);
        await NoteFileDialog.save(item.filename, Uint8List.fromList(bytes));
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _linkTask() async {
    final note = await _ensureSaved();
    if (note == null || !mounted) return;
    final available = widget.tasks
        .where((task) => !note.taskIds.contains(task.id))
        .toList();
    if (available.isEmpty) {
      setState(() => _error = 'Нет задач для привязки');
      return;
    }
    final id = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Связать с задачей'),
        children: [
          for (final task in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, task.id),
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    await _run(() async {
      final updated = await widget.api.linkNoteTask(note.id, id);
      if (mounted) setState(() => _note = updated);
    });
  }

  Future<void> _createTask() async {
    final note = await _ensureSaved();
    if (note == null || !mounted) return;
    final options = await showDialog<NoteTaskOptions>(
      context: context,
      builder: (context) => NoteTaskDialog(projects: widget.projects),
    );
    if (options == null || !mounted) return;
    await _run(() async {
      final task = await widget.api.createTaskFromNote(
        note.id,
        projectId: options.projectId,
        status: options.status,
        priority: options.priority,
        startDate: options.startDate,
        deadline: options.deadline,
      );
      final updated = await widget.api.getNote(note.id);
      if (mounted) {
        setState(() {
          _note = updated;
          _createdTaskTitles[task.id] = task.title;
        });
      }
      widget.onTasksChanged();
    });
  }

  Future<void> _close() async {
    if (_dirty) {
      final answer = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить изменения?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Остаться'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Не сохранять'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (answer == 'save') {
        if (await _save() == null || !mounted) return;
      } else if (answer != 'discard') {
        return;
      } else {
        setState(() => _dirty = false);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _toolbar() {
    final style = _blocks[_active].controller.currentStyle;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      runSpacing: 8,
      children: [
        DropdownButton<String>(
          value: style.fontFamily,
          items: const [
            DropdownMenuItem(value: 'sans', child: Text('Обычный')),
            DropdownMenuItem(value: 'serif', child: Text('С засечками')),
            DropdownMenuItem(value: 'mono', child: Text('Моноширинный')),
          ],
          onChanged: (value) {
            if (value != null)
              _format((span) => span.copyWith(fontFamily: value));
          },
        ),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value:
              [
                8,
                10,
                12,
                14,
                16,
                18,
                20,
                24,
                28,
                32,
                36,
                48,
              ].contains(style.fontSize)
              ? style.fontSize
              : 14,
          items: [
            for (final size in [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48])
              DropdownMenuItem(value: size, child: Text('$size')),
          ],
          onChanged: (value) {
            if (value != null)
              _format((span) => span.copyWith(fontSize: value));
          },
        ),
        IconButton(
          tooltip: 'Жирный',
          isSelected: style.bold,
          onPressed: () => _format((span) => span.copyWith(bold: !style.bold)),
          icon: const Icon(Icons.format_bold),
        ),
        IconButton(
          tooltip: 'Курсив',
          isSelected: style.italic,
          onPressed: () =>
              _format((span) => span.copyWith(italic: !style.italic)),
          icon: const Icon(Icons.format_italic),
        ),
        IconButton(
          tooltip: 'Подчёркнутый',
          isSelected: style.underline,
          onPressed: () =>
              _format((span) => span.copyWith(underline: !style.underline)),
          icon: const Icon(Icons.format_underline),
        ),
        PopupMenuButton<String>(
          tooltip: 'Цвет текста',
          icon: const Icon(Icons.format_color_text),
          onSelected: (value) => _format(
            (span) => value.isEmpty
                ? span.copyWith(clearColor: true)
                : span.copyWith(color: value),
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('Цвет по умолчанию')),
            for (final color in _colors)
              PopupMenuItem(
                value: color,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: Color(
                        int.parse(color.substring(1), radix: 16) | 0xFF000000,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(color),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _blockEditor(int index) {
    final block = _blocks[index];
    return Padding(
      key: ObjectKey(block),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Тип блока',
            icon: Icon(switch (block.type) {
              'heading' => Icons.title,
              'bullet' => Icons.format_list_bulleted,
              'numbered' => Icons.format_list_numbered,
              _ => Icons.notes,
            }, color: _muted),
            onSelected: (value) => setState(() {
              block.type = value;
              _active = index;
              _dirty = true;
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'paragraph', child: Text('Абзац')),
              PopupMenuItem(value: 'heading', child: Text('Заголовок')),
              PopupMenuItem(value: 'bullet', child: Text('Маркер')),
              PopupMenuItem(value: 'numbered', child: Text('Нумерация')),
            ],
          ),
          Expanded(
            child: TextField(
              controller: block.controller,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              onTap: () => setState(() => _active = index),
              onChanged: (_) => setState(() {
                _active = index;
                _dirty = true;
              }),
              style: TextStyle(
                color: const Color(0xFF192B45),
                fontSize: block.type == 'heading' ? 20 : 14,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: index == 0 ? 'Начните писать…' : 'Продолжение…',
                prefixText: block.type == 'bullet'
                    ? '•  '
                    : block.type == 'numbered'
                    ? '${index + 1}.  '
                    : null,
                fillColor: index == _active
                    ? const Color(0xFFF7F9FF)
                    : Colors.white,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Удалить блок',
            onPressed: _blocks.length == 1
                ? null
                : () => setState(() {
                    final removed = _blocks.removeAt(index);
                    removed.dispose();
                    _active = _active.clamp(0, _blocks.length - 1);
                    _dirty = true;
                  }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _attachments() {
    final attachments = _note?.attachments ?? const <NoteAttachment>[];
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 36),
        Text('Вложения', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in attachments)
              Card(
                child: SizedBox(
                  width: 230,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.mediaType.startsWith('image/'))
                        FutureBuilder<List<int>>(
                          future: widget.api.downloadNoteAttachment(
                            _note!.id,
                            item.id,
                          ),
                          builder: (_, snapshot) => snapshot.hasData
                              ? Image.memory(
                                  Uint8List.fromList(snapshot.data!),
                                  height: 110,
                                  width: 210,
                                  fit: BoxFit.cover,
                                )
                              : const SizedBox(
                                  height: 110,
                                  child: Center(
                                    child: Icon(Icons.image_outlined),
                                  ),
                                ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: Icon(
                            Icons.audiotrack_rounded,
                            color: _accent,
                            size: 38,
                          ),
                        ),
                      ListTile(
                        dense: true,
                        title: Text(
                          item.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${(item.size / 1024).toStringAsFixed(1)} КБ',
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Скачать вложение',
                            onPressed: _busy ? null : () => _download(item),
                            icon: const Icon(Icons.download_outlined),
                          ),
                          IconButton(
                            tooltip: 'Удалить вложение',
                            onPressed: _busy
                                ? null
                                : () => _removeAttachment(item),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_note == null ? 'Новая заметка' : 'Редактор заметки'),
        leading: IconButton(
          onPressed: _busy ? null : _close,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    await _save();
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Сохранить'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!, style: const TextStyle(color: Colors.red)),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 850),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _title,
                          onChanged: (_) => setState(() => _dirty = true),
                          maxLength: 200,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF192B45),
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Название заметки',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                          ),
                        ),
                        const Text(
                          'Выделите текст для форматирования. Без выделения формат применяется к следующему вводу.',
                          style: TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: _toolbar(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        for (var index = 0; index < _blocks.length; index++)
                          _blockEditor(index),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _append(const NoteBlock());
                              _active = _blocks.length - 1;
                              _dirty = true;
                            }),
                            icon: const Icon(Icons.add),
                            label: const Text('Добавить блок'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _attach,
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Прикрепить фото или аудио'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _linkTask,
                              icon: const Icon(Icons.link),
                              label: const Text('Связать с задачей'),
                            ),
                            FilledButton.icon(
                              onPressed: _busy ? null : _createTask,
                              icon: const Icon(Icons.add_task),
                              label: const Text('Сделать задачей'),
                            ),
                          ],
                        ),
                        if ((_note?.taskIds ?? const <int>[]).isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Связанные задачи',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final id in _note!.taskIds)
                                InputChip(
                                  label: Text(
                                    widget.tasks
                                            .where((task) => task.id == id)
                                            .map((task) => task.title)
                                            .firstOrNull ??
                                        _createdTaskTitles[id] ??
                                        'Задача #$id',
                                  ),
                                  onDeleted: _busy
                                      ? null
                                      : () async {
                                          final note = _note!;
                                          await _run(() async {
                                            final updated = await widget.api
                                                .unlinkNoteTask(note.id, id);
                                            if (mounted)
                                              setState(() => _note = updated);
                                          });
                                        },
                                ),
                            ],
                          ),
                        ],
                        _attachments(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
