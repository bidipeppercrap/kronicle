import 'package:flutter_test/flutter_test.dart';
import 'package:kronicle/chat/diff.dart';

void main() {
  test('unifiedDiff marks added and removed lines', () {
    final rows = unifiedDiff('alpha\nbeta', 'alpha\ngamma');
    expect(rows.any((r) => r.kind == DiffKind.del && r.text == 'beta'), isTrue);
    expect(rows.any((r) => r.kind == DiffKind.add && r.text == 'gamma'), isTrue);
    expect(rows.any((r) => r.kind == DiffKind.same && r.text == 'alpha'), isTrue);
  });

  test('unifiedDiff collapses long unchanged runs', () {
    final lines = List.generate(40, (i) => 'line $i').join('\n');
    final after = '$lines\nchanged';
    final rows = unifiedDiff(lines, after);
    expect(rows.any((r) => r.kind == DiffKind.skip), isTrue);
  });
}
