import 'dart:math';
import 'dart:typed_data';
import '../models/models.dart';
import '../utils/availability.dart';
import '../utils/meal_time.dart';
import 'kitchen_backend.dart';

class LocalDemoKitchenBackend implements KitchenBackend {
  static const String _meId = 'demo-user-me';
  static const String _friendMingId = 'demo-user-ming';
  static const String _friendYuId = 'demo-user-yu';

  AppUser _user = const AppUser(
    id: _meId,
    email: 'demo@tablekin.app',
    displayName: '我',
  );

  int _seq = 1000;
  int _nextId() => ++_seq;

  final List<Kitchen> _kitchens = [];
  final Map<int, KitchenInvite> _invites = {};
  final List<KitchenMember> _members = [];
  final List<Category> _categories = [];
  final List<Dish> _dishes = [];
  final List<Ingredient> _ingredients = [];
  final List<DishIngredient> _recipes = [];
  final List<StockLog> _stockLogs = [];
  final List<KitchenOrder> _orders = [];
  final List<ShortageAlert> _shortages = [];
  final List<AppNotification> _notifications = [];
  final Map<String, Uint8List> _uploadedImages = {};
  void Function()? _onChanged;

  LocalDemoKitchenBackend() {
    _seed();
  }

  void _notify() => _onChanged?.call();

  void _seed() {
    final now = DateTime.now();

    // 1. My own kitchen
    _kitchens.addAll([
      Kitchen(
        id: 1,
        ownerId: _meId,
        name: '我的私房小厨',
        description: '拿手家常菜，朋友来家里吃饭提前点单！',
        isPublic: true,
        createdAt: now.subtract(const Duration(days: 14)),
      ),
      Kitchen(
        id: 2,
        ownerId: _friendMingId,
        name: '阿明的小灶',
        description: '川湘风味 + 深夜下酒菜，提前半小时点单',
        isPublic: true,
        createdAt: now.subtract(const Duration(days: 9)),
      ),
      Kitchen(
        id: 3,
        ownerId: _friendYuId,
        name: '小雨家周末饭局',
        description: '清淡暖胃、烘焙甜品与煲汤，周末开火',
        isPublic: true,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);

    _invites[1] = KitchenInvite(
      kitchenId: 1,
      inviteCode: 'HOME8888',
      createdAt: now.subtract(const Duration(days: 14)),
    );
    _invites[2] = KitchenInvite(
      kitchenId: 2,
      inviteCode: 'MING2026',
      createdAt: now.subtract(const Duration(days: 9)),
    );
    _invites[3] = KitchenInvite(
      kitchenId: 3,
      inviteCode: 'RAIN6666',
      createdAt: now.subtract(const Duration(days: 5)),
    );

    _members.addAll([
      KitchenMember(
        id: 1,
        kitchenId: 1,
        userId: _meId,
        role: 'owner',
        nickname: '大厨本人',
        createdAt: now.subtract(const Duration(days: 14)),
      ),
      KitchenMember(
        id: 2,
        kitchenId: 1,
        userId: _friendYuId,
        role: 'member',
        nickname: '小雨',
        createdAt: now.subtract(const Duration(days: 7)),
      ),
      KitchenMember(
        id: 3,
        kitchenId: 2,
        userId: _friendMingId,
        role: 'owner',
        nickname: '阿明',
        createdAt: now.subtract(const Duration(days: 9)),
      ),
      KitchenMember(
        id: 4,
        kitchenId: 3,
        userId: _friendYuId,
        role: 'owner',
        nickname: '小雨',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);

    _categories.addAll([
      const Category(id: 10, kitchenId: 1, name: '招牌硬菜', sortOrder: 1),
      const Category(id: 11, kitchenId: 1, name: '快手小炒', sortOrder: 2),
      const Category(id: 12, kitchenId: 1, name: '暖胃靓汤', sortOrder: 3),
      const Category(id: 20, kitchenId: 2, name: '麻辣下饭', sortOrder: 1),
      const Category(id: 21, kitchenId: 2, name: '凉拌下酒', sortOrder: 2),
      const Category(id: 30, kitchenId: 3, name: '慢炖暖汤', sortOrder: 1),
      const Category(id: 31, kitchenId: 3, name: '手作主食', sortOrder: 2),
    ]);

    _ingredients.addAll([
      const Ingredient(id: 100, kitchenId: 1, name: '猪肋排', unit: '克', stock: 800, alertThreshold: 400, sortOrder: 1),
      const Ingredient(id: 101, kitchenId: 1, name: '番茄', unit: '个', stock: 6, alertThreshold: 2, sortOrder: 2),
      const Ingredient(id: 102, kitchenId: 1, name: '鸡蛋', unit: '个', stock: 12, alertThreshold: 4, sortOrder: 3),
      const Ingredient(id: 103, kitchenId: 1, name: '嫩豆腐', unit: '盒', stock: 1, alertThreshold: 2, sortOrder: 4),
      const Ingredient(id: 104, kitchenId: 1, name: '鲜虾', unit: '克', stock: 0, alertThreshold: 200, sortOrder: 5),
      const Ingredient(id: 200, kitchenId: 2, name: '牛里脊', unit: '克', stock: 600, alertThreshold: 250, sortOrder: 1),
      const Ingredient(id: 201, kitchenId: 2, name: '鸡腿肉', unit: '克', stock: 900, alertThreshold: 300, sortOrder: 2),
    ]);

    _dishes.addAll([
      const Dish(
        id: 101,
        kitchenId: 1,
        categoryId: 10,
        name: '秘制红烧排骨',
        description: '色泽红亮、软烂脱骨，配米饭能吃两碗',
        recipe: '1. 肋排冷水下锅焯水，加姜片料酒去腥。\n2. 冰糖小火炒糖色，下排骨翻炒上色。\n3. 加生抽、老抽、八角桂皮与热水没过排骨，小火焖 45 分钟大火收汁。',
        tags: ['硬菜', '下饭', '不辣'],
        sortOrder: 1,
      ),
      const Dish(
        id: 102,
        kitchenId: 1,
        categoryId: 11,
        name: '番茄炒蛋',
        description: '酸甜多汁，经典国民家常菜',
        recipe: '1. 鸡蛋加少许盐打散，滑炒至蓬松盛出。\n2. 番茄去皮切块炒出沙，加半勺白糖提鲜。\n3. 倒回鸡蛋翻匀撒葱花出锅。',
        tags: ['快手', '不辣', '家常'],
        sortOrder: 2,
      ),
      const Dish(
        id: 103,
        kitchenId: 1,
        categoryId: 11,
        name: '蒜蓉粉丝蒸虾',
        description: '蒜香浓郁，虾肉 Q 弹（目前缺鲜虾，可点击提醒补货）',
        recipe: '1. 鲜虾开背去虾线，粉丝温水泡软铺盘底。\n2. 铺上炒香的金银蒜蓉酱，大火蒸 6 分钟。\n3. 淋蒸鱼豉油，泼热油激香。',
        tags: ['海鲜', '宴客', '不辣'],
        sortOrder: 3,
      ),
      const Dish(
        id: 104,
        kitchenId: 1,
        categoryId: 12,
        name: '虾皮紫菜豆腐汤',
        description: '清淡解腻，5 分钟搞定',
        recipe: '1. 嫩豆腐切小块，水开下豆腐与虾皮煮 3 分钟。\n2. 放入紫菜、少许盐和白胡椒粉，淋几滴香油。',
        tags: ['清淡', '汤羹', '快手'],
        sortOrder: 4,
      ),
      const Dish(
        id: 201,
        kitchenId: 2,
        categoryId: 20,
        name: '水煮牛肉',
        description: '麻辣鲜嫩，花椒香气扑鼻',
        recipe: '牛里脊逆纹切片上浆，豆瓣酱炒香煮底菜，滑入牛肉片后泼热油激香蒜末干辣椒。',
        tags: ['川菜', '微辣', '下饭'],
        sortOrder: 1,
      ),
      const Dish(
        id: 202,
        kitchenId: 2,
        categoryId: 20,
        name: '歌乐山辣子鸡',
        description: '外酥里嫩，追剧喝酒绝配',
        recipe: '鸡腿肉切丁腌制复炸至酥脆，干辣椒花椒小火煸香后下鸡丁翻炒撒白芝麻。',
        tags: ['川菜', '重辣', '下酒'],
        sortOrder: 2,
      ),
      const Dish(
        id: 203,
        kitchenId: 2,
        categoryId: 21,
        name: '拍黄瓜拌木耳',
        description: '酸辣爽口，解腻必备',
        recipe: '黄瓜拍裂切段，焯水木耳沥干，加蒜末、陈醋、生抽、辣椒油拌匀。',
        tags: ['凉菜', '快手', '爽口'],
        sortOrder: 3,
      ),
      const Dish(
        id: 301,
        kitchenId: 3,
        categoryId: 30,
        name: '莲藕排骨老火汤',
        description: '粉糯香甜，文火慢炖两小时',
        recipe: '洪湖粉藕滚刀切块，与焯水排骨、姜片慢炖 2 小时，出锅前加盐调味。',
        tags: ['汤羹', '清淡', '滋补'],
        sortOrder: 1,
      ),
      const Dish(
        id: 302,
        kitchenId: 3,
        categoryId: 31,
        name: '葱油拌面',
        description: '小葱慢熬焦香，拌面一口满足',
        recipe: '小葱切段小火熬至焦黄，加生抽老抽白糖调汁，浇在煮好的手擀面上。',
        tags: ['主食', '快手', '不辣'],
        sortOrder: 2,
      ),
    ]);

    _recipes.addAll([
      const DishIngredient(id: 1, kitchenId: 1, dishId: 101, ingredientId: 100, amount: 350),
      const DishIngredient(id: 2, kitchenId: 1, dishId: 102, ingredientId: 101, amount: 2),
      const DishIngredient(id: 3, kitchenId: 1, dishId: 102, ingredientId: 102, amount: 3),
      const DishIngredient(id: 4, kitchenId: 1, dishId: 103, ingredientId: 104, amount: 250),
      const DishIngredient(id: 5, kitchenId: 1, dishId: 104, ingredientId: 103, amount: 1),
      const DishIngredient(id: 6, kitchenId: 2, dishId: 201, ingredientId: 200, amount: 250),
      const DishIngredient(id: 7, kitchenId: 2, dishId: 202, ingredientId: 201, amount: 300),
    ]);

    _stockLogs.addAll([
      StockLog(
        id: 1,
        ingredientId: 100,
        mode: 'delta',
        change: 800,
        balance: 800,
        reason: '周末逛菜市场采购',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      StockLog(
        id: 2,
        ingredientId: 101,
        mode: 'delta',
        change: 6,
        balance: 6,
        reason: '补货入库',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
    ]);

    final today = todayDateString(now);

    // Sample received order for my kitchen (from friend 阿明)
    _orders.add(
      KitchenOrder(
        id: 501,
        kitchenId: 1,
        ownerId: _meId,
        dinerId: _friendMingId,
        dinerName: '阿明',
        status: 'pending',
        note: '排骨少放点糖，米饭来两碗！',
        orderDate: today,
        mealTimeType: 'point',
        mealTimeStart: '18:30',
        createdAt: now.subtract(const Duration(minutes: 12)),
        kitchenName: '我的私房小厨',
        items: const [
          OrderItem(id: 1, orderId: 501, dishId: 101, dishName: '秘制红烧排骨', quantity: 1),
          OrderItem(id: 2, orderId: 501, dishId: 102, dishName: '番茄炒蛋', quantity: 1),
        ],
      ),
    );

    // Sample order I placed at 阿明的小灶
    _orders.add(
      KitchenOrder(
        id: 502,
        kitchenId: 2,
        ownerId: _friendMingId,
        dinerId: _meId,
        dinerName: '我',
        status: 'accepted',
        note: '微辣就好，谢谢明哥',
        orderDate: today,
        mealTimeType: 'range',
        mealTimeStart: '19:00',
        mealTimeEnd: '19:30',
        ackedAt: now.subtract(const Duration(minutes: 20)),
        decidedAt: now.subtract(const Duration(minutes: 15)),
        createdAt: now.subtract(const Duration(minutes: 25)),
        kitchenName: '阿明的小灶',
        items: const [
          OrderItem(id: 3, orderId: 502, dishId: 201, dishName: '水煮牛肉', quantity: 1),
          OrderItem(id: 4, orderId: 502, dishId: 203, dishName: '拍黄瓜拌木耳', quantity: 1),
        ],
      ),
    );

    _notifications.add(
      AppNotification(
        id: 701,
        kitchenId: 1,
        orderId: 501,
        title: '阿明 刚点了菜',
        body: '秘制红烧排骨、番茄炒蛋 · 想吃 18:30',
        createdAt: now.subtract(const Duration(minutes: 12)),
      ),
    );
  }

  @override
  String get backendName => '本地体验模式';

  @override
  bool get isCloud => false;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<AppUser?> restoreSession() async => _user;

  @override
  Future<AppUser> signInWithPassword(String email, String password) async {
    _user = AppUser(id: _meId, email: email, displayName: email.split('@').first);
    return _user;
  }

  @override
  Future<AppUser> signUpWithPassword(String email, String password, {String? displayName}) async {
    _user = AppUser(
      id: _meId,
      email: email,
      displayName: (displayName ?? '').trim().isNotEmpty ? displayName!.trim() : email.split('@').first,
    );
    return _user;
  }

  @override
  Future<void> signOut() async {}

  @override
  void subscribeLiveUpdates(void Function() onChanged) {
    _onChanged = onChanged;
  }

  @override
  void unsubscribeLiveUpdates() {
    _onChanged = null;
  }

  @override
  Future<List<Kitchen>> fetchMyKitchens() async {
    final myRows = _members.where((m) => m.userId == _user.id).toList();
    final result = <Kitchen>[];
    for (final m in myRows) {
      final k = _kitchens.where((e) => e.id == m.kitchenId).firstOrNull;
      if (k != null) {
        result.add(
          k.copyWith(
            memberId: m.id,
            role: m.role,
            myNickname: m.nickname,
            isOwner: m.role == 'owner' || k.ownerId == _user.id,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<Kitchen?> fetchKitchen(int kitchenId) async {
    final k = _kitchens.where((e) => e.id == kitchenId).firstOrNull;
    if (k == null) return null;
    final m = _members.where((e) => e.kitchenId == kitchenId && e.userId == _user.id).firstOrNull;
    return k.copyWith(
      memberId: m?.id,
      role: m?.role,
      myNickname: m?.nickname,
      isOwner: m?.role == 'owner' || k.ownerId == _user.id,
    );
  }

  @override
  Future<List<Kitchen>> searchKitchens({String keyword = ''}) async {
    final kw = keyword.trim().toLowerCase();
    final myKitchenIds = _members.where((m) => m.userId == _user.id).map((m) => m.kitchenId).toSet();
    return _kitchens.where((k) {
      final visible = k.isPublic || myKitchenIds.contains(k.id);
      if (!visible) return false;
      if (kw.isEmpty) return k.isPublic;
      return k.name.toLowerCase().contains(kw) || k.description.toLowerCase().contains(kw);
    }).toList();
  }

  @override
  Future<Map<int, int>> countPublicDishes(List<int> kitchenIds) async {
    final result = {for (final id in kitchenIds) id: 0};
    for (final d in _dishes) {
      if (result.containsKey(d.kitchenId) && d.isPublic && d.isAvailable) {
        result[d.kitchenId] = (result[d.kitchenId] ?? 0) + 1;
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
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('kitchen_name_required');
    final id = _nextId();
    final now = DateTime.now();
    final kitchen = Kitchen(
      id: id,
      ownerId: _user.id,
      name: trimmed,
      description: description.trim(),
      isPublic: isPublic,
      createdAt: now,
      role: 'owner',
      myNickname: nickname.trim().isEmpty ? '主厨' : nickname.trim(),
      isOwner: true,
    );
    _kitchens.insert(0, kitchen);
    final memberId = _nextId();
    _members.add(
      KitchenMember(
        id: memberId,
        kitchenId: id,
        userId: _user.id,
        role: 'owner',
        nickname: kitchen.myNickname ?? '主厨',
        createdAt: now,
      ),
    );
    _invites[id] = KitchenInvite(
      kitchenId: id,
      inviteCode: _randomCode(),
      createdAt: now,
    );
    _notify();
    return kitchen.copyWith(memberId: memberId);
  }

  @override
  Future<Kitchen> updateKitchen(
    int kitchenId, {
    required String name,
    required String description,
    required bool isPublic,
  }) async {
    final idx = _kitchens.indexWhere((k) => k.id == kitchenId);
    if (idx < 0) throw Exception('kitchen_not_found');
    final updated = _kitchens[idx].copyWith(
      name: name.trim(),
      description: description.trim(),
      isPublic: isPublic,
    );
    _kitchens[idx] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> deleteKitchen(int kitchenId) async {
    _kitchens.removeWhere((k) => k.id == kitchenId);
    _members.removeWhere((m) => m.kitchenId == kitchenId);
    _categories.removeWhere((c) => c.kitchenId == kitchenId);
    _dishes.removeWhere((d) => d.kitchenId == kitchenId);
    _ingredients.removeWhere((i) => i.kitchenId == kitchenId);
    _recipes.removeWhere((r) => r.kitchenId == kitchenId);
    _invites.remove(kitchenId);
    _notify();
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  Future<KitchenInvite> getKitchenInvite(int kitchenId) async {
    return _invites.putIfAbsent(
      kitchenId,
      () => KitchenInvite(
        kitchenId: kitchenId,
        inviteCode: _randomCode(),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<KitchenInvite> resetKitchenInvite(int kitchenId) async {
    final now = DateTime.now();
    final inv = KitchenInvite(
      kitchenId: kitchenId,
      inviteCode: _randomCode(),
      createdAt: _invites[kitchenId]?.createdAt ?? now,
      rotatedAt: now,
    );
    _invites[kitchenId] = inv;
    return inv;
  }

  @override
  Future<Kitchen> joinKitchenByCode(String code, {String nickname = ''}) async {
    final normalized = code.trim().toUpperCase();
    final match = _invites.values.where((e) => e.inviteCode.toUpperCase() == normalized).firstOrNull;
    if (match == null) throw Exception('invite_code_not_found');
    final kitchen = _kitchens.where((k) => k.id == match.kitchenId).firstOrNull;
    if (kitchen == null) throw Exception('kitchen_not_found');
    final existing = _members.indexWhere((m) => m.kitchenId == kitchen.id && m.userId == _user.id);
    final nick = nickname.trim().isEmpty ? '家人' : nickname.trim();
    if (existing >= 0) {
      final old = _members[existing];
      _members[existing] = KitchenMember(
        id: old.id,
        kitchenId: old.kitchenId,
        userId: old.userId,
        role: old.role,
        nickname: nick,
        createdAt: old.createdAt,
      );
    } else {
      _members.add(
        KitchenMember(
          id: _nextId(),
          kitchenId: kitchen.id,
          userId: _user.id,
          role: 'member',
          nickname: nick,
          createdAt: DateTime.now(),
        ),
      );
    }
    _notify();
    return kitchen;
  }

  @override
  Future<List<KitchenMember>> fetchMembers(int kitchenId) async {
    return _members.where((m) => m.kitchenId == kitchenId).toList();
  }

  @override
  Future<KitchenMember> updateMemberNickname(int memberId, String nickname) async {
    final idx = _members.indexWhere((m) => m.id == memberId);
    if (idx < 0) throw Exception('没有找到该成员');
    final old = _members[idx];
    final updated = KitchenMember(
      id: old.id,
      kitchenId: old.kitchenId,
      userId: old.userId,
      role: old.role,
      nickname: nickname.trim(),
      createdAt: old.createdAt,
    );
    _members[idx] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> removeMember(int memberId) async {
    _members.removeWhere((m) => m.id == memberId);
    _notify();
  }

  @override
  Future<List<Category>> fetchCategories(int kitchenId, {bool publicOnly = false}) async {
    final list = _categories.where((c) => c.kitchenId == kitchenId && (!publicOnly || c.isPublic)).toList();
    list.sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
    return list;
  }

  @override
  Future<Category> createCategory(int kitchenId, String name, {bool isPublic = true}) async {
    final cat = Category(
      id: _nextId(),
      kitchenId: kitchenId,
      name: name.trim(),
      isPublic: isPublic,
      sortOrder: _categories.where((c) => c.kitchenId == kitchenId).length + 1,
    );
    _categories.add(cat);
    _notify();
    return cat;
  }

  @override
  Future<Category> updateCategory(int categoryId, {String? name, bool? isPublic}) async {
    final idx = _categories.indexWhere((c) => c.id == categoryId);
    if (idx < 0) throw Exception('分类不存在');
    final updated = _categories[idx].copyWith(name: name, isPublic: isPublic);
    _categories[idx] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> deleteCategory(int categoryId) async {
    _categories.removeWhere((c) => c.id == categoryId);
    for (var i = 0; i < _dishes.length; i++) {
      if (_dishes[i].categoryId == categoryId) {
        _dishes[i] = _dishes[i].copyWith(clearCategory: true);
      }
    }
    _notify();
  }

  @override
  Future<List<Dish>> fetchDishes(
    int kitchenId, {
    bool publicOnly = false,
    List<String> tags = const [],
    String tagMode = 'all',
  }) async {
    final list = _dishes.where((d) {
      if (d.kitchenId != kitchenId) return false;
      if (publicOnly && !d.isPublic) return false;
      if (tags.isNotEmpty) {
        if (tagMode == 'any') {
          if (!tags.any((t) => d.tags.contains(t))) return false;
        } else {
          if (!tags.every((t) => d.tags.contains(t))) return false;
        }
      }
      return true;
    }).toList();
    list.sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
    return list;
  }

  @override
  Future<Dish?> fetchDish(int dishId) async {
    return _dishes.where((d) => d.id == dishId).firstOrNull;
  }

  @override
  Future<List<Dish>> searchDishes({
    String keyword = '',
    int? kitchenId,
    List<String> tags = const [],
    String tagMode = 'all',
  }) async {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty && tags.isEmpty) return [];
    return _dishes.where((d) {
      if (kitchenId != null && d.kitchenId != kitchenId) return false;
      if (kw.isNotEmpty &&
          !d.name.toLowerCase().contains(kw) &&
          !d.description.toLowerCase().contains(kw)) {
        return false;
      }
      if (tags.isNotEmpty) {
        if (tagMode == 'any') {
          if (!tags.any((t) => d.tags.contains(t))) return false;
        } else {
          if (!tags.every((t) => d.tags.contains(t))) return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Future<List<TagCount>> listKitchenTags({int kitchenId = 0}) async {
    final counts = <String, int>{};
    for (final d in _dishes) {
      if (kitchenId != 0 && d.kitchenId != kitchenId) continue;
      for (final tag in d.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final list = counts.entries.map((e) => TagCount(name: e.key, count: e.value)).toList();
    list.sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.compareTo(b.name));
    return list;
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
    final dish = Dish(
      id: _nextId(),
      kitchenId: kitchenId,
      categoryId: categoryId,
      name: name.trim(),
      description: description.trim(),
      recipe: recipe.trim(),
      imagePath: imagePaths.isNotEmpty ? imagePaths.first : null,
      imagePaths: List<String>.from(imagePaths),
      tags: List<String>.from(tags),
      isPublic: isPublic,
      isRecipePublic: isRecipePublic,
      isAvailable: isAvailable,
      sortOrder: _dishes.where((d) => d.kitchenId == kitchenId).length + 1,
    );
    _dishes.add(dish);
    _notify();
    return dish;
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
    final idx = _dishes.indexWhere((d) => d.id == dishId);
    if (idx < 0) throw Exception('菜品不存在');
    final updated = _dishes[idx].copyWith(
      categoryId: categoryId,
      clearCategory: clearCategory,
      name: name?.trim(),
      description: description?.trim(),
      recipe: recipe?.trim(),
      imagePath: imagePaths != null ? (imagePaths.isNotEmpty ? imagePaths.first : null) : null,
      imagePaths: imagePaths,
      tags: tags,
      isPublic: isPublic,
      isRecipePublic: isRecipePublic,
      isAvailable: isAvailable,
    );
    _dishes[idx] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> deleteDish(int dishId) async {
    _dishes.removeWhere((d) => d.id == dishId);
    _recipes.removeWhere((r) => r.dishId == dishId);
    _notify();
  }

  @override
  Future<void> reorderKitchenItems(int kitchenId, String kind, List<int> ids, List<int> expectedIds) async {
    if (kind == 'categories') {
      for (var i = 0; i < ids.length; i++) {
        final idx = _categories.indexWhere((c) => c.id == ids[i] && c.kitchenId == kitchenId);
        if (idx >= 0) _categories[idx] = _categories[idx].copyWith(sortOrder: i + 1);
      }
    } else {
      for (var i = 0; i < ids.length; i++) {
        final idx = _dishes.indexWhere((d) => d.id == ids[i] && d.kitchenId == kitchenId);
        if (idx >= 0) _dishes[idx] = _dishes[idx].copyWith(sortOrder: i + 1);
      }
    }
    _notify();
  }

  @override
  Future<String> uploadDishImage(Uint8List bytes, String filename) async {
    final path = 'demo-image://${_nextId()}-$filename';
    _uploadedImages[path] = bytes;
    return path;
  }

  @override
  Future<Map<String, String>> signImageUrls(List<String> paths) async {
    return {for (final p in paths) if (p.startsWith('http')) p: p};
  }

  @override
  Future<List<Ingredient>> fetchIngredients(int kitchenId) async {
    final list = _ingredients.where((i) => i.kitchenId == kitchenId).toList();
    list.sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
    return list;
  }

  @override
  Future<Ingredient> createIngredient({
    required int kitchenId,
    required String name,
    required String unit,
    required double initialStock,
    double alertThreshold = 0,
  }) async {
    final ing = Ingredient(
      id: _nextId(),
      kitchenId: kitchenId,
      name: name.trim(),
      unit: unit.trim().isEmpty ? '份' : unit.trim(),
      stock: initialStock,
      alertThreshold: alertThreshold,
      sortOrder: _ingredients.where((i) => i.kitchenId == kitchenId).length + 1,
    );
    _ingredients.add(ing);
    if (initialStock > 0) {
      _stockLogs.insert(
        0,
        StockLog(
          id: _nextId(),
          ingredientId: ing.id,
          mode: 'recount',
          change: initialStock,
          balance: initialStock,
          reason: '新建食材初始库存',
          createdAt: DateTime.now(),
        ),
      );
    }
    _notify();
    return ing;
  }

  @override
  Future<Ingredient> updateIngredient(
    int ingredientId, {
    required String name,
    required String unit,
    required double alertThreshold,
  }) async {
    final idx = _ingredients.indexWhere((i) => i.id == ingredientId);
    if (idx < 0) throw Exception('ingredient_not_found');
    final updated = _ingredients[idx].copyWith(
      name: name.trim(),
      unit: unit.trim(),
      alertThreshold: alertThreshold,
    );
    _ingredients[idx] = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> deleteIngredient(int ingredientId) async {
    _ingredients.removeWhere((i) => i.id == ingredientId);
    _recipes.removeWhere((r) => r.ingredientId == ingredientId);
    _notify();
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
    final idx = _ingredients.indexWhere((i) => i.id == ingredientId);
    if (idx < 0) throw Exception('ingredient_not_found');
    final ing = _ingredients[idx];
    double after;
    double change;
    if (mode == 'delta') {
      if (value <= 0) throw Exception('value_invalid');
      change = value;
      after = round1(ing.stock + value);
    } else {
      if (value < 0) throw Exception('stock_negative');
      if (expectedStock != null && round1(expectedStock) != round1(ing.stock)) {
        throw Exception('stock_changed:${ing.stock}:$expectedStock');
      }
      after = round1(value);
      change = round1(after - ing.stock);
      if (change == 0) throw Exception('no_change');
    }
    _ingredients[idx] = ing.copyWith(stock: after);
    _stockLogs.insert(
      0,
      StockLog(
        id: _nextId(),
        ingredientId: ing.id,
        mode: mode,
        change: change,
        balance: after,
        reason: reason.trim().isEmpty ? (mode == 'delta' ? '手动入库' : '库存盘点') : reason.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _notify();
    return after;
  }

  @override
  Future<List<StockLog>> fetchStockLogs(int ingredientId) async {
    return _stockLogs.where((l) => l.ingredientId == ingredientId).toList();
  }

  @override
  Future<List<DishIngredient>> fetchRecipes({int? kitchenId, int? dishId}) async {
    return _recipes.where((r) {
      if (dishId != null) return r.dishId == dishId;
      if (kitchenId != null) return r.kitchenId == kitchenId;
      return true;
    }).toList();
  }

  @override
  Future<void> replaceDishIngredients(int dishId, int kitchenId, List<DishIngredient> rows) async {
    _recipes.removeWhere((r) => r.dishId == dishId);
    for (final r in rows) {
      if (r.amount > 0) {
        _recipes.add(
          DishIngredient(
            id: _nextId(),
            kitchenId: kitchenId,
            dishId: dishId,
            ingredientId: r.ingredientId,
            amount: r.amount,
          ),
        );
      }
    }
    _notify();
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
    if (items.isEmpty) throw Exception('order_items_required');
    final kitchen = _kitchens.where((k) => k.id == kitchenId).firstOrNull;
    if (kitchen == null) throw Exception('kitchen_not_found');
    final err = validateMealSchedule(
      orderDate: orderDate,
      mealTimeType: mealTimeType,
      start: mealTimeStart,
      end: mealTimeEnd,
    );
    if (err != null) throw Exception(err);

    final orderId = _nextId();
    final orderItems = items
        .map(
          (e) => OrderItem(
            id: _nextId(),
            orderId: orderId,
            dishId: e.dish.id,
            dishName: e.dish.name,
            quantity: e.count,
          ),
        )
        .toList();

    final order = KitchenOrder(
      id: orderId,
      kitchenId: kitchenId,
      ownerId: kitchen.ownerId,
      dinerId: _user.id,
      dinerName: dinerName.trim().isEmpty ? '我' : dinerName.trim(),
      status: 'pending',
      note: note.trim(),
      orderDate: orderDate,
      mealTimeType: mealTimeType,
      mealTimeStart: mealTimeStart,
      mealTimeEnd: mealTimeEnd,
      createdAt: DateTime.now(),
      items: orderItems,
      kitchenName: kitchen.name,
    );
    _orders.insert(0, order);
    _notify();
    return order;
  }

  @override
  Future<List<KitchenOrder>> fetchMyOrders() async {
    return _orders.where((o) => o.dinerId == _user.id).toList();
  }

  @override
  Future<List<KitchenOrder>> fetchReceivedOrders(List<int> kitchenIds) async {
    final set = kitchenIds.toSet();
    return _orders.where((o) => set.contains(o.kitchenId)).toList();
  }

  @override
  Future<KitchenOrder?> fetchOrder(int orderId) async {
    return _orders.where((o) => o.id == orderId).firstOrNull;
  }

  @override
  Future<void> ackOrder(int orderId) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) throw Exception('order_not_found');
    if (_orders[idx].status != 'pending') throw Exception('order_not_pending');
    _orders[idx] = _orders[idx].copyWith(ackedAt: _orders[idx].ackedAt ?? DateTime.now());
    _notify();
  }

  @override
  Future<AcceptOrderResult> acceptOrder(int orderId) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) throw Exception('order_not_found');
    final order = _orders[idx];
    if (order.status != 'pending') throw Exception('order_not_pending');

    final wanted = <int, int>{};
    for (final item in order.items) {
      if (item.dishId != null) {
        wanted[item.dishId!] = (wanted[item.dishId!] ?? 0) + item.quantity;
      }
    }
    final kitchenDishes = _dishes.where((d) => d.kitchenId == order.kitchenId).toList();
    final kitchenIngredients = _ingredients.where((i) => i.kitchenId == order.kitchenId).toList();
    final kitchenRecipes = _recipes.where((r) => r.kitchenId == order.kitchenId).toList();

    final check = checkOrderAvailability(kitchenDishes, kitchenIngredients, kitchenRecipes, wanted);
    if (!check.ok) {
      return AcceptOrderResult(ok: false, problems: check.problems);
    }

    // Deduct stock atomically
    final deductByIng = <int, double>{};
    for (final r in kitchenRecipes) {
      final qty = wanted[r.dishId] ?? 0;
      if (qty > 0) {
        deductByIng[r.ingredientId] = (deductByIng[r.ingredientId] ?? 0) + r.amount * qty;
      }
    }
    deductByIng.forEach((ingId, amount) {
      final iIdx = _ingredients.indexWhere((i) => i.id == ingId);
      if (iIdx >= 0) {
        final ing = _ingredients[iIdx];
        final after = round1(ing.stock - amount);
        _ingredients[iIdx] = ing.copyWith(stock: after);
        _stockLogs.insert(
          0,
          StockLog(
            id: _nextId(),
            ingredientId: ingId,
            mode: 'order',
            change: -round1(amount),
            balance: after,
            reason: '接单扣减（#${order.id}）',
            createdAt: DateTime.now(),
          ),
        );
      }
    });

    final now = DateTime.now();
    _orders[idx] = order.copyWith(
      status: 'accepted',
      ackedAt: order.ackedAt ?? now,
      decidedAt: now,
    );
    _notify();
    return const AcceptOrderResult(ok: true);
  }

  @override
  Future<void> finishOrder(int orderId) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) throw Exception('order_not_found');
    if (_orders[idx].status == 'done') return;
    if (_orders[idx].status != 'accepted') throw Exception('order_not_accepted');
    _orders[idx] = _orders[idx].copyWith(status: 'done', doneAt: DateTime.now());
    _notify();
  }

  @override
  Future<void> rejectOrder(int orderId, {String reason = ''}) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) throw Exception('order_not_found');
    if (_orders[idx].status != 'pending') throw Exception('order_not_pending');
    _orders[idx] = _orders[idx].copyWith(
      status: 'rejected',
      rejectReason: reason.trim(),
      decidedAt: DateTime.now(),
    );
    _notify();
  }

  @override
  Future<void> cancelOrder(int orderId) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) throw Exception('order_not_found');
    if (_orders[idx].status == 'accepted') throw Exception('order_already_accepted');
    if (_orders[idx].status != 'pending') throw Exception('order_not_cancelable');
    _orders[idx] = _orders[idx].copyWith(status: 'cancelled', cancelledAt: DateTime.now());
    _notify();
  }

  @override
  Future<void> reportShortage({
    required int kitchenId,
    required String dinerName,
    required List<DishShortageDetail> problems,
  }) async {
    for (final p in problems) {
      _shortages.insert(
        0,
        ShortageAlert(
          id: _nextId(),
          kitchenId: kitchenId,
          dinerName: dinerName.trim().isEmpty ? '朋友' : dinerName.trim(),
          dishName: p.dishes.isNotEmpty ? p.dishes : '菜品',
          ingredientName: p.ingredientName,
          needed: p.needed,
          stock: p.stock,
          createdAt: DateTime.now(),
        ),
      );
    }
    _notify();
  }

  @override
  Future<List<ShortageAlert>> fetchShortageAlerts({int? kitchenId}) async {
    return _shortages.where((s) => !s.isRead && (kitchenId == null || s.kitchenId == kitchenId)).toList();
  }

  @override
  Future<void> markShortageAlertsRead(List<int> ids) async {
    final set = ids.toSet();
    for (var i = 0; i < _shortages.length; i++) {
      if (set.contains(_shortages[i].id)) {
        final s = _shortages[i];
        _shortages[i] = ShortageAlert(
          id: s.id,
          kitchenId: s.kitchenId,
          dinerName: s.dinerName,
          dishName: s.dishName,
          ingredientName: s.ingredientName,
          needed: s.needed,
          stock: s.stock,
          isRead: true,
          createdAt: s.createdAt,
        );
      }
    }
    _notify();
  }

  @override
  Future<Map<int, KitchenBadge>> fetchKitchenBadges(List<int> kitchenIds) async {
    final map = <int, KitchenBadge>{};
    for (final id in kitchenIds) {
      final pending = _orders.where((o) => o.kitchenId == id && o.status == 'pending').length;
      final alerts = _shortages.where((s) => s.kitchenId == id && !s.isRead).length;
      map[id] = KitchenBadge(pending: pending, alerts: alerts);
    }
    return map;
  }

  @override
  Future<List<AppNotification>> fetchUnreadNotifications() async {
    return _notifications.where((n) => !n.isRead).toList();
  }

  @override
  Future<void> markNotificationsRead({List<int>? ids}) async {
    final set = ids?.toSet();
    for (var i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      if (!n.isRead && (set == null || set.contains(n.id))) {
        _notifications[i] = AppNotification(
          id: n.id,
          kitchenId: n.kitchenId,
          orderId: n.orderId,
          title: n.title,
          body: n.body,
          isRead: true,
          createdAt: n.createdAt,
        );
      }
    }
    _notify();
  }

  @override
  Future<KitchenOrder?> simulateFriendOrder() async {
    final myKitchens = await fetchMyKitchens();
    if (myKitchens.isEmpty) return null;
    final target = myKitchens.first;
    final dishes = await fetchDishes(target.id);
    final available = dishes.where((d) => d.isAvailable).toList();
    if (available.isEmpty) return null;

    final friends = ['小雨', '阿明', '老陈', '林琳'];
    final notes = ['少盐少油，谢谢大厨！', '多加一份米饭～', '微辣，不吃香菜', '辛苦啦，带了饮料过来'];
    final rand = Random();
    final picked = available.take(min(2, available.length)).toList();
    final friend = friends[rand.nextInt(friends.length)];
    final orderId = _nextId();
    final order = KitchenOrder(
      id: orderId,
      kitchenId: target.id,
      ownerId: target.ownerId,
      dinerId: 'friend-${rand.nextInt(999)}',
      dinerName: friend,
      status: 'pending',
      note: notes[rand.nextInt(notes.length)],
      orderDate: todayDateString(),
      mealTimeType: 'point',
      mealTimeStart: '19:00',
      createdAt: DateTime.now(),
      kitchenName: target.name,
      items: picked
          .map(
            (d) => OrderItem(
              id: _nextId(),
              orderId: orderId,
              dishId: d.id,
              dishName: d.name,
              quantity: 1,
            ),
          )
          .toList(),
    );
    _orders.insert(0, order);
    _notifications.insert(
      0,
      AppNotification(
        id: _nextId(),
        kitchenId: target.id,
        orderId: orderId,
        title: '$friend 刚点了菜',
        body: '${order.dishesSummary} · 想吃 19:00',
        createdAt: DateTime.now(),
      ),
    );
    _notify();
    return order;
  }
}
