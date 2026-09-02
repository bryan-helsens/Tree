/// Procedural plant geometry for GROW.
///
/// Pure Dart with no renderer dependency, so a tree can be generated, tested,
/// measured and exported headlessly. `grow_render` draws what this produces;
/// Tree Lab tunes it.
library;

export 'src/branch_rules.dart';
export 'src/foliage.dart';
export 'src/mature_tree.dart';
export 'src/species_forms.dart';
export 'src/tree_generator.dart';
export 'src/tree_skeleton.dart';
export 'src/vec2.dart';
