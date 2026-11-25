import 'package:material_ui/material_ui.dart';

import 'task.dart';
import '../schedule/schedule_entry.dart';

const _ink = Color(0xFF192B45);
const _muted = Color(0xFF78879C);
const _blue = Color(0xFF4269EF);
const _line = Color(0xFFE7ECF4);

class TaskCalendar extends StatelessWidget {
  const TaskCalendar({
    super.key,
    required this.month,
    required this.tasksByDay,
    required this.scheduleByDay,
    required this.showSchedule,
    required this.selectedDay,
    required this.mobile,
    required this.loading,
    required this.error,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.onRetry,
    required this.taskBuilder,
    required this.onCancelOccurrence,
  });

  final DateTime month;
  final Map<int, List<Task>> tasksByDay;
  final Map<int, List<ScheduleOccurrence>> scheduleByDay;
  final bool showSchedule;
  final int? selectedDay;
  final bool mobile;
  final bool loading;
  final String? error;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onRetry;
  final Widget Function(Task) taskBuilder;
  final ValueChanged<ScheduleOccurrence> onCancelOccurrence;

  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;
    final dayTasks = tasksByDay[selectedDay] ?? const <Task>[];
    final daySchedule = showSchedule
        ? scheduleByDay[selectedDay] ?? const <ScheduleOccurrence>[]
        : const <ScheduleOccurrence>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.all(mobile ? 10 : 20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_months[month.month - 1]} ${month.year}',
                      style: TextStyle(
                        fontSize: mobile ? 18 : 21,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  if (!mobile)
                    TextButton(
                      onPressed: () => onMonthChanged(DateTime.now()),
                      child: const Text('Сегодня'),
                    ),
                  IconButton(
                    tooltip: 'Предыдущий месяц',
                    onPressed: () =>
                        onMonthChanged(DateTime(month.year, month.month - 1)),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    tooltip: 'Следующий месяц',
                    onPressed: () =>
                        onMonthChanged(DateTime(month.year, month.month + 1)),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final weekday in _weekdays)
                    Expanded(
                      child: Center(
                        child: Text(
                          weekday,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (var row = 0; row < cells ~/ 7; row++)
                Row(
                  children: [
                    for (var column = 0; column < 7; column++)
                      Expanded(
                        child: _dayCell(
                          row * 7 + column - firstWeekday + 1,
                          daysInMonth,
                          isCurrentMonth ? today.day : null,
                        ),
                      ),
                  ],
                ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (error != null)
          Row(
            children: [
              Expanded(
                child: Text(error!, style: const TextStyle(color: _muted)),
              ),
              TextButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          )
        else if (selectedDay == null)
          const Text(
            'Выберите день, чтобы посмотреть задачи с дедлайном.',
            style: TextStyle(color: _muted),
          )
        else ...[
          Text(
            '${selectedDay.toString().padLeft(2, '0')}.'
            '${month.month.toString().padLeft(2, '0')}: '
            '${dayTasks.length} задач'
            '${showSchedule ? ' · ${daySchedule.length} занятий' : ''}',
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (daySchedule.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${daySchedule.length} занятий',
                style: const TextStyle(
                  color: Color(0xFFB77925),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (dayTasks.isEmpty && daySchedule.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'На этот день задач нет.',
                style: TextStyle(color: _muted),
              ),
            ),
          for (final task in dayTasks) taskBuilder(task),
          for (final occurrence in daySchedule)
            Card(
              color: const Color(0xFFFFFAEE),
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.school_outlined, color: Color(0xFFB77925)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            occurrence.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${scheduleTime(occurrence.startTime)}–${scheduleTime(occurrence.endTime)}'
                            '${occurrence.description.isEmpty ? '' : ' · ${occurrence.description}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Отменить это занятие',
                      onPressed: () => onCancelOccurrence(occurrence),
                      icon: const Icon(Icons.event_busy_outlined),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _dayCell(int day, int daysInMonth, int? today) {
    if (day < 1 || day > daysInMonth) {
      return SizedBox(height: mobile ? 58 : 102);
    }
    final tasks = tasksByDay[day] ?? const <Task>[];
    final schedule = showSchedule
        ? scheduleByDay[day] ?? const <ScheduleOccurrence>[]
        : const <ScheduleOccurrence>[];
    final selected = day == selectedDay;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected ? const Color(0xFFECF1FF) : Colors.white,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => onDaySelected(day),
          child: Container(
            height: mobile ? 54 : 98,
            padding: EdgeInsets.all(mobile ? 3 : 7),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? _blue : _line,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: mobile ? 22 : 25,
                  height: mobile ? 22 : 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: day == today ? _blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: day == today ? Colors.white : _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: mobile ? 11 : 13,
                    ),
                  ),
                ),
                if (tasks.isNotEmpty || schedule.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  if (mobile)
                    Row(
                      children: [
                        if (tasks.isNotEmpty)
                          Container(
                            width: 9,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        if (tasks.isNotEmpty && schedule.isNotEmpty)
                          const SizedBox(width: 3),
                        if (schedule.isNotEmpty)
                          Container(
                            width: 9,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBA342),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    )
                  else
                    for (final task in tasks.take(schedule.isEmpty ? 2 : 1))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '• ${task.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  if (!mobile)
                    for (final item in schedule.take(tasks.isEmpty ? 2 : 1))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${scheduleTime(item.startTime)} ${item.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB77925),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
