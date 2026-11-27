import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablekin/main.dart';
import 'package:tablekin/models/models.dart';
import 'package:tablekin/services/local_demo_backend.dart';
import 'package:tablekin/state/app_state.dart';
import 'package:tablekin/utils/availability.dart';
import 'package:tablekin/utils/meal_time.dart';

void main() {
  group('Availability & MealTime logic', () {
    test('buildAvailability computes canMake and lacks accurately', () {
      const dishes = [
        Dish(id: 1, kitchenId: 1, name: '红烧排骨'),
        Dish(id: 2, kitchenId: 1, name: '清炒时蔬'),
      ];
      const ingredients = [
        Ingredient(id: 10, kitchenId: 1, name: '猪肋排', unit: '克', stock: 700),
      ];
      const recipes = [
        DishIngredient(kitchenId: 1, dishId: 1, ingredientId: 10, amount: 300),
      ];

      final map = buildAvailability(dishes, ingredients, recipes);
      expect(map[1]?.canMake, 2);
      expect(map[1]?.soldOut, false);
      expect(map[2]?.canMake, isNull);
    });

    test('checkOrderAvailability detects shortage across dishes', () {
      const dishes = [
        Dish(id: 1, kitchenId: 1, name: '番茄炒蛋'),
        Dish(id: 2, kitchenId: 1, name: '鸡蛋羹'),
      ];
      const ingredients = [
        Ingredient(id: 10, kitchenId: 1, name: '鸡蛋', unit: '个', stock: 4),
      ];
      const recipes = [
        DishIngredient(kitchenId: 1, dishId: 1, ingredientId: 10, amount: 3),
        DishIngredient(kitchenId: 1, dishId: 2, ingredientId: 10, amount: 2),
      ];

      final check = checkOrderAvailability(dishes, ingredients, recipes, {1: 1, 2: 1});
      expect(check.ok, false);
      expect(check.problems.length, 1);
      expect(check.problems.first.needed, 5);
      expect(check.problems.first.short, 1);
    });

    test('validateMealSchedule rejects asap on future date and invalid range', () {
      final tomorrow = todayDateString(DateTime.now().add(const Duration(days: 1)));
      expect(
        validateMealSchedule(orderDate: tomorrow, mealTimeType: 'asap'),
        isNotNull,
      );
      expect(
        validateMealSchedule(
          orderDate: todayDateString(),
          mealTimeType: 'range',
          start: '19:00',
          end: '18:00',
        ),
        isNotNull,
      );
      expect(
        validateMealSchedule(
          orderDate: tomorrow,
          mealTimeType: 'point',
          start: '18:30',
        ),
        isNull,
      );
    });
  });

  group('LocalDemoKitchenBackend end-to-end flow', () {
    test('place order, ack, accept with stock deduction, and finish', () async {
      final backend = LocalDemoKitchenBackend();
      final dishes = await backend.fetchDishes(1);
      final ribs = dishes.firstWhere((d) => d.name == '秘制红烧排骨');

      final beforeIngs = await backend.fetchIngredients(1);
      final beforeRibsStock = beforeIngs.firstWhere((i) => i.name == '猪肋排').stock;

      final order = await backend.createOrder(
        kitchenId: 1,
        items: [CartEntry(dish: ribs, count: 1)],
        dinerName: '测试好友',
        orderDate: todayDateString(),
        mealTimeType: 'asap',
      );
      expect(order.status, 'pending');

      await backend.ackOrder(order.id);
      final acked = await backend.fetchOrder(order.id);
      expect(acked?.ackedAt, isNotNull);

      final acceptRes = await backend.acceptOrder(order.id);
      expect(acceptRes.ok, true);

      final afterIngs = await backend.fetchIngredients(1);
      final afterRibsStock = afterIngs.firstWhere((i) => i.name == '猪肋排').stock;
      expect(afterRibsStock, beforeRibsStock - 350);

      await backend.finishOrder(order.id);
      final done = await backend.fetchOrder(order.id);
      expect(done?.status, 'done');
    });

    test('recount detects stock conflict when expectedStock is stale', () async {
      final backend = LocalDemoKitchenBackend();
      await expectLater(
        () => backend.adjustStock(
          ingredientId: 100,
          mode: 'recount',
          value: 500,
          expectedStock: 100, // stale
        ),
        throwsA(predicate((e) => e.toString().contains('stock_changed'))),
      );
    });

    test('join kitchen by invite code works', () async {
      final backend = LocalDemoKitchenBackend();
      final joined = await backend.joinKitchenByCode('MING2026', nickname: '老铁');
      expect(joined.name, '阿明的小灶');
      final mine = await backend.fetchMyKitchens();
      expect(mine.any((k) => k.id == joined.id), true);
    });
  });

  testWidgets('TablekinApp renders 3 iOS tabs and switches cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.init();

    await tester.pumpWidget(TablekinApp(initialState: state));
    await tester.pumpAndSettle();

    expect(find.text('今天想吃点什么'), findsOneWidget);
    expect(find.text('点菜'), findsOneWidget);
    expect(find.text('下厨'), findsOneWidget);
    expect(find.text('订单'), findsOneWidget);

    await tester.tap(find.text('下厨'));
    await tester.pumpAndSettle();
    expect(find.text('我的厨房'), findsOneWidget);

    await tester.tap(find.text('订单'));
    await tester.pumpAndSettle();
    expect(find.text('我点的'), findsOneWidget);
  });
}
