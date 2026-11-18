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
  final List<String> tags;
  final bool isOverdue;

  bool get isDone => status == 'done';

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
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag as String)
          .toList(),
      isOverdue: json['is_overdue'] as bool? ?? false,
    );
  }
}
