import 'package:material_ui/material_ui.dart';

import 'model.dart';
import 'theme.dart';

class PrototypeBadge extends StatelessWidget {
  const PrototypeBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: warningColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: warningColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        compact ? 'PROTO' : 'PROTOTYPE',
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: warningColor,
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C8CFF), Color(0xFF9B7BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        'M',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.48,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.border,
    this.radius = 16,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? panelColorOf(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? borderColorOf(context)),
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: accentColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle(context)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: mutedStyle(context)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: mutedStyle(context)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.color = accentColor,
    this.icon,
    this.outlined = false,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool outlined;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: outlined ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(999),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: panelColorOf(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColorOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 32});

  final ProfilePreset profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: profile.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(profile.icon, size: size * 0.52, color: profile.color),
    );
  }
}

class ScalingStatusPill extends StatelessWidget {
  const ScalingStatusPill({
    super.key,
    required this.isScaling,
    this.compact = false,
  });

  final bool isScaling;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Pill(
      label: isScaling ? '正在缩放' : '待机',
      color: isScaling ? successColor : mutedColorOf(context),
      icon: isScaling ? Icons.play_circle_outline : Icons.pause_circle_outline,
      compact: compact,
    );
  }
}

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.hint,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: labelStyle(context))),
            Text(
              valueLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: accentColor,
          inactiveColor: borderColorOf(context),
        ),
        if (hint != null) Text(hint!, style: mutedStyle(context)),
      ],
    );
  }
}

class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle(context)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: inputFillColorOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColorOf(context)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              dropdownColor: panelColorOf(context),
              items: items
                  .map(
                    (T item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(
                        labelOf(item),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: mutedStyle(context)),
        ],
      ],
    );
  }
}

class HotkeyRow extends StatelessWidget {
  const HotkeyRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: hint,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyCap(value),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onTap,
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: '更换快捷键',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class LinuxNote extends StatelessWidget {
  const LinuxNote({super.key, required this.text, this.icon = Icons.terminal});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: mutedStyle(context))),
        ],
      ),
    );
  }
}

class MockWindowPreview extends StatelessWidget {
  const MockWindowPreview({
    super.key,
    required this.title,
    required this.badge,
    this.scaled = false,
    this.scale = 2.0,
    this.showChrome = true,
  });

  final String title;
  final String badge;
  final bool scaled;
  final double scale;
  final bool showChrome;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF18213D), Color(0xFF3A1E4A), Color(0xFF0E2A2A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: scaled
                  ? accentColor.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.14),
              width: scaled ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _PreviewGridPainter()),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 30,
                  color: Colors.black.withValues(alpha: 0.28),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _Dot(color: const Color(0xFFFF6B7A)),
                      const SizedBox(width: 5),
                      _Dot(color: const Color(0xFFFFD166)),
                      const SizedBox(width: 5),
                      _Dot(color: const Color(0xFF3DDC97)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      Pill(
                        label: badge,
                        color: scaled ? successColor : warningColor,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 60,
                child: Center(
                  child: Icon(
                    Icons.auto_awesome,
                    size: 36,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            scaled ? '放大输出' : '源窗口',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            scaled
                                ? '${scale.toStringAsFixed(1)}× · Vulkan compute'
                                : 'Portal · ScreenCast',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      scaled ? Icons.fullscreen : Icons.crop_free,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PreviewGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
