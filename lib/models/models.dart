class AppUser {
  final String id;
  final String email;
  final String displayName;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
  });
}

class Kitchen {
  final int id;
  final String ownerId;
  final String name;
  final String description;
  final String? coverPath;
  final bool isPublic;
  final DateTime createdAt;

  // Optional membership context when fetched via my kitchens
  final int? memberId;
  final String? role;
  final String? myNickname;
  final bool isOwner;

  const Kitchen({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description = '',
    this.coverPath,
    this.isPublic = true,
    required this.createdAt,
    this.memberId,
    this.role,
    this.myNickname,
    this.isOwner = false,
  });

  String get initial => name.trim().isEmpty ? '厨' : name.trim().substring(0, 1);

  String get roleText => isOwner ? '主厨' : '共有人';

  String get scopeText => isPublic ? '公开厨房' : '私密厨房';

  Kitchen copyWith({
    String? name,
    String? description,
    String? coverPath,
    bool? isPublic,
    int? memberId,
    String? role,
    String? myNickname,
    bool? isOwner,
  }) {
    return Kitchen(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      coverPath: coverPath ?? this.coverPath,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
      memberId: memberId ?? this.memberId,
      role: role ?? this.role,
      myNickname: myNickname ?? this.myNickname,
      isOwner: isOwner ?? this.isOwner,
    );
  }

  factory Kitchen.fromJson(
    Map<String, dynamic> json, {
    int? memberId,
    String? role,
    String? myNickname,
    String? currentUserId,
  }) {
    final ownerId = (json['owner_id'] ?? '').toString();
    return Kitchen(
      id: (json['id'] as num).toInt(),
      ownerId: ownerId,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      coverPath: json['cover_path']?.toString(),
      isPublic: json['is_public'] != false,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      memberId: memberId,
      role: role,
      myNickname: myNickname,
      isOwner: role == 'owner' ||
          (currentUserId != null && ownerId == currentUserId),
    );
  }
}

class KitchenInvite {
  final int kitchenId;
  final String inviteCode;
  final DateTime? createdAt;
  final DateTime? rotatedAt;

  const KitchenInvite({
    required this.kitchenId,
    required this.inviteCode,
    this.createdAt,
    this.rotatedAt,
  });

  factory KitchenInvite.fromJson(Map<String, dynamic> json) {
    return KitchenInvite(
      kitchenId: (json['kitchen_id'] as num).toInt(),
      inviteCode: (json['invite_code'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      rotatedAt: DateTime.tryParse((json['rotated_at'] ?? '').toString()),
    );
  }
}

class KitchenMember {
  final int id;
  final int kitchenId;
  final String userId;
  final String role;
  final String nickname;
  final DateTime createdAt;

  const KitchenMember({
    required this.id,
    required this.kitchenId,
    required this.userId,
    required this.role,
    required this.nickname,
    required this.createdAt,
  });

  bool get isOwner => role == 'owner';
  String get displayName => nickname.trim().isEmpty ? (isOwner ? '主厨' : '家人') : nickname.trim();
  String get initial => displayName.substring(0, 1);

  factory KitchenMember.fromJson(Map<String, dynamic> json) {
    return KitchenMember(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      userId: (json['user_id'] ?? '').toString(),
      role: (json['role'] ?? 'member').toString(),
      nickname: (json['nickname'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class Category {
  final int id;
  final int kitchenId;
  final String name;
  final bool isPublic;
  final int sortOrder;

  const Category({
    required this.id,
    required this.kitchenId,
    required this.name,
    this.isPublic = true,
    this.sortOrder = 0,
  });

  Category copyWith({String? name, bool? isPublic, int? sortOrder}) {
    return Category(
      id: id,
      kitchenId: kitchenId,
      name: name ?? this.name,
      isPublic: isPublic ?? this.isPublic,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      isPublic: json['is_public'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class Dish {
  final int id;
  final int kitchenId;
  final int? categoryId;
  final String name;
  final String description;
  final String recipe;
  final String? imagePath;
  final List<String> imagePaths;
  final List<String> tags;
  final bool isPublic;
  final bool isRecipePublic;
  final bool isAvailable;
  final int sortOrder;

  const Dish({
    required this.id,
    required this.kitchenId,
    this.categoryId,
    required this.name,
    this.description = '',
    this.recipe = '',
    this.imagePath,
    this.imagePaths = const [],
    this.tags = const [],
    this.isPublic = true,
    this.isRecipePublic = true,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  String get initial => name.trim().isEmpty ? '菜' : name.trim().substring(0, 1);

  List<String> get allImages {
    if (imagePaths.isNotEmpty) return imagePaths;
    if (imagePath != null && imagePath!.isNotEmpty) return [imagePath!];
    return const [];
  }

  String? get coverImage => allImages.isNotEmpty ? allImages.first : null;

  Dish copyWith({
    int? categoryId,
    bool clearCategory = false,
    String? name,
    String? description,
    String? recipe,
    String? imagePath,
    List<String>? imagePaths,
    List<String>? tags,
    bool? isPublic,
    bool? isRecipePublic,
    bool? isAvailable,
    int? sortOrder,
  }) {
    return Dish(
      id: id,
      kitchenId: kitchenId,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      name: name ?? this.name,
      description: description ?? this.description,
      recipe: recipe ?? this.recipe,
      imagePath: imagePath ?? this.imagePath,
      imagePaths: imagePaths ?? this.imagePaths,
      tags: tags ?? this.tags,
      isPublic: isPublic ?? this.isPublic,
      isRecipePublic: isRecipePublic ?? this.isRecipePublic,
      isAvailable: isAvailable ?? this.isAvailable,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory Dish.fromJson(Map<String, dynamic> json) {
    final rawPaths = (json['image_paths'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];
    final singlePath = json['image_path']?.toString();
    if (rawPaths.isEmpty && singlePath != null && singlePath.isNotEmpty) {
      rawPaths.add(singlePath);
    }
    final rawTags = (json['tags'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];
    return Dish(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      categoryId: (json['category_id'] as num?)?.toInt(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      recipe: (json['recipe'] ?? '').toString(),
      imagePath: rawPaths.isNotEmpty ? rawPaths.first : null,
      imagePaths: rawPaths,
      tags: rawTags,
      isPublic: json['is_public'] != false,
      isRecipePublic: json['is_recipe_public'] != false,
      isAvailable: json['is_available'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class TagCount {
  final String name;
  final int count;

  const TagCount({required this.name, required this.count});
}

class Ingredient {
  final int id;
  final int kitchenId;
  final String name;
  final String unit;
  final double stock;
  final double alertThreshold;
  final int sortOrder;

  const Ingredient({
    required this.id,
    required this.kitchenId,
    required this.name,
    required this.unit,
    required this.stock,
    this.alertThreshold = 0,
    this.sortOrder = 0,
  });

  bool get isLow => alertThreshold > 0 && stock <= alertThreshold;

  String get stockText => _formatNum(stock);
  String get alertText => _formatNum(alertThreshold);

  Ingredient copyWith({
    String? name,
    String? unit,
    double? stock,
    double? alertThreshold,
    int? sortOrder,
  }) {
    return Ingredient(
      id: id,
      kitchenId: kitchenId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      stock: stock ?? this.stock,
      alertThreshold: alertThreshold ?? this.alertThreshold,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      unit: (json['unit'] ?? '份').toString(),
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      alertThreshold: (json['alert_threshold'] as num?)?.toDouble() ?? 0,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class DishIngredient {
  final int? id;
  final int kitchenId;
  final int dishId;
  final int ingredientId;
  final double amount;

  const DishIngredient({
    this.id,
    required this.kitchenId,
    required this.dishId,
    required this.ingredientId,
    required this.amount,
  });

  factory DishIngredient.fromJson(Map<String, dynamic> json) {
    return DishIngredient(
      id: (json['id'] as num?)?.toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      dishId: (json['dish_id'] as num).toInt(),
      ingredientId: (json['ingredient_id'] as num).toInt(),
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

class StockLog {
  final int id;
  final int ingredientId;
  final String mode;
  final double change;
  final double balance;
  final String reason;
  final DateTime createdAt;

  const StockLog({
    required this.id,
    required this.ingredientId,
    required this.mode,
    required this.change,
    required this.balance,
    required this.reason,
    required this.createdAt,
  });

  bool get isPositive => change >= 0;
  String get changeText => '${change >= 0 ? '+' : ''}${_formatNum(change)}';
  String get balanceText => '余 ${_formatNum(balance)}';

  factory StockLog.fromJson(Map<String, dynamic> json) {
    return StockLog(
      id: (json['id'] as num).toInt(),
      ingredientId: (json['ingredient_id'] as num).toInt(),
      mode: (json['mode'] ?? 'delta').toString(),
      change: (json['change'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      reason: (json['reason'] ?? '库存变动').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class OrderItem {
  final int id;
  final int orderId;
  final int? dishId;
  final String dishName;
  final int quantity;

  const OrderItem({
    required this.id,
    required this.orderId,
    this.dishId,
    required this.dishName,
    required this.quantity,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: (json['id'] as num).toInt(),
      orderId: (json['order_id'] as num).toInt(),
      dishId: (json['dish_id'] as num?)?.toInt(),
      dishName: (json['dish_name'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

enum OrderTone { wait, ack, doing, done, off }

class OrderStatusInfo {
  final String key;
  final String text;
  final OrderTone tone;

  const OrderStatusInfo({
    required this.key,
    required this.text,
    required this.tone,
  });
}

class OrderStep {
  final String key;
  final String label;
  final DateTime? at;
  final bool done;

  const OrderStep({
    required this.key,
    required this.label,
    this.at,
    required this.done,
  });
}

class KitchenOrder {
  final int id;
  final int kitchenId;
  final String ownerId;
  final String dinerId;
  final String dinerName;
  final String status; // pending, accepted, done, rejected, cancelled
  final String note;
  final String rejectReason;
  final String orderDate; // YYYY-MM-DD
  final String mealTimeType; // asap, point, range
  final String? mealTimeStart;
  final String? mealTimeEnd;
  final DateTime? ackedAt;
  final DateTime? decidedAt;
  final DateTime? doneAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  // Hydrated fields
  final List<OrderItem> items;
  final String kitchenName;

  const KitchenOrder({
    required this.id,
    required this.kitchenId,
    required this.ownerId,
    required this.dinerId,
    required this.dinerName,
    required this.status,
    this.note = '',
    this.rejectReason = '',
    required this.orderDate,
    this.mealTimeType = 'asap',
    this.mealTimeStart,
    this.mealTimeEnd,
    this.ackedAt,
    this.decidedAt,
    this.doneAt,
    this.cancelledAt,
    required this.createdAt,
    this.items = const [],
    this.kitchenName = '',
  });

  int get totalPortions =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  String get dishesSummary =>
      items.map((e) => '${e.dishName}×${e.quantity}').join('、');

  bool get isOngoing => status == 'pending' || status == 'accepted';

  OrderStatusInfo get statusInfo {
    if (status == 'pending' && ackedAt != null) {
      return const OrderStatusInfo(
        key: 'acked',
        text: '大厨已收到',
        tone: OrderTone.ack,
      );
    }
    switch (status) {
      case 'pending':
        return const OrderStatusInfo(
          key: 'pending',
          text: '等大厨回复',
          tone: OrderTone.wait,
        );
      case 'accepted':
        return const OrderStatusInfo(
          key: 'accepted',
          text: '大厨正在做',
          tone: OrderTone.doing,
        );
      case 'done':
        return const OrderStatusInfo(
          key: 'done',
          text: '已出餐',
          tone: OrderTone.done,
        );
      case 'rejected':
        return const OrderStatusInfo(
          key: 'rejected',
          text: '这单没做成',
          tone: OrderTone.off,
        );
      case 'cancelled':
        return const OrderStatusInfo(
          key: 'cancelled',
          text: '已撤回',
          tone: OrderTone.off,
        );
      default:
        return OrderStatusInfo(
          key: status,
          text: status,
          tone: OrderTone.wait,
        );
    }
  }

  List<OrderStep> get steps {
    if (status == 'cancelled') {
      return [
        OrderStep(key: 'sent', label: '已发送给大厨', at: createdAt, done: true),
        OrderStep(
          key: 'cancelled',
          label: '点菜人已撤回',
          at: cancelledAt,
          done: true,
        ),
      ];
    }
    if (status == 'rejected') {
      return [
        OrderStep(key: 'sent', label: '已发送给大厨', at: createdAt, done: true),
        if (ackedAt != null)
          OrderStep(key: 'acked', label: '大厨已收到', at: ackedAt, done: true),
        OrderStep(
          key: 'rejected',
          label: '大厨回复做不了',
          at: decidedAt,
          done: true,
        ),
      ];
    }
    final accepted = status == 'accepted' || status == 'done';
    return [
      OrderStep(key: 'sent', label: '已发送给大厨', at: createdAt, done: true),
      OrderStep(
        key: 'acked',
        label: '大厨已收到',
        at: ackedAt,
        done: ackedAt != null || accepted,
      ),
      OrderStep(
        key: 'accepted',
        label: '大厨接单，开始做',
        at: decidedAt,
        done: accepted,
      ),
      OrderStep(
        key: 'done',
        label: '已出餐',
        at: doneAt,
        done: status == 'done',
      ),
    ];
  }

  KitchenOrder copyWith({
    String? status,
    String? rejectReason,
    DateTime? ackedAt,
    DateTime? decidedAt,
    DateTime? doneAt,
    DateTime? cancelledAt,
    List<OrderItem>? items,
    String? kitchenName,
  }) {
    return KitchenOrder(
      id: id,
      kitchenId: kitchenId,
      ownerId: ownerId,
      dinerId: dinerId,
      dinerName: dinerName,
      status: status ?? this.status,
      note: note,
      rejectReason: rejectReason ?? this.rejectReason,
      orderDate: orderDate,
      mealTimeType: mealTimeType,
      mealTimeStart: mealTimeStart,
      mealTimeEnd: mealTimeEnd,
      ackedAt: ackedAt ?? this.ackedAt,
      decidedAt: decidedAt ?? this.decidedAt,
      doneAt: doneAt ?? this.doneAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      createdAt: createdAt,
      items: items ?? this.items,
      kitchenName: kitchenName ?? this.kitchenName,
    );
  }

  factory KitchenOrder.fromJson(
    Map<String, dynamic> json, {
    List<OrderItem> items = const [],
    String kitchenName = '',
  }) {
    return KitchenOrder(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      ownerId: (json['owner_id'] ?? '').toString(),
      dinerId: (json['diner_id'] ?? '').toString(),
      dinerName: (json['diner_name'] ?? '朋友').toString(),
      status: (json['status'] ?? 'pending').toString(),
      note: (json['note'] ?? '').toString(),
      rejectReason: (json['reject_reason'] ?? '').toString(),
      orderDate: (json['order_date'] ?? '').toString(),
      mealTimeType: (json['meal_time_type'] ?? 'asap').toString(),
      mealTimeStart: json['meal_time_start']?.toString(),
      mealTimeEnd: json['meal_time_end']?.toString(),
      ackedAt: DateTime.tryParse((json['acked_at'] ?? '').toString()),
      decidedAt: DateTime.tryParse((json['decided_at'] ?? '').toString()),
      doneAt: DateTime.tryParse((json['done_at'] ?? '').toString()),
      cancelledAt: DateTime.tryParse((json['cancelled_at'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      items: items,
      kitchenName: kitchenName,
    );
  }
}

class ShortageAlert {
  final int id;
  final int kitchenId;
  final String dinerName;
  final String dishName;
  final String ingredientName;
  final double needed;
  final double stock;
  final bool isRead;
  final DateTime createdAt;

  const ShortageAlert({
    required this.id,
    required this.kitchenId,
    required this.dinerName,
    required this.dishName,
    required this.ingredientName,
    required this.needed,
    required this.stock,
    this.isRead = false,
    required this.createdAt,
  });

  factory ShortageAlert.fromJson(Map<String, dynamic> json) {
    return ShortageAlert(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num).toInt(),
      dinerName: (json['diner_name'] ?? '朋友').toString(),
      dishName: (json['dish_name'] ?? '菜品').toString(),
      ingredientName: (json['ingredient_name'] ?? '食材').toString(),
      needed: (json['needed'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class AppNotification {
  final int id;
  final int? kitchenId;
  final int? orderId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    this.kitchenId,
    this.orderId,
    required this.title,
    this.body = '',
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num).toInt(),
      kitchenId: (json['kitchen_id'] as num?)?.toInt(),
      orderId: (json['order_id'] as num?)?.toInt(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class KitchenBadge {
  final int pending;
  final int alerts;

  const KitchenBadge({this.pending = 0, this.alerts = 0});
}

class CartEntry {
  final Dish dish;
  final int count;

  const CartEntry({required this.dish, required this.count});
}

class DishShortageDetail {
  final int ingredientId;
  final String ingredientName;
  final String unit;
  final double needed;
  final double stock;
  final double short;
  final String dishes;

  const DishShortageDetail({
    required this.ingredientId,
    required this.ingredientName,
    required this.unit,
    required this.needed,
    required this.stock,
    required this.short,
    this.dishes = '',
  });
}

class DishAvailability {
  final bool hasRecipe;
  final int? canMake;
  final List<DishShortageDetail> lacks;

  const DishAvailability({
    required this.hasRecipe,
    required this.canMake,
    this.lacks = const [],
  });

  bool get soldOut => canMake != null && canMake! <= 0;

  String get text {
    if (canMake == null) return '';
    return canMake! > 0 ? '还能做 $canMake 份' : '食材不足';
  }
}

class OrderAvailabilityCheck {
  final bool ok;
  final List<DishShortageDetail> problems;

  const OrderAvailabilityCheck({required this.ok, this.problems = const []});
}

class AcceptOrderResult {
  final bool ok;
  final List<DishShortageDetail> problems;

  const AcceptOrderResult({required this.ok, this.problems = const []});
}

String _formatNum(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}
