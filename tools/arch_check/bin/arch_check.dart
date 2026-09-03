// Enforces the dependency rules in docs/03-project-structure.md.
//
// These boundaries are what keep the simulation testable without a device and
// the engine choice reversible at the rendering layer. A rule that is only
// written down is a rule that erodes, so it is checked.
import 'dart:io';

/// Which packages each package's *library* code may import.
const allowed = <String, Set<String>>{
  'grow_domain': {},
  'grow_sim': {'grow_domain', 'grow_content'},
  'grow_content': {'grow_domain'},
  'grow_data': {'grow_domain'},
  'grow_flora': {'grow_domain'},
  'grow_render': {'grow_domain', 'grow_flora'},
  // A development tool, not shipped code: it is allowed to reach across the
  // whole stack precisely so it can tune the real chain end to end.
  'tree_lab': {
    'grow_domain',
    'grow_content',
    'grow_sim',
    'grow_flora',
    'grow_render',
  },
  'balance_sim': {'grow_domain', 'grow_content', 'grow_sim'},
  // The application shell composes everything; nothing may depend on it.
  'grow_app': {
    'grow_domain',
    'grow_content',
    'grow_sim',
    'grow_flora',
    'grow_render',
  },
  'arch_check': {},
};

/// Packages that legitimately draw or build UI. Everything else must stay
/// device-free so it can be tested headlessly.
const rendererPackages = {'grow_render', 'tree_lab'};

/// Banned in library code, with the reason a reviewer needs.
const bannedImports = <({String needle, String why, Set<String> except})>[
  (
    needle: "import 'dart:io'",
    why: 'dart:io in a pure package — it must run in tests and on the web',
    except: {},
  ),
  (
    needle: "import 'package:flutter/",
    why: 'Flutter in a pure package — the simulation must stay device-free',
    except: rendererPackages,
  ),
];

const bannedApis = <({String pattern, String why})>[
  (
    pattern: r'DateTime\.now\(\s*\)',
    why: 'reads a real clock; elapsed time must arrive as an argument',
  ),
  (
    pattern: r'(?<![\w.])Random\(\s*\)',
    why: 'unseeded randomness breaks determinism; use Xorshift128',
  ),
];

void main() {
  final failures = <String>[];

  for (final root in ['packages', 'tools']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;

    for (final entity in dir.listSync().whereType<Directory>()) {
      final pkg = entity.path.split(Platform.pathSeparator).last;
      final rules = allowed[pkg];

      for (final file
          in entity
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final parts = file.path.split(Platform.pathSeparator);
        // Only `lib/` is library code. Tests, build tools and CLI entrypoints
        // legitimately reach outside; the rules exist to protect what ships.
        final isLibrary = parts.contains('lib');
        final raw = file.readAsStringSync();
        final code = _stripCommentsAndStrings(raw);

        for (final m in RegExp(r"import 'package:(\w+)/").allMatches(raw)) {
          final imported = m.group(1)!;
          if (imported == pkg || !allowed.containsKey(imported)) continue;
          if (isLibrary && rules != null && !rules.contains(imported)) {
            failures.add('${file.path}\n      $pkg may not import $imported');
          }
        }

        if (!isLibrary) continue;
        for (final rule in bannedImports) {
          if (rule.except.contains(pkg)) continue;
          if (raw.contains(rule.needle)) {
            failures.add('${file.path}\n      ${rule.why}');
          }
        }
        for (final rule in bannedApis) {
          if (RegExp(rule.pattern).hasMatch(code)) {
            failures.add('${file.path}\n      ${rule.why}');
          }
        }
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('arch_check: all boundaries hold');
    return;
  }
  stderr.writeln('arch_check: ${failures.length} violation(s)\n');
  for (final f in failures) {
    stderr.writeln('  $f\n');
  }
  exit(1);
}

/// Blanks out comments and string literals so a rule quoted in prose is not
/// mistaken for a rule being broken.
String _stripCommentsAndStrings(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final rest = src.length - i;
    if (rest >= 2 && src[i] == '/' && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (rest >= 2 && src[i] == '/' && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    if (src[i] == "'" || src[i] == '"') {
      final quote = src[i];
      final triple = rest >= 3 && src[i + 1] == quote && src[i + 2] == quote;
      final delim = triple ? quote * 3 : quote;
      i += delim.length;
      while (i < src.length) {
        if (src[i] == r'\') {
          i += 2;
          continue;
        }
        if (src.startsWith(delim, i)) {
          i += delim.length;
          break;
        }
        i++;
      }
      out.write('""');
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}
