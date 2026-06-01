import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// 颜色提取工具类
class ColorExtractor {
  static const int _maxCacheEntries = 96;
  static final LinkedHashMap<String, ExtractedColors> _cache =
      LinkedHashMap<String, ExtractedColors>();
  static final Map<String, Future<ExtractedColors>> _pending =
      <String, Future<ExtractedColors>>{};

  /// 从图片URL提取主色调和暗色背景
  /// 降低采样分辨率以减少主线程阻塞
  static Future<ExtractedColors> extractFromUrl(String imageUrl) async {
    final cached = _readCache(imageUrl);
    if (cached != null) {
      return cached;
    }

    final pending = _pending[imageUrl];
    if (pending != null) {
      return pending;
    }

    final future = _extract(imageUrl);
    _pending[imageUrl] = future;
    return future.whenComplete(() {
      _pending.remove(imageUrl);
    });
  }

  static Future<ExtractedColors> _extract(String imageUrl) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(100, 100),
        maximumColorCount: 16,
        filters: [],
      );

      // 收集所有颜色样本
      final colors = palette.colors.toList();
      
      if (colors.isEmpty) {
        return _writeCache(imageUrl, ExtractedColors.fallback());
      }

      // 计算加权平均颜色（基于像素占比）
      final avgColor = _computeWeightedAverage(colors, palette);
      
      // 找到最具代表性的鲜艳颜色
      final vibrant = palette.vibrantColor?.color ?? avgColor;
      
      // 使用暗色样本或从平均颜色生成暗色背景
      final darkMuted = palette.darkMutedColor?.color ?? _darken(avgColor, 0.5);
      
      // 渐变起始颜色 - 使用平均颜色并降低饱和度
      final muted = _mute(avgColor, 0.2);
      
      // 确保背景颜色足够暗以显示白色文字
      final bgHsl = HSLColor.fromColor(darkMuted);
      final safeBackground = bgHsl.lightness < 0.15 
          ? darkMuted 
          : bgHsl.withSaturation(bgHsl.saturation * 0.7).withLightness(0.12).toColor();

      return _writeCache(
        imageUrl,
        ExtractedColors(
          primary: vibrant,
          background: safeBackground,
          gradientStart: muted.withValues(alpha: 0.7),
          gradientEnd: safeBackground,
        ),
      );
    } catch (e) {
      return _writeCache(imageUrl, ExtractedColors.fallback());
    }
  }

  static ExtractedColors? _readCache(String imageUrl) {
    final cached = _cache.remove(imageUrl);
    if (cached != null) {
      _cache[imageUrl] = cached;
    }
    return cached;
  }

  static ExtractedColors _writeCache(String imageUrl, ExtractedColors colors) {
    _cache.remove(imageUrl);
    _cache[imageUrl] = colors;
    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return colors;
  }

  /// 计算颜色的加权平均值
  static Color _computeWeightedAverage(List<Color> colors, PaletteGenerator palette) {
    if (colors.isEmpty) return Colors.black;
    
    double r = 0, g = 0, b = 0;
    double totalWeight = 0;
    
    for (final color in colors) {
      // 计算颜色的"重要性"权重：鲜艳且不太暗的颜色权重更高
      final hsl = HSLColor.fromColor(color);
      final weight = (hsl.saturation * 0.5 + 0.5) * (hsl.lightness.clamp(0.1, 0.9));
      
      r += color.r * weight;
      g += color.g * weight;
      b += color.b * weight;
      totalWeight += weight;
    }
    
    if (totalWeight == 0) return colors.first;
    
    return Color.fromARGB(
      255,
      (r / totalWeight).round().clamp(0, 255),
      (g / totalWeight).round().clamp(0, 255),
      (b / totalWeight).round().clamp(0, 255),
    );
  }

  /// 加深颜色
  static Color _darken(Color color, [double amount = 0.4]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// 降低饱和度
  static Color _mute(Color color, [double amount = 0.3]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation((hsl.saturation - amount).clamp(0.0, 1.0))
        .toColor();
  }
}

/// 提取的颜色集合
class ExtractedColors {
  final Color primary;
  final Color background;
  final Color gradientStart;
  final Color gradientEnd;

  const ExtractedColors({
    required this.primary,
    required this.background,
    required this.gradientStart,
    required this.gradientEnd,
  });

  factory ExtractedColors.fallback() {
    return const ExtractedColors(
      primary: Color(0xFF5B8DEF),
      background: Color(0xFF121212),
      gradientStart: Color(0x99121212),
      gradientEnd: Color(0xFF121212),
    );
  }
}
