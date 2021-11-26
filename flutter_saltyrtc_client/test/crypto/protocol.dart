import 'dart:convert' show base64, json;
import 'dart:typed_data' show Uint8List;

import 'package:equatable/equatable.dart' show Equatable;

class MessageType {
  const MessageType._();

  static const keyExchange = 'keyExchange';
  static const encrypted = 'encrypted';
  static const plainData = 'plainData';
}

const signalingVersion = 1;

class _Fields {
  const _Fields._();

  static const data = 'data';
  static const type = 'type';
  static const version = 'version';
}

abstract class JsonMessage extends Equatable {
  final String type;
  final dynamic data;
  final int version;

  const JsonMessage({
    required this.type,
    required this.data,
    this.version = signalingVersion,
  });

  @override
  List<Object?> get props => [type, data];

  String get toJson => json.encode(<String, dynamic>{
        _Fields.type: type,
        _Fields.data: data,
        _Fields.version: version
      });

  @override
  String toString() => toJson;

  factory JsonMessage.plainData(String data) => PlainDataMessage(data);

  factory JsonMessage.encrypted(Map<String, String> data) => EncryptedMessage(
        cipher: base64.decode(data[_EncryptedFields.message]!),
        nonce: base64.decode(data[_EncryptedFields.nonce]!),
      );

  factory JsonMessage.keyExchange(Map<String, String> data) =>
      KeyExchangeMessage(
        cipher: base64.decode(data[_EncryptedFields.message]!),
        nonce: base64.decode(data[_EncryptedFields.nonce]!),
        pk: base64.decode(data[_EncryptedFields.pk]!),
      );

  factory JsonMessage.decode(Object message) {
    if (message is! String) {
      throw FormatException('Unsupported type ${message.runtimeType}');
    }
    final dynamic decode = json.decode(message);
    if (decode is! Map || !decode.containsKey(_Fields.type)) {
      throw FormatException(
        'Message is mal formatted, is not json or does not contain a ${_Fields.type} field.',
        message,
      );
    }
    final type = decode[_Fields.type] as String;
    final dynamic data = decode[_Fields.data];
    switch (type) {
      case MessageType.encrypted:
        return JsonMessage.encrypted(data as Map<String, String>);
      case MessageType.keyExchange:
        return JsonMessage.keyExchange(data as Map<String, String>);
      case MessageType.plainData:
        return JsonMessage.plainData(data as String);
    }
    throw FormatException('Unsupported type: $type in message $message');
  }
}

class PlainDataMessage extends JsonMessage {
  const PlainDataMessage(String data)
      : super(type: MessageType.plainData, data: data);
}

class _EncryptedFields {
  const _EncryptedFields._();

  static const message = 'message';
  static const nonce = 'nonce';

  // public key
  static const pk = 'pk';
}

class EncryptedMessage extends JsonMessage {
  final Uint8List cipher, nonce;

  EncryptedMessage({required this.cipher, required this.nonce})
      : super(
          type: MessageType.encrypted,
          data: {
            _EncryptedFields.message: cipher.toBase64,
            _EncryptedFields.nonce: nonce.toBase64,
          },
        );
}

class KeyExchangeMessage extends JsonMessage {
  final Uint8List cipher, nonce, pk;

  KeyExchangeMessage({
    required this.cipher,
    required this.nonce,
    required this.pk,
  }) : super(
          type: MessageType.keyExchange,
          data: {
            _EncryptedFields.message: cipher.toBase64,
            _EncryptedFields.nonce: nonce.toBase64,
            _EncryptedFields.pk: pk.toBase64
          },
        );

  @override
  String toString() => toJson;
}

extension CodecExtension on Uint8List {
  String get toBase64 => base64.encode(this);
}
