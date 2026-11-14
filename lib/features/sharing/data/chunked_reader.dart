import 'dart:async';
import 'dart:typed_data';

/// Reads a byte stream in fixed-size pieces (one upload part at a time).
/// Works for plain files and Android content:// streams alike.
class ChunkedReader {
  ChunkedReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  List<int>? _pending;
  int _offset = 0;

  /// The next [size] bytes, fewer at the end of the stream, or null when nothing is left.
  Future<Uint8List?> next(int size) async {
    final builder = BytesBuilder(copy: false);
    while (builder.length < size) {
      final pending = _pending;
      if (pending == null) {
        if (!await _iterator.moveNext()) break;
        _pending = _iterator.current;
        _offset = 0;
        continue;
      }
      final need = size - builder.length;
      final available = pending.length - _offset;
      if (available <= need) {
        builder.add(_offset == 0 ? pending : pending.sublist(_offset));
        _pending = null;
      } else {
        builder.add(pending.sublist(_offset, _offset + need));
        _offset += need;
      }
    }
    return builder.isEmpty ? null : builder.takeBytes();
  }

  Future<void> close() => _iterator.cancel();
}
