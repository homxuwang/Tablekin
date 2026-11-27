import 'package:flutter/material.dart';
import 'screens/root_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TablekinApp());
}

class TablekinApp extends StatefulWidget {
  final AppState? initialState;

  const TablekinApp({super.key, this.initialState});

  @override
  State<TablekinApp> createState() => _TablekinAppState();
}

class _TablekinAppState extends State<TablekinApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState ?? AppState();
    if (!_state.initialized) {
      _state.init();
    }
  }

  @override
  void dispose() {
    if (widget.initialState == null) {
      _state.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: MaterialApp(
        title: '吃好喝好',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const RootShell(),
      ),
    );
  }
}
