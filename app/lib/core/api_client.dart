import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/tasks/task.dart';
import '../features/tasks/calendar_month.dart';
import '../features/projects/project.dart';

// Для Windows адрес по умолчанию указывает на FastAPI на этом же компьютере.
// Для Android адрес можно переопределить через --dart-define=API_BASE_URL=...
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String baseUrl = apiBaseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _baseUrl;
  static const _timeout = Duration(seconds: 10);

  Uri _uri(String path) => _baseUrl.resolve(path);

  Future<http.Response> _send(Future<http.Response> request) async {
    late final http.Response response;
    try {
      response = await request.timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'Нет связи с сервером. Проверь, что FastAPI запущен на порту 8000.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Нет связи с сервером. Проверь, что FastAPI запущен на порту 8000.',
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException('Ошибка сервера: ${response.statusCode}');
    }
    return response;
  }

  Future<List<Task>> getTasks({
    int? projectId,
    String? sortBy,
    bool descending = false,
    String? status,
    String? priority,
    String? tag,
    bool? overdue,
  }) async {
    final uri = _uri('/tasks');
    final query = <String, String>{
      if (projectId != null) 'project_id': '$projectId',
      if (sortBy != null) ...{'sort_by': sortBy, 'descending': '$descending'},
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (tag != null) 'tag': tag,
      if (overdue != null) 'overdue': '$overdue',
    };
    final response = await _send(
      _client.get(query.isEmpty ? uri : uri.replace(queryParameters: query)),
    );
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return data
          .map((item) => Task.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException('Сервер вернул неверный список задач.');
    }
  }

  Future<List<Task>> getOverdueTasks({int? projectId}) async {
    final uri = _uri('/tasks/overdue');
    final response = await _send(
      _client.get(
        projectId == null
            ? uri
            : uri.replace(queryParameters: {'project_id': '$projectId'}),
      ),
    );
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return data
          .map((item) => Task.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException(
        'Сервер вернул неверный список просроченных задач.',
      );
    }
  }

  Future<CalendarMonth> getCalendar({
    required int year,
    required int month,
    int? projectId,
  }) async {
    final response = await _send(
      _client.get(
        _uri('/tasks/calendar').replace(
          queryParameters: {
            'year': '$year',
            'month': '$month',
            if (projectId != null) 'project_id': '$projectId',
          },
        ),
      ),
    );
    try {
      return CalendarMonth.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const ApiException('Сервер вернул неверные данные календаря.');
    }
  }

  Future<Task> createTask(
    String title,
    String description, {
    int? projectId,
    String? status,
    String? startDate,
    String? deadline,
    String? priority,
    List<String>? tags,
  }) async {
    final response = await _send(
      _client.post(
        _uri('/tasks'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'title': title,
          'description': description,
          'project_id': projectId,
          if (status != null) 'status': status,
          if (startDate != null) 'start_date': startDate,
          if (deadline != null) 'deadline': deadline,
          if (priority != null) 'priority': priority,
          if (tags != null) 'tags': tags,
        }),
      ),
    );
    return _taskFromResponse(response);
  }

  Future<Task> updateStatus(int id, String status) async {
    final response = await _send(
      _client.patch(
        _uri('/tasks/$id'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'status': status}),
      ),
    );
    return _taskFromResponse(response);
  }

  Future<Task> editTask(
    int id,
    String title,
    String description, {
    int? projectId,
    String? status,
    String? startDate,
    String? deadline,
    bool updateDeadline = false,
    String? priority,
    List<String>? tags,
  }) async {
    final response = await _send(
      _client.patch(
        _uri('/tasks/$id'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'title': title,
          'description': description,
          'project_id': projectId,
          if (status != null) 'status': status,
          if (startDate != null) 'start_date': startDate,
          if (updateDeadline) 'deadline': deadline,
          if (priority != null) 'priority': priority,
          if (tags != null) 'tags': tags,
        }),
      ),
    );
    return _taskFromResponse(response);
  }

  Future<void> deleteTask(int id) async {
    await _send(_client.delete(_uri('/tasks/$id')));
  }

  Future<Task> updateDeadline(int id, String deadline) async {
    final response = await _send(
      _client.patch(
        _uri('/tasks/$id'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'deadline': deadline}),
      ),
    );
    return _taskFromResponse(response);
  }

  Future<List<Project>> getProjects() async {
    final response = await _send(_client.get(_uri('/projects')));
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return data
          .map((item) => Project.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException('Сервер вернул неверный список проектов.');
    }
  }

  Future<Project> createProject(String name) async {
    final response = await _send(
      _client.post(
        _uri('/projects'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'name': name}),
      ),
    );
    try {
      return Project.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const ApiException('Сервер вернул неверные данные проекта.');
    }
  }

  Future<void> deleteProject(int id) async {
    await _send(_client.delete(_uri('/projects/$id')));
  }

  Task _taskFromResponse(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return Task.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      throw const ApiException('Сервер вернул неверные данные задачи.');
    }
  }

  void close() => _client.close();
}
