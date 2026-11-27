import 'dart:typed_data';
import '../models/models.dart';

/// Abstract backend interface for Tablekin.
///
/// Decouples UI & state management from any specific cloud provider:
/// - [SupabaseKitchenBackend]: Recommended cloud backend (PostgreSQL + RLS + Realtime + Storage)
/// - [LocalDemoKitchenBackend]: Zero-config interactive demo backend
/// - Easily extensible to Cloudflare Workers + D1 or other backends in the future.
abstract class KitchenBackend {
  String get backendName;
  bool get isCloud;

  AppUser? get currentUser;

  Future<AppUser?> restoreSession();
  Future<AppUser> signInWithPassword(String email, String password);
  Future<AppUser> signUpWithPassword(String email, String password, {String? displayName});
  Future<void> signOut();

  // Optional Realtime subscription hook
  void subscribeLiveUpdates(void Function() onChanged);
  void unsubscribeLiveUpdates();

  // Kitchens
  Future<List<Kitchen>> fetchMyKitchens();
  Future<Kitchen?> fetchKitchen(int kitchenId);
  Future<List<Kitchen>> searchKitchens({String keyword = ''});
  Future<Map<int, int>> countPublicDishes(List<int> kitchenIds);
  Future<Kitchen> createKitchen({
    required String name,
    String description = '',
    bool isPublic = true,
    String nickname = '',
  });
  Future<Kitchen> updateKitchen(
    int kitchenId, {
    required String name,
    required String description,
    required bool isPublic,
  });
  Future<void> deleteKitchen(int kitchenId);

  // Invites & Members
  Future<KitchenInvite> getKitchenInvite(int kitchenId);
  Future<KitchenInvite> resetKitchenInvite(int kitchenId);
  Future<Kitchen> joinKitchenByCode(String code, {String nickname = ''});
  Future<List<KitchenMember>> fetchMembers(int kitchenId);
  Future<KitchenMember> updateMemberNickname(int memberId, String nickname);
  Future<void> removeMember(int memberId);

  // Categories
  Future<List<Category>> fetchCategories(int kitchenId, {bool publicOnly = false});
  Future<Category> createCategory(int kitchenId, String name, {bool isPublic = true});
  Future<Category> updateCategory(int categoryId, {String? name, bool? isPublic});
  Future<void> deleteCategory(int categoryId);

  // Dishes & Tags
  Future<List<Dish>> fetchDishes(
    int kitchenId, {
    bool publicOnly = false,
    List<String> tags = const [],
    String tagMode = 'all',
  });
  Future<Dish?> fetchDish(int dishId);
  Future<List<Dish>> searchDishes({
    String keyword = '',
    int? kitchenId,
    List<String> tags = const [],
    String tagMode = 'all',
  });
  Future<List<TagCount>> listKitchenTags({int kitchenId = 0});
  Future<Dish> createDish({
    required int kitchenId,
    int? categoryId,
    required String name,
    String description = '',
    String recipe = '',
    List<String> imagePaths = const [],
    List<String> tags = const [],
    bool isPublic = true,
    bool isRecipePublic = true,
    bool isAvailable = true,
  });
  Future<Dish> updateDish(
    int dishId, {
    int? categoryId,
    bool clearCategory = false,
    String? name,
    String? description,
    String? recipe,
    List<String>? imagePaths,
    List<String>? tags,
    bool? isPublic,
    bool? isRecipePublic,
    bool? isAvailable,
  });
  Future<void> deleteDish(int dishId);
  Future<void> reorderKitchenItems(int kitchenId, String kind, List<int> ids, List<int> expectedIds);

  // Images
  Future<String> uploadDishImage(Uint8List bytes, String filename);
  Future<Map<String, String>> signImageUrls(List<String> paths);

  // Ingredients & Recipes
  Future<List<Ingredient>> fetchIngredients(int kitchenId);
  Future<Ingredient> createIngredient({
    required int kitchenId,
    required String name,
    required String unit,
    required double initialStock,
    double alertThreshold = 0,
  });
  Future<Ingredient> updateIngredient(
    int ingredientId, {
    required String name,
    required String unit,
    required double alertThreshold,
  });
  Future<void> deleteIngredient(int ingredientId);
  Future<double> adjustStock({
    required int ingredientId,
    required String mode, // 'delta' | 'recount'
    required double value,
    double? expectedStock,
    String reason = '',
    String? requestId,
  });
  Future<List<StockLog>> fetchStockLogs(int ingredientId);
  Future<List<DishIngredient>> fetchRecipes({int? kitchenId, int? dishId});
  Future<void> replaceDishIngredients(int dishId, int kitchenId, List<DishIngredient> rows);

  // Orders
  Future<KitchenOrder> createOrder({
    required int kitchenId,
    required List<CartEntry> items,
    required String dinerName,
    String note = '',
    required String orderDate,
    required String mealTimeType,
    String? mealTimeStart,
    String? mealTimeEnd,
  });
  Future<List<KitchenOrder>> fetchMyOrders();
  Future<List<KitchenOrder>> fetchReceivedOrders(List<int> kitchenIds);
  Future<KitchenOrder?> fetchOrder(int orderId);
  Future<void> ackOrder(int orderId);
  Future<AcceptOrderResult> acceptOrder(int orderId);
  Future<void> finishOrder(int orderId);
  Future<void> rejectOrder(int orderId, {String reason = ''});
  Future<void> cancelOrder(int orderId);

  // Shortage Alerts & Notifications & Badges
  Future<void> reportShortage({
    required int kitchenId,
    required String dinerName,
    required List<DishShortageDetail> problems,
  });
  Future<List<ShortageAlert>> fetchShortageAlerts({int? kitchenId});
  Future<void> markShortageAlertsRead(List<int> ids);
  Future<Map<int, KitchenBadge>> fetchKitchenBadges(List<int> kitchenIds);
  Future<List<AppNotification>> fetchUnreadNotifications();
  Future<void> markNotificationsRead({List<int>? ids});

  /// Demo-only helper to simulate a friend placing an order to your kitchen.
  Future<KitchenOrder?> simulateFriendOrder() async => null;
}
