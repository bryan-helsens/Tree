import 'package:grow_flora/grow_flora.dart';

void main() {
  for (final form in [oakForm, birchForm]) {
    final sw = Stopwatch()..start();
    var branches = 0, leaves = 0;
    for (var i = 0; i < 200; i++) {
      final t = const TreeGenerator().generate(
        rules: form.rules,
        seed: 1000 + i,
        growth01: 0.9,
      );
      branches += t.branches.length;
      leaves += t.leafCount;
    }
    sw.stop();
    print(
      '${form.id}: ${(sw.elapsedMicroseconds / 200).toStringAsFixed(0)}us/tree, '
      '${branches ~/ 200} branches, ${leaves ~/ 200} leaves, '
      '${const TreeGenerator().generate(rules: form.rules, seed: 1, growth01: 0.9).segmentCount} segments',
    );
  }
}
