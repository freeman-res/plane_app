class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.projectId,
  });

  final int id;
  final String title;
  final String description;
  final String status;
  final int? projectId;

  bool get isDone => status == 'done';

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      status: json['status'] as String,
      projectId: json['project_id'] as int?,
    );
  }
}
