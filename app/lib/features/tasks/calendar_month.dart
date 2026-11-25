import 'task.dart';
import '../schedule/schedule_entry.dart';

class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.tasks,
    this.schedule = const [],
  });

  final String date;
  final List<Task> tasks;
  final List<ScheduleOccurrence> schedule;

  factory CalendarDay.fromJson(Map<String, dynamic> json) => CalendarDay(
    date: json['date'] as String,
    tasks: (json['tasks'] as List<dynamic>)
        .map((item) => Task.fromJson(item as Map<String, dynamic>))
        .toList(),
    schedule: (json['schedule'] as List<dynamic>? ?? const [])
        .map(
          (item) => ScheduleOccurrence.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );
}

class CalendarMonth {
  const CalendarMonth({
    required this.year,
    required this.month,
    required this.days,
  });

  final int year;
  final int month;
  final List<CalendarDay> days;

  factory CalendarMonth.fromJson(Map<String, dynamic> json) => CalendarMonth(
    year: json['year'] as int,
    month: json['month'] as int,
    days: (json['days'] as List<dynamic>)
        .map((item) => CalendarDay.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}
