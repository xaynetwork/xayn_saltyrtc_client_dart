import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageFields, TasksData;
import 'package:messagepack/messagepack.dart' show Packer;

void writeTasksData(Packer msgPacker, TasksData data) {
  msgPacker
    ..packString(MessageFields.data)
    ..packMapLength(data.length);

  data.forEach((key, value) {
    msgPacker.packString(key);

    if (value == null) {
      msgPacker.packNull();
    } else {
      msgPacker.packMapLength(value.length);
      value.forEach((key, value) {
        msgPacker
          ..packString(key)
          ..packBinary(value);
      });
    }
  });
}
