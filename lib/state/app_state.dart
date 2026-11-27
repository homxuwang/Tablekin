import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/kitchen_backend.dart';
import '../services/local_demo_backend.dart';
import '../services/supabase_backend.dart';

class AppState extends ChangeNotifier {
  static const _kSupabaseUrl = 'tablekin_supabase_url';
  static const _kSupabaseKey = 'tablekin_supabase_anon_key';
  static const _kUseCloud = 'tablekin_use_cloud';
  static const _kDinerName = 'tablekin_diner_name';
  static const _kLastKitchenId = 'tablekin_last_kitchen_id';

  static const String envSupabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String envSupabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  final LocalDemoKitchenBackend _demoBackend = LocalDemoKitchenBackend();
  KitchenBackend _backend;

  String supabaseUrl = envSupabaseUrl;
  String supabaseAnonKey = envSupabaseKey;
  bool _supabaseInitialized = false;

  bool initialized = false;
  int tabIndex = 0;
  int dataVersion = 0;

  // Cart keyed by kitchenId -> dishId -> CartEntry
  final Map<int, Map<int, CartEntry>> _carts = {};

  String dinerName = '';
  int? lastKitchenId;

  // Live summary counts for badges
  int pendingOrdersCount = 0;
  int unreadNotificationsCount = 0;

  Timer? _debounce;

  AppState() : _backend = LocalDemoKitchenBackend() {
    _backend = _demoBackend;
  }

  KitchenBackend get backend => _backend;
  AppUser? get currentUser => _backend.currentUser;
  bool get isCloud => _backend.isCloud;
  bool get isSignedIn => _backend.currentUser != null;

  int get totalOrdersBadge => pendingOrdersCount + unreadNotificationsCount;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    dinerName = prefs.getString(_kDinerName) ?? '';
    lastKitchenId = prefs.getInt(_kLastKitchenId);

    final savedUrl = prefs.getString(_kSupabaseUrl) ?? '';
    final savedKey = prefs.getString(_kSupabaseKey) ?? '';
    if (savedUrl.isNotEmpty && savedKey.isNotEmpty) {
      supabaseUrl = savedUrl;
      supabaseAnonKey = savedKey;
    }

    final useCloud = prefs.getBool(_kUseCloud) ??
        (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty);

    if (useCloud && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      try {
        await _activateSupabase(supabaseUrl, supabaseAnonKey);
      } catch (_) {
        _activateDemo();
      }
    } else {
      _activateDemo();
    }

    initialized = true;
    notifyListeners();
    await refreshBadges();
  }

  void _activateDemo() {
    _backend.unsubscribeLiveUpdates();
    _backend = _demoBackend;
    _backend.subscribeLiveUpdates(_scheduleLiveRefresh);
  }

  Future<void> _activateSupabase(String url, String anonKey) async {
    _backend.unsubscribeLiveUpdates();
    if (!_supabaseInitialized) {
      await Supabase.initialize(url: url.trim(), anonKey: anonKey.trim());
      _supabaseInitialized = true;
    }
    _backend = SupabaseKitchenBackend(Supabase.instance.client);
    await _backend.restoreSession();
    if (_backend.currentUser != null) {
      _backend.subscribeLiveUpdates(_scheduleLiveRefresh);
    }
  }

  Future<void> switchToDemo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseCloud, false);
    _activateDemo();
    bumpDataVersion();
    await refreshBadges();
  }

  Future<void> configureAndSwitchToSupabase(String url, String anonKey) async {
    final cleanUrl = url.trim();
    final cleanKey = anonKey.trim();
    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      throw Exception('请填写完整的 Supabase URL 和 Anon Key');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseUrl, cleanUrl);
    await prefs.setString(_kSupabaseKey, cleanKey);
    await prefs.setBool(_kUseCloud, true);
    supabaseUrl = cleanUrl;
    supabaseAnonKey = cleanKey;
    await _activateSupabase(cleanUrl, cleanKey);
    bumpDataVersion();
    await refreshBadges();
  }

  Future<void> signIn(String email, String password) async {
    await _backend.signInWithPassword(email, password);
    _backend.subscribeLiveUpdates(_scheduleLiveRefresh);
    bumpDataVersion();
    await refreshBadges();
  }

  Future<void> signUp(String email, String password, {String? displayName}) async {
    await _backend.signUpWithPassword(email, password, displayName: displayName);
    _backend.subscribeLiveUpdates(_scheduleLiveRefresh);
    bumpDataVersion();
    await refreshBadges();
  }

  Future<void> signOut() async {
    await _backend.signOut();
    pendingOrdersCount = 0;
    unreadNotificationsCount = 0;
    bumpDataVersion();
  }

  void setTab(int index) {
    if (tabIndex == index) return;
    tabIndex = index;
    notifyListeners();
  }

  void bumpDataVersion() {
    dataVersion++;
    notifyListeners();
  }

  void _scheduleLiveRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      bumpDataVersion();
      refreshBadges();
    });
  }

  Future<void> refreshBadges() async {
    if (!isSignedIn) {
      pendingOrdersCount = 0;
      unreadNotificationsCount = 0;
      notifyListeners();
      return;
    }
    try {
      final kitchens = await _backend.fetchMyKitchens();
      final badges = await _backend.fetchKitchenBadges(kitchens.map((k) => k.id).toList());
      final notices = await _backend.fetchUnreadNotifications();
      pendingOrdersCount = badges.values.fold<int>(0, (s, b) => s + b.pending);
      unreadNotificationsCount = notices.length;
      notifyListeners();
    } catch (_) {
      // Non-fatal
    }
  }

  Future<void> setDinerName(String value) async {
    dinerName = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDinerName, dinerName);
  }

  Future<void> setLastKitchenId(int kitchenId) async {
    lastKitchenId = kitchenId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastKitchenId, kitchenId);
  }

  // ---------- Cart helpers ----------

  List<CartEntry> cartEntries(int kitchenId) {
    return (_carts[kitchenId]?.values.toList() ?? const <CartEntry>[]);
  }

  int dishCartCount(int kitchenId, int dishId) {
    return _carts[kitchenId]?[dishId]?.count ?? 0;
  }

  int cartTotalCount(int kitchenId) {
    final map = _carts[kitchenId];
    if (map == null) return 0;
    return map.values.fold<int>(0, (s, e) => s + e.count);
  }

  void addToCart(int kitchenId, Dish dish) {
    final map = _carts.putIfAbsent(kitchenId, () => <int, CartEntry>{});
    final existing = map[dish.id];
    map[dish.id] = CartEntry(dish: dish, count: (existing?.count ?? 0) + 1);
    notifyListeners();
  }

  void decreaseFromCart(int kitchenId, int dishId) {
    final map = _carts[kitchenId];
    if (map == null || !map.containsKey(dishId)) return;
    final current = map[dishId]!;
    if (current.count <= 1) {
      map.remove(dishId);
    } else {
      map[dishId] = CartEntry(dish: current.dish, count: current.count - 1);
    }
    notifyListeners();
  }

  void clearCart(int kitchenId) {
    _carts.remove(kitchenId);
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _backend.unsubscribeLiveUpdates();
    super.dispose();
  }
}

/// Lightweight InheritedNotifier so we don't need extra state management packages.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }
}
