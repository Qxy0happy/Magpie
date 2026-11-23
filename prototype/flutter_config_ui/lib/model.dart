import 'package:material_ui/material_ui.dart';

/// PROTOTYPE ONLY — fake data for the Flutter configuration UI exploration.
/// Nothing here talks to the engine or persists to disk.

class ProfilePreset {
  const ProfilePreset({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.scalingMode,
    required this.frameRate,
    required this.matchRule,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String scalingMode;
  final int frameRate;
  final String matchRule;
}

class ScalingModePreset {
  const ScalingModePreset({
    required this.name,
    required this.description,
    required this.tag,
    required this.cost,
  });

  final String name;
  final String description;
  final String tag;
  final String cost;
}

const List<String> hotkeyOptions = <String>[
  'Alt+Shift+A',
  'Ctrl+Alt+A',
  'Super+Shift+A',
];

String nextHotkey(String current) {
  final int index = hotkeyOptions.indexOf(current);
  return hotkeyOptions[(index + 1) % hotkeyOptions.length];
}

class PrototypeState extends ChangeNotifier {
  int activeProfile = 1;
  String scalingMode = 'NIS';
  double scale = 2.0;
  int frameRate = 120;
  bool cursorScaling = true;
  bool frameRateLimiter = true;
  bool autoHideCursor = true;
  bool showOverlay = true;
  bool windowedMode = false;
  bool isScaling = false;
  String captureMethod = 'Portal · ScreenCast';
  String output = 'DP-1 · 2560×1440 · 165 Hz';
  String fullscreenHotkey = 'Alt+Shift+A';
  String windowedHotkey = 'Alt+Shift+W';
  String screenshotHotkey = 'Alt+Shift+S';
  String timer = '关闭';
  bool saveAsProfile = true;
  String profileDraftName = '游戏 · 1440p';

  static const List<ProfilePreset> profiles = <ProfilePreset>[
    ProfilePreset(
      name: '默认',
      subtitle: '所有窗口',
      icon: Icons.layers_outlined,
      color: Color(0xFF6C8CFF),
      scalingMode: 'FSR',
      frameRate: 60,
      matchRule: '未匹配其他配置时使用',
    ),
    ProfilePreset(
      name: '游戏',
      subtitle: '全屏游戏',
      icon: Icons.sports_esports_outlined,
      color: Color(0xFF3DDC97),
      scalingMode: 'NIS',
      frameRate: 120,
      matchRule: '窗口类名包含 game / unity',
    ),
    ProfilePreset(
      name: '动漫',
      subtitle: '视频与动画',
      icon: Icons.auto_awesome_outlined,
      color: Color(0xFFB18CFF),
      scalingMode: 'Anime4K',
      frameRate: 60,
      matchRule: '窗口标题包含 mpv / 播放器',
    ),
    ProfilePreset(
      name: '复古',
      subtitle: '像素与 CRT',
      icon: Icons.videogame_asset_outlined,
      color: Color(0xFFFFB86C),
      scalingMode: 'CRT',
      frameRate: 60,
      matchRule: '手动选择',
    ),
  ];

  static const List<ScalingModePreset> scalingModes = <ScalingModePreset>[
    ScalingModePreset(
      name: 'FSR',
      description: 'AMD FidelityFX Super Resolution，空间放大，兼容性最好。',
      tag: '通用',
      cost: '低',
    ),
    ScalingModePreset(
      name: 'NIS',
      description: 'NVIDIA Image Scaling，锐度可调，适合游戏画面。',
      tag: '游戏',
      cost: '低',
    ),
    ScalingModePreset(
      name: 'Anime4K',
      description: '面向动画的神经网络放大，GPU 负载较高。',
      tag: '动画',
      cost: '高',
    ),
    ScalingModePreset(
      name: 'CAS',
      description: '对比度自适应锐化，常与其他放大组合。',
      tag: '锐化',
      cost: '低',
    ),
    ScalingModePreset(
      name: 'Bicubic',
      description: '经典双三次插值，最轻量。',
      tag: '基础',
      cost: '极低',
    ),
    ScalingModePreset(
      name: 'CRT',
      description: 'CRT 扫描线与几何模拟，适合复古游戏。',
      tag: '复古',
      cost: '中',
    ),
  ];

  static const List<String> captureMethods = <String>[
    'Portal · ScreenCast',
    'PipeWire 流（实验）',
  ];

  static const List<String> outputs = <String>[
    'DP-1 · 2560×1440 · 165 Hz',
    'HDMI-A-1 · 1920×1080 · 60 Hz',
  ];

  static const List<String> timers = <String>['关闭', '30 秒', '60 秒', '5 分钟'];

  static const List<int> frameRates = <int>[30, 60, 120, 144];

  ProfilePreset get profile => profiles[activeProfile];

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void selectProfile(int index) {
    if (index < 0 || index >= profiles.length) {
      return;
    }
    activeProfile = index;
    scalingMode = profiles[index].scalingMode;
    frameRate = profiles[index].frameRate;
    notifyListeners();
  }

  void setScalingMode(String mode) {
    scalingMode = mode;
    notifyListeners();
  }

  void setScale(double value) {
    scale = value;
    notifyListeners();
  }

  void setFrameRate(int value) {
    frameRate = value;
    notifyListeners();
  }

  void toggleScaling() {
    isScaling = !isScaling;
    notifyListeners();
  }

  void reset() {
    activeProfile = 1;
    scalingMode = 'NIS';
    scale = 2.0;
    frameRate = 120;
    cursorScaling = true;
    frameRateLimiter = true;
    autoHideCursor = true;
    showOverlay = true;
    windowedMode = false;
    isScaling = false;
    captureMethod = 'Portal · ScreenCast';
    output = 'DP-1 · 2560×1440 · 165 Hz';
    fullscreenHotkey = 'Alt+Shift+A';
    windowedHotkey = 'Alt+Shift+W';
    screenshotHotkey = 'Alt+Shift+S';
    timer = '关闭';
    saveAsProfile = true;
    profileDraftName = '游戏 · 1440p';
    notifyListeners();
  }

  String get summary =>
      '${profile.name} · $scalingMode · ${scale.toStringAsFixed(1)}× · ${frameRate}fps · $captureMethod';
}
