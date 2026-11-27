import '../models/models.dart';

double round1(num value) => (value.toDouble() * 10).round() / 10.0;

Map<int, DishAvailability> buildAvailability(
  List<Dish> dishes,
  List<Ingredient> ingredients,
  List<DishIngredient> recipes,
) {
  final stockById = <int, Ingredient>{
    for (final item in ingredients) item.id: item,
  };
  final byDish = <int, List<DishIngredient>>{};
  for (final row in recipes) {
    byDish.putIfAbsent(row.dishId, () => <DishIngredient>[]).add(row);
  }

  final result = <int, DishAvailability>{};
  for (final dish in dishes) {
    final rows = byDish[dish.id] ?? const <DishIngredient>[];
    int? canMake;
    final lacks = <DishShortageDetail>[];
    for (final row in rows) {
      final ingredient = stockById[row.ingredientId];
      if (ingredient == null || row.amount <= 0) continue;
      final possible = (ingredient.stock / row.amount).floor();
      canMake = canMake == null ? possible : (possible < canMake ? possible : canMake);
      if (possible <= 0) {
        lacks.add(
          DishShortageDetail(
            ingredientId: ingredient.id,
            ingredientName: ingredient.name,
            unit: ingredient.unit,
            needed: round1(row.amount),
            stock: round1(ingredient.stock),
            short: round1(row.amount - ingredient.stock),
            dishes: dish.name,
          ),
        );
      }
    }
    result[dish.id] = DishAvailability(
      hasRecipe: rows.isNotEmpty,
      canMake: canMake,
      lacks: lacks,
    );
  }
  return result;
}

OrderAvailabilityCheck checkOrderAvailability(
  List<Dish> dishes,
  List<Ingredient> ingredients,
  List<DishIngredient> recipes,
  Map<int, int> wanted,
) {
  final ingredientById = <int, Ingredient>{
    for (final item in ingredients) item.id: item,
  };
  final dishById = <int, Dish>{
    for (final dish in dishes) dish.id: dish,
  };

  final needed = <int, double>{};
  final dishNames = <int, List<String>>{};

  for (final row in recipes) {
    final count = wanted[row.dishId] ?? 0;
    if (count <= 0 || row.amount <= 0) continue;
    needed[row.ingredientId] = (needed[row.ingredientId] ?? 0) + row.amount * count;
    final dish = dishById[row.dishId];
    if (dish != null) {
      final list = dishNames.putIfAbsent(row.ingredientId, () => <String>[]);
      if (!list.contains(dish.name)) list.add(dish.name);
    }
  }

  final problems = <DishShortageDetail>[];
  needed.forEach((ingredientId, rawNeed) {
    final ingredient = ingredientById[ingredientId];
    if (ingredient == null) return;
    final need = round1(rawNeed);
    final stock = round1(ingredient.stock);
    if (need > stock) {
      problems.add(
        DishShortageDetail(
          ingredientId: ingredient.id,
          ingredientName: ingredient.name,
          unit: ingredient.unit,
          needed: need,
          stock: stock,
          short: round1(need - stock),
          dishes: (dishNames[ingredientId] ?? const []).join('、'),
        ),
      );
    }
  });

  return OrderAvailabilityCheck(ok: problems.isEmpty, problems: problems);
}
