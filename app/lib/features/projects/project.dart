class Project {
  const Project({required this.id, required this.name});

  final int id;
  final String name;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(id: json['id'] as int, name: json['name'] as String);
  }
}
