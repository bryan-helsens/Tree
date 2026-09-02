/// Content definitions for GROW: species, biomes and the weather table.
///
/// Data, not code. Adding the fortieth species must never require touching
/// `grow_sim` (docs/02-system-architecture.md §4).
library;

import 'src/content_asset.g.dart';
import 'src/content_bundle.dart';

export 'src/content_bundle.dart';
export 'src/tree_species.dart';

ContentBundle? _cached;

/// The MVP content bundle, parsed once and cached.
ContentBundle mvpContent() =>
    _cached ??= ContentBundle.parse(kContentAssetJson);
