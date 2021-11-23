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
