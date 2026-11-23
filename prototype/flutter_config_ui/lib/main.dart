// PROTOTYPE ONLY — throwaway UI exploration for the Magpie Linux Flutter
// configuration interface. Do not merge this into the product.
//
// Question: after replacing the WinUI shell with Flutter, how should the
// configuration UI be structured on Linux?
//
// Plan: three structurally different variants on one window, switchable from
// the floating bottom bar or with keys 1 / 2 / 3. The initial variant can be
// selected with:
//   flutter run -d linux --dart-define=PROTOTYPE_VARIANT=b
//
// No engine connection, no persistence. See README.md for the comparison guide.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'model.dart';
import 'theme.dart';
import 'variant_switcher.dart';
import 'variants/variant_a.dart';
import 'variants/variant_b.dart';
import 'variants/variant_c.dart';

void main() {
  runApp(const PrototypeApp());
}

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key});

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magpie 配置界面原型',
      debugShowCheckedModeBanner: false,
      theme: buildPrototypeTheme(Brightness.light),
      darkTheme: buildPrototypeTheme(Brightness.dark),
      themeMode: _themeMode,
      home: PrototypeShell(
        themeMode: _themeMode,
        onToggleTheme: () {
          setState(() {
            _themeMode = _themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          });
        },
      ),
    );
  }
}

class PrototypeShell extends StatefulWidget {
  const PrototypeShell({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<PrototypeShell> createState() => _PrototypeShellState();
}

class _PrototypeShellState extends State<PrototypeShell> {
  static const List<String> _variantKeys = <String>['a', 'b', 'c'];
  static const List<String> _variantNames = <String>[
    'A · 侧栏 + 设置卡片',
    'B · 配置优先工作台',
    'C · 设置向导',
  ];

  late final PrototypeState _state;
  late int _variantIndex;

  @override
  void initState() {
    super.initState();
    _state = PrototypeState();
    const String initial = String.fromEnvironment(
      'PROTOTYPE_VARIANT',
      defaultValue: 'a',
    );
    final int index = _variantKeys.indexOf(initial.toLowerCase());
    _variantIndex = index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  void _setVariant(int index) {
    setState(() {
      _variantIndex = (index + _variantKeys.length) % _variantKeys.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1): () => _setVariant(0),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _setVariant(1),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _setVariant(2),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _setVariant(_variantIndex - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _setVariant(_variantIndex + 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _state,
                  builder: (BuildContext context, Widget? child) {
                    final Widget content = switch (_variantIndex) {
                      0 => VariantA(state: _state),
                      1 => VariantB(state: _state),
                      _ => VariantC(state: _state),
                    };
                    return KeyedSubtree(
                      key: ValueKey<int>(_variantIndex),
                      child: content,
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(
                  child: PrototypeSwitcher(
                    state: _state,
                    variantIndex: _variantIndex,
                    variantNames: _variantNames,
                    onVariant: _setVariant,
                    onToggleTheme: widget.onToggleTheme,
                    themeMode: widget.themeMode,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
