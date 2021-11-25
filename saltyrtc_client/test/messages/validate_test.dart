import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show TaskData, TasksData;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateTaskDataType, validateTasksDataType;

void main() {
  const task = 'task_name';
  const field = 'field';

  test('validateTaskDataType null', () {
    final map = validateTaskDataType({field: null}, '');
    expect(map, isNotNull);
    expect(map, isA<TaskData?>());
    expect(map!.keys, contains(field));
    expect(map[field], null);
  });

  test('validateTasksDataType null', () {
    final map = validateTasksDataType({task: null}, '');
    expect(map, isA<TasksData>());
    expect(map[task], null);
  });

  test('validateTasksDataType inner map value null', () {
    final map = validateTasksDataType(
      {
        task: {field: null}
      },
      '',
    );
    expect(map, isA<TasksData>());
    expect(map[task], {field: null});
    expect(map[task]![field], null);
  });
}
