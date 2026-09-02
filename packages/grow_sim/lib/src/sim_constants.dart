/// Every tunable number in the simulation, in one place.
///
/// These are starting values for `tools/balance_sim`, not final numbers. The
/// *shapes* of the curves encode the design intent and should be changed
/// deliberately; the magnitudes are expected to move.
class SimConstants {
  const SimConstants({
    this.baseWaterLossPerHour = 1.15,
    this.baseNutrientLossPerHour = 0.55,
    this.leachThreshold = 85.0,
    this.leachRate = 0.03,
    this.healPerHour = 3.2,
    this.harmPerHour = 1.1,
    this.growthComfortExponent = 1.6,
    this.healthGateFloor = 25.0,
    this.healthGateSpan = 45.0,
    this.comfortWeightWater = 1.5,
    this.comfortWeightNutrition = 1.0,
    this.comfortWeightLight = 0.8,
    this.comfortWeightTemperature = 0.6,
    this.dormancyAfterHours = 72.0,
    this.dormancyWaterRest = 25.0,
    this.dormancyNutritionRest = 30.0,
    this.dormancyWaterTauHours = 36.0,
    this.dormancyNutritionTauHours = 48.0,
    this.dormancyHarmScale = 0.25,
    this.dormancyHealthFloor = 15.0,
    this.criticalHoursToDeath = 120.0,
    this.criticalRecoveryRate = 2.0,
    this.minCriticalSightings = 2,
    this.pestBaseChancePerHour = 0.004,
    this.fungusChancePerHour = 0.02,
    this.fungusWetThreshold = 82.0,
    this.fungusWetHoursRequired = 6.0,
    this.nutrientBurnMargin = 18.0,
    this.animalVisitBaseChance = 0.05,
    this.afflictionHealthPenalty = 12.0,
    this.afflictionDecayPerHour = 0.02,
  });

  /// Baseline moisture loss, percentage points per hour, before species,
  /// stage, weather and soil multipliers.
  final double baseWaterLossPerHour;
  final double baseNutrientLossPerHour;

  /// Above this moisture, nutrients wash out of the soil. Over-caring in one
  /// dimension costs you in another — expressed as physics, not as a popup.
  final double leachThreshold;
  final double leachRate;

  /// Healing runs roughly 3x faster than harm. The forgiveness the design
  /// requires is the formula, not a special case bolted on top.
  final double healPerHour;
  final double harmPerHour;

  final double growthComfortExponent;
  final double healthGateFloor;
  final double healthGateSpan;

  final double comfortWeightWater;
  final double comfortWeightNutrition;
  final double comfortWeightLight;
  final double comfortWeightTemperature;

  /// Absence past this many hours switches a tree to dormancy dynamics.
  final double dormancyAfterHours;
  final double dormancyWaterRest;
  final double dormancyNutritionRest;
  final double dormancyWaterTauHours;
  final double dormancyNutritionTauHours;
  final double dormancyHarmScale;

  /// Health can never fall below this while dormant, which is what makes
  /// "a tree cannot die from absence alone" true by construction.
  final double dormancyHealthFloor;

  final double criticalHoursToDeath;
  final double criticalRecoveryRate;
  final int minCriticalSightings;

  final double pestBaseChancePerHour;
  final double fungusChancePerHour;
  final double fungusWetThreshold;
  final double fungusWetHoursRequired;
  final double nutrientBurnMargin;
  final double animalVisitBaseChance;

  /// Health points per hour subtracted at full affliction severity.
  final double afflictionHealthPenalty;
  final double afflictionDecayPerHour;

  double get comfortWeightSum =>
      comfortWeightWater +
      comfortWeightNutrition +
      comfortWeightLight +
      comfortWeightTemperature;

  SimConstants copyWith({
    double? baseWaterLossPerHour,
    double? healPerHour,
    double? harmPerHour,
    double? growthComfortExponent,
    double? dormancyAfterHours,
  }) => SimConstants(
    baseWaterLossPerHour: baseWaterLossPerHour ?? this.baseWaterLossPerHour,
    baseNutrientLossPerHour: baseNutrientLossPerHour,
    leachThreshold: leachThreshold,
    leachRate: leachRate,
    healPerHour: healPerHour ?? this.healPerHour,
    harmPerHour: harmPerHour ?? this.harmPerHour,
    growthComfortExponent: growthComfortExponent ?? this.growthComfortExponent,
    healthGateFloor: healthGateFloor,
    healthGateSpan: healthGateSpan,
    comfortWeightWater: comfortWeightWater,
    comfortWeightNutrition: comfortWeightNutrition,
    comfortWeightLight: comfortWeightLight,
    comfortWeightTemperature: comfortWeightTemperature,
    dormancyAfterHours: dormancyAfterHours ?? this.dormancyAfterHours,
    dormancyWaterRest: dormancyWaterRest,
    dormancyNutritionRest: dormancyNutritionRest,
    dormancyWaterTauHours: dormancyWaterTauHours,
    dormancyNutritionTauHours: dormancyNutritionTauHours,
    dormancyHarmScale: dormancyHarmScale,
    dormancyHealthFloor: dormancyHealthFloor,
    criticalHoursToDeath: criticalHoursToDeath,
    criticalRecoveryRate: criticalRecoveryRate,
    minCriticalSightings: minCriticalSightings,
    pestBaseChancePerHour: pestBaseChancePerHour,
    fungusChancePerHour: fungusChancePerHour,
    fungusWetThreshold: fungusWetThreshold,
    fungusWetHoursRequired: fungusWetHoursRequired,
    nutrientBurnMargin: nutrientBurnMargin,
    animalVisitBaseChance: animalVisitBaseChance,
    afflictionHealthPenalty: afflictionHealthPenalty,
    afflictionDecayPerHour: afflictionDecayPerHour,
  );
}

const SimConstants kDefaultConstants = SimConstants();
