import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../utils/availability.dart';
import 'kitchen_backend.dart';

class SupabaseKitchenBackend implements KitchenBackend {
  final SupabaseClient client;
  RealtimeChannel? _channel;

  SupabaseKitchenBackend(this.client);

  @override
  String get backendName => 'Supabase 云端同步';

  @override
  bool get isCloud => true;

  AppUser? _mapUser(User? user) {
    if (user == null) return null;
    final metaName = user.userMetadata?['display_name']?.toString() ?? '';
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      displayName: metaName.isNotEmpty
          ? metaName
          : (user.email ?? '用户').split('@').first,
    );
  }

  @override
  AppUser? get currentUser => _mapUser(client.auth.currentUser);

  @override
  Future<AppUser?> restoreSession() async => currentUser;

  @override
  Future<AppUser> signInWithPassword(String email, String password) async {
    final res = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final mapped = _mapUser(res.user);
    if (mapped == null) throw Exception('not_signed_in');
    return mapped;
  }

  @override
  Future<AppUser> signUpWithPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    final res = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: displayName != null && displayName.trim().isNotEmpty
          ? {'display_name': displayName.trim()}
          : null,
    );
    final mapped = _mapUser(res.user);
    if (mapped == null) {
      throw Exception('注册已提交，请查收邮箱验证邮件后再登录');
    }
    return mapped;
  }

  @override
  Future<void> signOut() async {
    unsubscribeLiveUpdates();
    await client.auth.signOut();
  }

  @override
  void subscribeLiveUpdates(void Function() onChanged) {
    unsubscribeLiveUpdates();
    _channel = client
        .channel('tablekin-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shortage_alerts',
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  @override
  void unsubscribeLiveUpdates() {
    if (_channel != null) {
      client.removeChannel(_channel!);
      _channel = null;
    }
  }

  String _requireUid() {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw Exception('not_signed_in');
    return uid;
  }

  @override
  Future<List<Kitchen>> fetchMyKitchens() async {
    final uid = _requireUid();
    final rows = await client
        .from('kitchen_members')
        .select(
          'id, role, nickname, kitchen_id, kitchen:kitchens(id, name, description, cover_path, is_public, owner_id, created_at)',
        )
        .eq('user_id', uid)
        .order('id', ascending: true);

    final list = <Kitchen>[];
    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final kRaw = row['kitchen'];
      if (kRaw is Map) {
        list.add(
          Kitchen.fromJson(
            Map<String, dynamic>.from(kRaw),
            memberId: (row['id'] as num?)?.toInt(),
            role: row['role']?.toString(),
            myNickname: row['nickname']?.toString(),
            currentUserId: uid,
          ),
        );
      }
    }
    return list;
  }

  @override
  Future<Kitchen?> fetchKitchen(int kitchenId) async {
    final uid = _requireUid();
    final row = await client
        .from('kitchens')
        .select('*')
        .eq('id', kitchenId)
        .maybeSingle();
    if (row == null) return null;
    final member = await client
        .from('kitchen_members')
        .select('id, role, nickname')
        .eq('kitchen_id', kitchenId)
        .eq('user_id', uid)
        .maybeSingle();
    return Kitchen.fromJson(
      Map<String, dynamic>.from(row),
      memberId: (member?['id'] as num?)?.toInt(),
      role: member?['role']?.toString(),
      myNickname: member?['nickname']?.toString(),
      currentUserId: uid,
    );
  }

  @override
  Future<List<Kitchen>> searchKitchens({String keyword = ''}) async {
    final uid = _requireUid();
    final kw = keyword.trim();
    var query = client.from('kitchens').select('*');
    if (kw.isNotEmpty) {
      query = query.ilike('name', '%$kw%');
    } else {
      query = query.eq('is_public', true);
    }
    final rows = await query.order('created_at', ascending: false).limit(30);
    return (rows as List)
        .map((e) => Kitchen.fromJson(Map<String, dynamic>.from(e as Map), currentUserId: uid))
        .toList();
  }

  @override
  Future<Map<int, int>> countPublicDishes(List<int> kitchenIds) async {
    if (kitchenIds.isEmpty) return {};
    _requireUid();
    final rows = await client
        .from('dishes')
        .select('kitchen_id, is_available')
        .inFilter('kitchen_id', kitchenIds)
        .eq('is_public', true);
    final result = {for (final id in kitchenIds) id: 0};
    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final kId = (row['kitchen_id'] as num?)?.toInt();
      if (kId != null && result.containsKey(kId) && row['is_available'] != false) {
        result[kId] = (result[kId] ?? 0) + 1;
      }
    }
    return result;
  }

  @override
  Future<Kitchen> createKitchen({
    required String name,
    String description = '',
    bool isPublic = true,
    String nickname = '',
  }) async {
    _requireUid();
    final data = await client.rpc('create_kitchen_atomic', params: {
      'p_name': name.trim(),
      'p_description': description.trim().isEmpty ? null : description.trim(),
      'p_is_public': isPublic,
      'p_cover_path': null,
      'p_nickname': nickname.trim().isEmpty ? null : nickname.trim(),
    });
    final map = Map<String, dynamic>.from(data as Map);
    final kitchenId = (map['kitchen_id'] as num).toInt();
    final created = await fetchKitchen(kitchenId);
    if (created == null) throw Exception('厨房创建失败，请重试');
    return created;
  }

  @override
  Future<Kitchen> updateKitchen(
    int kitchenId, {
    required String name,
    required String description,
    required bool isPublic,
  }) async {
    final uid = _requireUid();
    final rows = await client
        .from('kitchens')
        .update({
          'name': name.trim(),
          'description': description.trim().isEmpty ? null : description.trim(),
          'is_public': isPublic,
        })
        .eq('id', kitchenId)
        .select();
    if ((rows as List).isEmpty) throw Exception('没有厨房被修改，可能你没有管理权限');
    return Kitchen.fromJson(Map<String, dynamic>.from(rows.first as Map), currentUserId: uid);
  }

  @override
  Future<void> deleteKitchen(int kitchenId) async {
    _requireUid();
    await client.from('kitchens').delete().eq('id', kitchenId);
  }

  @override
  Future<KitchenInvite> getKitchenInvite(int kitchenId) async {
    _requireUid();
    final data = await client.rpc('get_kitchen_invite', params: {'p_kitchen_id': kitchenId});
    return KitchenInvite.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<KitchenInvite> resetKitchenInvite(int kitchenId) async {
    _requireUid();
    final data = await client.rpc('reset_kitchen_invite', params: {'p_kitchen_id': kitchenId});
    return KitchenInvite.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<Kitchen> joinKitchenByCode(String code, {String nickname = ''}) async {
    _requireUid();
    final data = await client.rpc('join_kitchen_by_code', params: {
      'code': code.trim(),
      'nick': nickname.trim(),
    });
    final map = Map<String, dynamic>.from(data as Map);
    final kitchenId = (map['kitchen_id'] as num).toInt();
    final kitchen = await fetchKitchen(kitchenId);
    if (kitchen == null) throw Exception('kitchen_not_found');
    return kitchen;
  }

  @override
  Future<List<KitchenMember>> fetchMembers(int kitchenId) async {
    _requireUid();
    final rows = await client
        .from('kitchen_members')
        .select('*')
        .eq('kitchen_id', kitchenId)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => KitchenMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<KitchenMember> updateMemberNickname(int memberId, String nickname) async {
    _requireUid();
    final rows = await client
        .from('kitchen_members')
        .update({'nickname': nickname.trim()})
        .eq('id', memberId)
        .select();
    if ((rows as List).isEmpty) throw Exception('没有成员被修改');
    return KitchenMember.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<void> removeMember(int memberId) async {
    _requireUid();
    await client.from('kitchen_members').delete().eq('id', memberId);
  }

  @override
  Future<List<Category>> fetchCategories(int kitchenId, {bool publicOnly = false}) async {
    _requireUid();
    var query = client.from('categories').select('*').eq('kitchen_id', kitchenId);
    if (publicOnly) query = query.eq('is_public', true);
    final rows = await query.order('sort_order', ascending: true).order('id', ascending: true);
    return (rows as List)
        .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Category> createCategory(int kitchenId, String name, {bool isPublic = true}) async {
    final uid = _requireUid();
    final rows = await client
        .from('categories')
        .insert({
          'kitchen_id': kitchenId,
          'owner_id': uid,
          'name': name.trim(),
          'is_public': isPublic,
        })
        .select();
    return Category.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
  }

  @override
  Future<Category> updateCategory(int categoryId, {String? name, bool? isPublic}) async {
    _requireUid();
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.trim();
    if (isPublic != null) payload['is_public'] = isPublic;
    final rows = await client.from('categories').update(payload).eq('id', categoryId).select();
    return Category.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
  }

  @override
  Future<void> deleteCategory(int categoryId) async {
    _requireUid();
    await client.from('categories').delete().eq('id', categoryId);
  }

  @override
  Future<List<Dish>> fetchDishes(
    int kitchenId, {
    bool publicOnly = false,
    List<String> tags = const [],
    String tagMode = 'all',
  }) async {
    _requireUid();
    var query = client.from('dishes').select('*').eq('kitchen_id', kitchenId);
    if (publicOnly) query = query.eq('is_public', true);
    if (tags.isNotEmpty) {
      query = tagMode == 'any' ? query.overlaps('tags', tags) : query.contains('tags', tags);
    }
    final rows = await query.order('sort_order', ascending: true).order('id', ascending: true);
    return (rows as List)
        .map((e) => Dish.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Dish?> fetchDish(int dishId) async {
    _requireUid();
    final row = await client.from('dishes').select('*').eq('id', dishId).maybeSingle();
    if (row == null) return null;
    return Dish.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<Dish>> searchDishes({
    String keyword = '',
    int? kitchenId,
    List<String> tags = const [],
    String tagMode = 'all',
  }) async {
    _requireUid();
    final kw = keyword.trim();
    if (kw.isEmpty && tags.isEmpty) return [];
    var query = client.from('dishes').select('*');
    if (kw.isNotEmpty) query = query.ilike('name', '%$kw%');
    if (kitchenId != null) query = query.eq('kitchen_id', kitchenId);
    if (tags.isNotEmpty) {
      query = tagMode == 'any' ? query.overlaps('tags', tags) : query.contains('tags', tags);
    }
    final rows = await query.order('id', ascending: true).limit(60);
    return (rows as List)
        .map((e) => Dish.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<TagCount>> listKitchenTags({int kitchenId = 0}) async {
    _requireUid();
    final data = await client.rpc('list_kitchen_tags', params: {
      'p_kitchen_id': kitchenId,
      'p_limit': 60,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final rawTags = (map['tags'] as List?) ?? const [];
    return rawTags.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      return TagCount(
        name: (m['tag'] ?? '').toString(),
        count: (m['dish_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  @override
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
  }) async {
    final uid = _requireUid();
    final rows = await client
        .from('dishes')
        .insert({
          'kitchen_id': kitchenId,
          'category_id': categoryId,
          'owner_id': uid,
          'name': name.trim(),
          'description': description.trim().isEmpty ? null : description.trim(),
          'recipe': recipe.trim().isEmpty ? null : recipe.trim(),
          'image_path': imagePaths.isNotEmpty ? imagePaths.first : null,
          'image_paths': imagePaths,
          'tags': tags,
          'is_public': isPublic,
          'is_recipe_public': isRecipePublic,
          'is_available': isAvailable,
        })
        .select();
    return Dish.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
  }

  @override
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
  }) async {
    _requireUid();
    final payload = <String, dynamic>{};
    if (clearCategory) {
      payload['category_id'] = null;
    } else if (categoryId != null) {
      payload['category_id'] = categoryId;
    }
    if (name != null) payload['name'] = name.trim();
    if (description != null) payload['description'] = description.trim();
    if (recipe != null) payload['recipe'] = recipe.trim();
    if (imagePaths != null) {
      payload['image_paths'] = imagePaths;
      payload['image_path'] = imagePaths.isNotEmpty ? imagePaths.first : null;
    }
    if (tags != null) payload['tags'] = tags;
    if (isPublic != null) payload['is_public'] = isPublic;
    if (isRecipePublic != null) payload['is_recipe_public'] = isRecipePublic;
    if (isAvailable != null) payload['is_available'] = isAvailable;

    final rows = await client.from('dishes').update(payload).eq('id', dishId).select();
    return Dish.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
  }

  @override
  Future<void> deleteDish(int dishId) async {
    _requireUid();
    await client.from('dishes').delete().eq('id', dishId);
  }

  @override
  Future<void> reorderKitchenItems(
    int kitchenId,
    String kind,
    List<int> ids,
    List<int> expectedIds,
  ) async {
    _requireUid();
    await client.rpc('reorder_kitchen_items', params: {
      'p_kitchen_id': kitchenId,
      'p_kind': kind,
      'p_ids': ids,
      'p_expected_ids': expectedIds,
    });
  }

  @override
  Future<String> uploadDishImage(Uint8List bytes, String filename) async {
    final uid = _requireUid();
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'jpg';
    final path = '$uid/dishes/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from('dish-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    return path;
  }

  @override
  Future<Map<String, String>> signImageUrls(List<String> paths) async {
    final unique = paths.where((p) => p.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return {};
    try {
      final signed = await client.storage.from('dish-images').createSignedUrls(unique, 3600);
      return {for (final item in signed) item.path: item.signedUrl};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<List<Ingredient>> fetchIngredients(int kitchenId) async {
    _requireUid();
    final rows = await client
        .from('ingredients')
        .select('*')
        .eq('kitchen_id', kitchenId)
        .order('sort_order', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Ingredient> createIngredient({
    required int kitchenId,
    required String name,
    required String unit,
    required double initialStock,
    double alertThreshold = 0,
  }) async {
    final uid = _requireUid();
    final rows = await client
        .from('ingredients')
        .insert({
          'kitchen_id': kitchenId,
          'owner_id': uid,
          'name': name.trim(),
          'unit': unit.trim().isEmpty ? '份' : unit.trim(),
          'alert_threshold': alertThreshold,
        })
        .select();
    var created = Ingredient.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
    if (initialStock > 0) {
      final balance = await adjustStock(
        ingredientId: created.id,
        mode: 'recount',
        value: initialStock,
        expectedStock: 0,
        reason: '新建食材初始库存',
        requestId: 'initial-${created.id}',
      );
      created = created.copyWith(stock: balance);
    }
    return created;
  }

  @override
  Future<Ingredient> updateIngredient(
    int ingredientId, {
    required String name,
    required String unit,
    required double alertThreshold,
  }) async {
    _requireUid();
    final rows = await client
        .from('ingredients')
        .update({
          'name': name.trim(),
          'unit': unit.trim(),
          'alert_threshold': alertThreshold,
        })
        .eq('id', ingredientId)
        .select();
    return Ingredient.fromJson(Map<String, dynamic>.from((rows as List).first as Map));
  }

  @override
  Future<void> deleteIngredient(int ingredientId) async {
    _requireUid();
    await client.from('ingredients').delete().eq('id', ingredientId);
  }

  @override
  Future<double> adjustStock({
    required int ingredientId,
    required String mode,
    required double value,
    double? expectedStock,
    String reason = '',
    String? requestId,
  }) async {
    _requireUid();
    final data = await client.rpc('adjust_stock_atomic', params: {
      'p_ingredient_id': ingredientId,
      'p_mode': mode,
      'p_value': value,
      'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      'p_expected_stock': mode == 'recount' ? expectedStock : null,
      'p_request_id': requestId,
    });
    final map = Map<String, dynamic>.from(data as Map);
    return (map['balance'] as num?)?.toDouble() ?? 0;
  }

  @override
  Future<List<StockLog>> fetchStockLogs(int ingredientId) async {
    _requireUid();
    final rows = await client
        .from('stock_logs')
        .select('*')
        .eq('ingredient_id', ingredientId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => StockLog.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<DishIngredient>> fetchRecipes({int? kitchenId, int? dishId}) async {
    _requireUid();
    var query = client.from('dish_ingredients').select('*');
    if (dishId != null) {
      query = query.eq('dish_id', dishId);
    } else if (kitchenId != null) {
      query = query.eq('kitchen_id', kitchenId);
    }
    final rows = await query.order('id', ascending: true);
    return (rows as List)
        .map((e) => DishIngredient.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> replaceDishIngredients(int dishId, int kitchenId, List<DishIngredient> rows) async {
    _requireUid();
    await client.from('dish_ingredients').delete().eq('dish_id', dishId);
    final payload = rows
        .where((r) => r.amount > 0)
        .map((r) => {
              'dish_id': dishId,
              'kitchen_id': kitchenId,
              'ingredient_id': r.ingredientId,
              'amount': r.amount,
            })
        .toList();
    if (payload.isNotEmpty) {
      await client.from('dish_ingredients').insert(payload);
    }
  }

  Future<List<KitchenOrder>> _hydrateOrders(List<dynamic> rawOrders) async {
    if (rawOrders.isEmpty) return [];
    final orderMaps = rawOrders.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final orderIds = orderMaps.map((e) => (e['id'] as num).toInt()).toList();
    final kitchenIds = orderMaps.map((e) => (e['kitchen_id'] as num).toInt()).toSet().toList();

    final itemRows = await client
        .from('order_items')
        .select('*')
        .inFilter('order_id', orderIds)
        .order('id', ascending: true);
    final itemsByOrder = <int, List<OrderItem>>{};
    for (final raw in (itemRows as List)) {
      final item = OrderItem.fromJson(Map<String, dynamic>.from(raw as Map));
      itemsByOrder.putIfAbsent(item.orderId, () => <OrderItem>[]).add(item);
    }

    final kitchenRows = await client.from('kitchens').select('id, name').inFilter('id', kitchenIds);
    final kitchenNameById = <int, String>{
      for (final raw in (kitchenRows as List))
        ((raw as Map)['id'] as num).toInt(): (raw['name'] ?? '').toString(),
    };

    return orderMaps.map((m) {
      final id = (m['id'] as num).toInt();
      final kId = (m['kitchen_id'] as num).toInt();
      return KitchenOrder.fromJson(
        m,
        items: itemsByOrder[id] ?? const [],
        kitchenName: kitchenNameById[kId] ?? '',
      );
    }).toList();
  }

  @override
  Future<KitchenOrder> createOrder({
    required int kitchenId,
    required List<CartEntry> items,
    required String dinerName,
    String note = '',
    required String orderDate,
    required String mealTimeType,
    String? mealTimeStart,
    String? mealTimeEnd,
  }) async {
    _requireUid();
    final data = await client.rpc('create_order_atomic', params: {
      'p_kitchen_id': kitchenId,
      'p_items': items.map((e) => {'dish_id': e.dish.id, 'quantity': e.count}).toList(),
      'p_note': note.trim().isEmpty ? null : note.trim(),
      'p_diner_name': dinerName.trim().isEmpty ? null : dinerName.trim(),
      'p_meal_time_type': mealTimeType,
      'p_meal_time_start': mealTimeStart,
      'p_meal_time_end': mealTimeEnd,
      'p_order_date': orderDate,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final orderId = (map['order_id'] as num).toInt();
    final created = await fetchOrder(orderId);
    if (created == null) throw Exception('下单失败，请重试');
    return created;
  }

  @override
  Future<List<KitchenOrder>> fetchMyOrders() async {
    final uid = _requireUid();
    final rows = await client
        .from('orders')
        .select('*')
        .eq('diner_id', uid)
        .order('created_at', ascending: false)
        .limit(60);
    return _hydrateOrders(rows as List);
  }

  @override
  Future<List<KitchenOrder>> fetchReceivedOrders(List<int> kitchenIds) async {
    if (kitchenIds.isEmpty) return [];
    _requireUid();
    final rows = await client
        .from('orders')
        .select('*')
        .inFilter('kitchen_id', kitchenIds)
        .order('created_at', ascending: false)
        .limit(60);
    return _hydrateOrders(rows as List);
  }

  @override
  Future<KitchenOrder?> fetchOrder(int orderId) async {
    _requireUid();
    final row = await client.from('orders').select('*').eq('id', orderId).maybeSingle();
    if (row == null) return null;
    final list = await _hydrateOrders([row]);
    return list.firstOrNull;
  }

  @override
  Future<void> ackOrder(int orderId) async {
    _requireUid();
    await client.rpc('ack_order_atomic', params: {'p_order_id': orderId});
  }

  @override
  Future<AcceptOrderResult> acceptOrder(int orderId) async {
    _requireUid();
    try {
      await client.rpc('accept_order_atomic', params: {'p_order_id': orderId});
      return const AcceptOrderResult(ok: true);
    } catch (err) {
      final raw = err.toString();
      final idx = raw.indexOf('ingredient_shortage:');
      if (idx >= 0) {
        final seg = raw.substring(idx).split('\n').first.split(':');
        final stock = double.tryParse(seg.length > 2 ? seg[2] : '0') ?? 0;
        final needed = double.tryParse(seg.length > 3 ? seg[3] : '0') ?? 0;
        return AcceptOrderResult(
          ok: false,
          problems: [
            DishShortageDetail(
              ingredientId: 0,
              ingredientName: seg.length > 1 ? seg[1] : '某种食材',
              unit: '',
              needed: needed,
              stock: stock,
              short: round1(needed - stock),
            ),
          ],
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> finishOrder(int orderId) async {
    _requireUid();
    await client.rpc('finish_order_atomic', params: {'p_order_id': orderId});
  }

  @override
  Future<void> rejectOrder(int orderId, {String reason = ''}) async {
    _requireUid();
    await client.rpc('reject_order_atomic', params: {
      'p_order_id': orderId,
      'p_reason': reason.trim().isEmpty ? null : reason.trim(),
    });
  }

  @override
  Future<void> cancelOrder(int orderId) async {
    _requireUid();
    await client.rpc('cancel_order_atomic', params: {'p_order_id': orderId});
  }

  @override
  Future<void> reportShortage({
    required int kitchenId,
    required String dinerName,
    required List<DishShortageDetail> problems,
  }) async {
    if (problems.isEmpty) return;
    _requireUid();
    await client.rpc('report_shortage_atomic', params: {
      'p_kitchen_id': kitchenId,
      'p_diner_name': dinerName.trim().isEmpty ? null : dinerName.trim(),
      'p_items': problems
          .map((p) => {
                'dish_name': p.dishes.isNotEmpty ? p.dishes : '菜品',
                'ingredient_name': p.ingredientName,
                'needed': p.needed,
                'stock': p.stock,
              })
          .toList(),
    });
  }

  @override
  Future<List<ShortageAlert>> fetchShortageAlerts({int? kitchenId}) async {
    _requireUid();
    var query = client.from('shortage_alerts').select('*').eq('is_read', false);
    if (kitchenId != null) query = query.eq('kitchen_id', kitchenId);
    final rows = await query.order('created_at', ascending: false).limit(50);
    return (rows as List)
        .map((e) => ShortageAlert.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> markShortageAlertsRead(List<int> ids) async {
    if (ids.isEmpty) return;
    _requireUid();
    await client.from('shortage_alerts').update({'is_read': true}).inFilter('id', ids);
  }

  @override
  Future<Map<int, KitchenBadge>> fetchKitchenBadges(List<int> kitchenIds) async {
    if (kitchenIds.isEmpty) return {};
    _requireUid();
    final orders = await client
        .from('orders')
        .select('kitchen_id')
        .inFilter('kitchen_id', kitchenIds)
        .eq('status', 'pending');
    final alerts = await client
        .from('shortage_alerts')
        .select('kitchen_id')
        .inFilter('kitchen_id', kitchenIds)
        .eq('is_read', false);

    final pendingCounts = <int, int>{};
    for (final raw in (orders as List)) {
      final kId = ((raw as Map)['kitchen_id'] as num).toInt();
      pendingCounts[kId] = (pendingCounts[kId] ?? 0) + 1;
    }
    final alertCounts = <int, int>{};
    for (final raw in (alerts as List)) {
      final kId = ((raw as Map)['kitchen_id'] as num).toInt();
      alertCounts[kId] = (alertCounts[kId] ?? 0) + 1;
    }
    return {
      for (final id in kitchenIds)
        id: KitchenBadge(
          pending: pendingCounts[id] ?? 0,
          alerts: alertCounts[id] ?? 0,
        ),
    };
  }

  @override
  Future<List<AppNotification>> fetchUnreadNotifications() async {
    final uid = _requireUid();
    final rows = await client
        .from('notifications')
        .select('*')
        .eq('user_id', uid)
        .eq('is_read', false)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> markNotificationsRead({List<int>? ids}) async {
    _requireUid();
    await client.rpc('mark_notifications_read', params: {
      'p_ids': ids,
      'p_kitchen_id': null,
    });
  }

  @override
  Future<KitchenOrder?> simulateFriendOrder() async => null;
}
