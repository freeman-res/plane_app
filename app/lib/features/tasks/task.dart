class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.projectId,
    this.deadline,
    this.startDate,
    this.priority = 'medium',
    this.urgent,
    this.moscow,
    this.urgencyFromServer,
    this.tags = const [],
    this.isOverdue = false,
  });

  final int id;
  final String title;
  final String description;
  final String status;
  final int? projectId;
  final String? deadline;
  final String? startDate;
  final String priority;

  /// null means urgency follows the deadline (today or the next two days).
  final bool? urgent;

  /// Project planning category. null means not yet classified.
  final String? moscow;
  final bool? urgencyFromServer;
  final List<String> tags;
  final bool isOverdue;

  bool get isDone => status == 'done';

  bool get isUrgent {
    if (urgencyFromServer != null) return urgencyFromServer!;
    if (urgent != null) return urgent!;
    final due = DateTime.tryParse(deadline ?? '');
    if (due == null) return false;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return !due.isAfter(start.add(const Duration(days: 2)));
  }

  String get matrixQuadrant =>
      '${isUrgent ? 'urgent' : 'not_urgent'}_'
      '${priority == 'high' ? 'important' : 'not_important'}';

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      status: json['status'] as String,
      projectId: json['project_id'] as int?,
      deadline: json['deadline'] as String?,
      startDate: json['start_date'] as String?,
      priority: json['priority'] as String? ?? 'medium',
      urgent: json['urgent'] as bool?,
      moscow: json['moscow'] as String?,
      urgencyFromServer: json['is_urgent'] as bool?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag as String)
          .toList(),
      isOverdue: json['is_overdue'] as bool? ?? false,
    );
  }
}
