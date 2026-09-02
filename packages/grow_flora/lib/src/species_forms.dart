import 'branch_rules.dart';
import 'foliage.dart';

/// Shape and colour for the MVP species.
///
/// These live in code for now because Tree Lab writes them; once the numbers
/// settle they move into `content.json` alongside the rest of the species
/// definition, at which point adding a tree is entirely a data change.
class SpeciesForm {
  const SpeciesForm({
    required this.id,
    required this.rules,
    required this.palette,
  });

  final String id;
  final BranchRules rules;
  final FoliagePalette palette;
}

/// Pedunculate Oak — broad, heavy, slow. Wide branch angles and a stout trunk
/// give the domed, spreading silhouette an oak is recognised by.
const oakForm = SpeciesForm(
  id: 'quercus_robur',
  rules: BranchRules(
    maxDepth: 5,
    trunkLength: 104,
    trunkWidth: 18,
    trunkSinuosity: 0.50,
    // High enough that outer branches stay substantial. Decaying length too
    // fast leaves a tuft of twigs on a bare pole rather than a crown.
    lengthDecay: 0.79,
    taper: 0.74,
    branchAngleMin: 28,
    branchAngleMax: 50,
    angleJitter: 13,
    childrenPerBranch: 2,
    firstNodeAt: 0.32,
    apicalExtension: 0.52,
    // Strong enough to curl the outer structure back upward. Without this an
    // oak spreads into a flat mushroom instead of the dome it is known for.
    phototropism: 0.55,
    gravityDroop: 0.14,
    wobble: 0.60,
    leafStartDepth: 3,
    leafDensity: 13,
    leafSize: 4.4,
    canopyBias: 0.55,
    asymmetry: 0.24,
    angleDecay: 0.74,
  ),
  palette: FoliagePalette(
    leafDark: 0xFF2F4A2A,
    leafMid: 0xFF4A6B34,
    leafLight: 0xFF6E8C45,
    barkDark: 0xFF3D3228,
    barkLight: 0xFF6A5A48,
    flowerColor: 0xFFC8C08A,
  ),
);

/// Silver Birch — a narrow, light-hungry pioneer with weeping tips and pale
/// bark. Tight branch angles and strong droop are the whole read.
const birchForm = SpeciesForm(
  id: 'betula_pendula',
  rules: BranchRules(
    maxDepth: 5,
    trunkLength: 128,
    trunkWidth: 11,
    trunkSinuosity: 0.26,
    lengthDecay: 0.80,
    taper: 0.78,
    branchAngleMin: 16,
    branchAngleMax: 34,
    angleJitter: 9,
    childrenPerBranch: 2,
    firstNodeAt: 0.30,
    apicalExtension: 0.60,
    phototropism: 0.70,
    // Birch weeps: the fine tips fall away while the frame stays upright.
    gravityDroop: 0.58,
    wobble: 0.44,
    leafStartDepth: 3,
    leafDensity: 11,
    leafSize: 3.4,
    canopyBias: 0.70,
    asymmetry: 0.16,
    angleDecay: 0.80,
  ),
  palette: FoliagePalette(
    leafDark: 0xFF4A6B33,
    leafMid: 0xFF6E9440,
    leafLight: 0xFF9CB558,
    barkDark: 0xFF9A9384,
    barkLight: 0xFFE4DFD2,
    flowerColor: 0xFFD8D2A8,
  ),
);

const Map<String, SpeciesForm> speciesForms = {
  'quercus_robur': oakForm,
  'betula_pendula': birchForm,
};

SpeciesForm formFor(String speciesId) =>
    speciesForms[speciesId] ??
    (throw ArgumentError('no visual form for species "$speciesId"'));
