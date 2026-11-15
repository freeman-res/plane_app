import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/tasks/task.dart';

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

  Future<List<Task>> getTasks() async {
    final response = await _send(_client.get(_uri('/tasks')));
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return data
          .map((item) => Task.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException('Сервер вернул неверный список задач.');
    }
  }

  Future<Task> createTask(String title, String description) async {
    final response = await _send(
      _client.post(
        _uri('/tasks'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'title': title, 'description': description}),
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

  Future<void> deleteTask(int id) async {
    await _send(_client.delete(_uri('/tasks/$id')));
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
