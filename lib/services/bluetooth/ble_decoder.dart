import 'dart:typed_data';

class BleDecoder {
  static int heartRate(List<int> bytes) {
    if (bytes.length < 2) throw const FormatException('Truncated HR');
    if ((bytes[0] & 1) == 0) return bytes[1];
    if (bytes.length < 3) throw const FormatException('Truncated 16 bit HR');
    return bytes[1] | (bytes[2] << 8);
  }

  static int power(List<int> bytes) {
    if (bytes.length < 4) throw const FormatException('Truncated power');
    return ByteData.sublistView(Uint8List.fromList(bytes))
        .getInt16(2, Endian.little);
  }

  int? _crank, _time;
  double? cadence(List<int> bytes) {
    if (bytes.isEmpty) throw const FormatException('Truncated CSC');
    if ((bytes[0] & 2) == 0) return null;
    final offset = (bytes[0] & 1) != 0 ? 7 : 1;
    if (bytes.length < offset + 4) {
      throw const FormatException('Truncated crank');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final crank = data.getUint16(offset, Endian.little);
    final time = data.getUint16(offset + 2, Endian.little);
    double? rpm;
    if (_crank != null) {
      final dt = (time - _time!) & 0xffff;
      final turns = (crank - _crank!) & 0xffff;
      if (dt > 0) rpm = turns * 60 * 1024 / dt;
      if (rpm != null && rpm > 250) rpm = null;
    }
    _crank = crank;
    _time = time;
    return rpm;
  }
}
