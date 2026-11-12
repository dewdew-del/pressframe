import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/export/filename.dart';

void main() {
  test('exportFileName pads to at least three digits', () {
    expect(exportFileName('Intrams', 1, 48), 'Intrams_001.jpg');
    expect(exportFileName('Intrams', 12, 1500), 'Intrams_0012.jpg');
    expect(exportFileName('Intrams', 999, 999), 'Intrams_999.jpg');
  });

  // Review Focus 3
  test('sanitizeEventName removes what Windows forbids', () {
    expect(sanitizeEventName('Intrams: Day 1/2?'), 'Intrams Day 12');
    expect(sanitizeEventName(r'a\b*c"d<e>f|g'), 'abcdefg');
    expect(sanitizeEventName('  ..  '), 'Event');
    expect(sanitizeEventName(''), 'Event');
    expect(sanitizeEventName('tab\there\n'), 'tabhere');
    expect(sanitizeEventName(' Foundation Day. '), 'Foundation Day');
    expect(sanitizeEventName('x' * 300).length, lessThanOrEqualTo(80));
  });

  // Review Focus 2
  test('uniquePath never returns a name that exists', () {
    final taken = {'a.jpg', 'a-2.jpg'};
    bool exists(String p) => taken.any(p.endsWith);
    expect(uniquePath('out', 'a.jpg', exists), endsWith('a-3.jpg'));
    expect(uniquePath('out', 'b.jpg', exists), endsWith('b.jpg'));
    expect(uniquePath('out', 'b.jpg', exists), startsWith('out'));
  });
}
