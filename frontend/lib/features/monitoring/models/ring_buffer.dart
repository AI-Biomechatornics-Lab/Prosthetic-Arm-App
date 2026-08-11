/// Fixed-capacity circular buffer. Never resizes or shifts elements -
/// writes just overwrite the oldest slot, so pushing new samples is O(1)
/// and allocation-free (unlike a growing List with removeAt(0)).
class RingBuffer {
  RingBuffer(this.capacity) : _data = List<double>.filled(capacity, 0);

  final int capacity;
  final List<double> _data;
  int _writeIndex = 0;
  int _count = 0;

  void add(double value) {
    _data[_writeIndex] = value;
    _writeIndex = (_writeIndex + 1) % capacity;
    if (_count < capacity) _count++;
  }

  int get length => _count;

  bool get isFull => _count == capacity;

  /// Value at logical index [i], where 0 is the oldest sample still held
  /// and length-1 is the newest.
  double operator [](int i) {
    final start = isFull ? _writeIndex : 0;
    return _data[(start + i) % capacity];
  }
}
