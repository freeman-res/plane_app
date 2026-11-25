import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:worknotes/core/api_client.dart';
import 'package:worknotes/features/schedule/schedule_entry.dart';
import 'package:worknotes/features/tasks/calendar_month.dart';

void main() {
  final entry = <String, dynamic>{
    'id': 5,
    'title': 'Матан',
    'description': 'Аудитория 101',
    'project_id': null,
    'first_date': '2026-11-02',
    'ends_on': null,
    'start_time': '10:00:00',
    'end_time': '11:00:00',
    'repeat_every_weeks': 2,
    'excluded_dates': ['2026-11-16'],
  };

  test('calendar parses optional schedule alongside tasks', () {
    final oldResponse = CalendarMonth.fromJson({
      'year': 2026,
      'month': 11,
      'days': [
        {'date': '2026-11-02', 'tasks': <dynamic>[]},
      ],
    });
    expect(oldResponse.days.single.schedule, isEmpty);
    final withSchedule = CalendarMonth.fromJson({
      'year': 2026,
      'month': 11,
      'days': [
        {
          'date': '2026-11-02',
          'tasks': <dynamic>[],
          'schedule': [
            {
              'schedule_id': 5,
              'title': 'Матан',
              'description': '',
              'project_id': null,
              'date': '2026-11-02',
              'start_time': '10:00:00',
              'end_time': '11:00:00',
            },
          ],
        },
      ],
    });
    expect(withSchedule.days.single.schedule.single.title, 'Матан');
    expect(
      scheduleTime(withSchedule.days.single.schedule.single.startTime),
      '10:00',
    );
  });

  test(
    'schedule client sends recurrence and an exception for one date',
    () async {
      final paths = <String>[];
      final client = ApiClient(
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url}');
          if (request.url.path == '/tasks/calendar') {
            expect(request.url.queryParameters['include_schedule'], 'true');
            expect(request.url.queryParameters['project_id'], '3');
            return http.Response(
              jsonEncode({'year': 2026, 'month': 11, 'days': []}),
              200,
            );
          }
          if (request.url.path == '/schedule' && request.method == 'POST') {
            final json = jsonDecode(request.body) as Map<String, dynamic>;
            expect(json['repeat_every_weeks'], 2);
            expect(json['first_date'], '2026-11-02');
            expect(json['ends_on'], isNull);
            return http.Response(jsonEncode(entry), 201);
          }
          if (request.method == 'DELETE' && request.url.path == '/schedule/5') {
            return http.Response('', 204);
          }
          return http.Response(jsonEncode(entry), 200);
        }),
      );

      await client.getCalendar(
        year: 2026,
        month: 11,
        projectId: 3,
        includeSchedule: true,
      );
      final created = await client.createSchedule(
        const ScheduleDraft(
          title: 'Матан',
          description: '',
          projectId: null,
          firstDate: '2026-11-02',
          endsOn: null,
          startTime: '10:00',
          endTime: '11:00',
          repeatEveryWeeks: 2,
        ),
      );
      expect(created.excludedDates, ['2026-11-16']);
      await client.skipScheduleDate(5, '2026-11-23');
      await client.restoreScheduleDate(5, '2026-11-23');
      await client.deleteSchedule(5);
      expect(
        paths
            .where((path) => path.contains('/schedule/5/exceptions/2026-11-23'))
            .length,
        2,
      );
      client.close();
    },
  );
}
