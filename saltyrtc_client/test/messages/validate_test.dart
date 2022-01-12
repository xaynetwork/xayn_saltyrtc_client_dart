// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
