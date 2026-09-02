// Regenerates lib/src/content_asset.g.dart from assets/content.json.
//
// The JSON is the single source of truth; the generated Dart constant is what
// ships, so content loads synchronously at startup with no async asset read.
// `content_asset_test.dart` fails if the two ever diverge.
//
//   dart run tool/embed_content.dart
import 'dart:io';

void main() {
  final json = File('assets/content.json').readAsStringSync();
  if (json.contains('"""')) {
    stderr.writeln(
      'content.json contains a triple quote; cannot embed as a '
      'raw string literal. Reformat the offending value.',
    );
    exit(1);
  }
  // A raw string treats $ and \ literally, so no escaping is needed.
  File('lib/src/content_asset.g.dart').writeAsStringSync('''
// GENERATED — do not edit by hand.
// Source: assets/content.json
// Regenerate with: dart run tool/embed_content.dart

/// Raw MVP content, embedded at build time.
const String kContentAssetJson = r"""
$json""";
''');
  stdout.writeln('embedded ${json.length} bytes');
}
