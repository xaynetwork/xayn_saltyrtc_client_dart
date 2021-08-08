import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageFields;
import 'package:messagepack/messagepack.dart' show Packer;

void writeStringMapMap(
    Packer msgPacker, Map<String, Map<String, List<int>>> data) {
  msgPacker
    ..packString(MessageFields.data)
    ..packMapLength(data.length);

  data.forEach((key, value) {
    msgPacker
      ..packString(key)
      ..packMapLength(value.length);
    value.forEach((key, value) {
      msgPacker
        ..packString(key)
        ..packBinary(value);
    });
  });
}
