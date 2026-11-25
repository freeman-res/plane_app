class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.firstDate,
    required this.startTime,
    required this.endTime,
    required this.repeatEveryWeeks,
    this.projectId,
    this.endsOn,
    this.excludedDates = const [],
  });

  final int id;
  final String title;
  final String description;
  final int? projectId;
  final String firstDate;
  final String? endsOn;
  final String startTime;
  final String endTime;
  final int repeatEveryWeeks;
  final List<String> excludedDates;

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    id: json['id'] as int,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    projectId: json['project_id'] as int?,
    firstDate: json['first_date'] as String,
    endsOn: json['ends_on'] as String?,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    repeatEveryWeeks: json['repeat_every_weeks'] as int? ?? 1,
    excludedDates: (json['excluded_dates'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );
}

class ScheduleDraft {
  const ScheduleDraft({
    required this.title,
    required this.description,
    required this.projectId,
    required this.firstDate,
    required this.endsOn,
    required this.startTime,
    required this.endTime,
    required this.repeatEveryWeeks,
  });
  final String title;
  final String description;
  final int? projectId;
  final String firstDate;
  final String? endsOn;
  final String startTime;
  final String endTime;
  final int repeatEveryWeeks;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'project_id': projectId,
    'first_date': firstDate,
    'ends_on': endsOn,
    'start_time': startTime,
    'end_time': endTime,
    'repeat_every_weeks': repeatEveryWeeks,
  };
}

class ScheduleOccurrence {
  const ScheduleOccurrence({
    required this.scheduleId,
    required this.title,
    required this.description,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.projectId,
  });

  final int scheduleId;
  final String title;
  final String description;
  final int? projectId;
  final String date;
  final String startTime;
  final String endTime;

  factory ScheduleOccurrence.fromJson(Map<String, dynamic> json) =>
      ScheduleOccurrence(
        scheduleId: json['schedule_id'] as int,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        projectId: json['project_id'] as int?,
        date: json['date'] as String,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
      );
}

String scheduleTime(String value) =>
    value.length >= 5 ? value.substring(0, 5) : value;
