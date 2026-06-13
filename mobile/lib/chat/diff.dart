/// Line-level unified diff for AI proposal cards — an LCS walk, ported from the
/// web client (DESIGN.md). Plenty at personal scale, where prose runs hundreds
/// of lines, not millions.
library;

enum DiffKind { same, add, del, skip }

class DiffRow {
  final DiffKind kind;
  final String text;
  final int count; // only for `skip`
  const DiffRow(this.kind, {this.text = '', this.count = 0});
}

List<DiffRow> unifiedDiff(String before, String after, {int context = 3}) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  final n = a.length;
  final m = b.length;

  // Degenerate guard: beyond this, show a full replacement rather than burn
  // time on the DP table.
  if (n * m > 2000000) {
    return [
      ...a.map((t) => DiffRow(DiffKind.del, text: t)),
      ...b.map((t) => DiffRow(DiffKind.add, text: t)),
    ];
  }

  final w = m + 1;
  final dp = List<int>.filled((n + 1) * w, 0);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i * w + j] = a[i] == b[j]
          ? dp[(i + 1) * w + j + 1] + 1
          : (dp[(i + 1) * w + j] > dp[i * w + j + 1]
              ? dp[(i + 1) * w + j]
              : dp[i * w + j + 1]);
    }
  }

  final ops = <DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(DiffRow(DiffKind.same, text: a[i]));
      i++;
      j++;
    } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
      ops.add(DiffRow(DiffKind.del, text: a[i]));
      i++;
    } else {
      ops.add(DiffRow(DiffKind.add, text: b[j]));
      j++;
    }
  }
  while (i < n) {
    ops.add(DiffRow(DiffKind.del, text: a[i++]));
  }
  while (j < m) {
    ops.add(DiffRow(DiffKind.add, text: b[j++]));
  }

  // Collapse long unchanged runs to `context` lines on each side.
  final rows = <DiffRow>[];
  var sameBuf = <String>[];
  var seenChange = false;
  void flush(bool atEnd) {
    final head = seenChange ? (context < sameBuf.length ? context : sameBuf.length) : 0;
    final remaining = sameBuf.length - head;
    final tail = atEnd ? 0 : (context < remaining ? context : remaining);
    final skipped = sameBuf.length - head - tail;
    if (skipped > 2) {
      for (var k = 0; k < head; k++) {
        rows.add(DiffRow(DiffKind.same, text: sameBuf[k]));
      }
      rows.add(DiffRow(DiffKind.skip, count: skipped));
      for (var k = sameBuf.length - tail; k < sameBuf.length; k++) {
        rows.add(DiffRow(DiffKind.same, text: sameBuf[k]));
      }
    } else {
      for (final t in sameBuf) {
        rows.add(DiffRow(DiffKind.same, text: t));
      }
    }
    sameBuf = [];
  }

  for (final op in ops) {
    if (op.kind == DiffKind.same) {
      sameBuf.add(op.text);
    } else {
      flush(false);
      seenChange = true;
      rows.add(op);
    }
  }
  flush(true);
  return rows;
}
