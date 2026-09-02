extension type const SpeciesId(String raw) {}

extension type const TreeId(String raw) {}

extension type const AnimalId(String raw) {}

extension type const BiomeId(String raw) {}

extension type const TraitId(String raw) {}

/// Seed for deterministic generation. Fixes an individual tree's geometry for
/// the life of the save, and drives every event roll in the simulation.
extension type const Seed(int raw) {}
