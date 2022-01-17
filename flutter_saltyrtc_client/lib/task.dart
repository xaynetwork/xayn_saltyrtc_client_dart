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

/// Re-export of all types needed to implement a task.
///
/// To implement a task you need to first implement a
/// [TaskBuilder] which is used to build a task and
/// can exchange some initial settings during the
/// client to client handshake.
///
/// Then you need to implement the [Task] created by
/// the [TaskBuilder], especially when you need to make sure
/// canceling the task works.
///
/// Take a look at `example/example.dart` to see how to implement a [TaskBuilder]
/// and a [Task].
library flutter_saltyrtc_client.task;

import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart'
    show Task, TaskBuilder;

export 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart'
    show
        Task,
        TaskBuilder,
        CancelReason,
        CloseCode,
        Pair,
        SaltyRtcTaskLink,
        TaskData,
        TaskMessage;
