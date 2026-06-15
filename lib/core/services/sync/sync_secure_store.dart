import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../../providers/app_preferences.dart';
import 'sync_models.dart';

/// 同步账号令牌的持久化。
///
/// 沿用 App 现有的 SharedPreferences 存储，但令牌不以明文落盘：
/// JSON 先 XOR 混淆（keystream = SHA256(passphrase) 循环）再 base64。
/// 与 [ObfuscatedSecrets] 一样，这是「防 grep/strings」级别的混淆，
/// 不是强加密；真正高安全场景应使用系统钥匙串或后端代理。
class SyncSecureStore {
  SyncSecureStore._();

  static const String _passphrase = 'LinPlayer::sync::token::v1';
  static const String _keyPrefix = 'sync_account_';
  static List<int>? _keyCache;

  static List<int> get _key =>
      _keyCache ??= sha256.convert(utf8.encode(_passphrase)).bytes;

  static String _obfuscate(String plain) {
    final bytes = utf8.encode(plain);
    final key = _key;
    final out = List<int>.filled(bytes.length, 0);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ key[i % key.length];
    }
    return base64Encode(out);
  }

  static String? _deobfuscate(String encoded) {
    try {
      final bytes = base64Decode(encoded);
      final key = _key;
      final out = List<int>.filled(bytes.length, 0);
      for (var i = 0; i < bytes.length; i++) {
        out[i] = bytes[i] ^ key[i % key.length];
      }
      return utf8.decode(out);
    } catch (_) {
      return null;
    }
  }

  static String _prefKey(SyncService service) => '$_keyPrefix${service.id}';

  static SyncAccount? read(SyncService service) {
    final raw = AppPreferencesStore.instance.getString(_prefKey(service));
    if (raw == null || raw.isEmpty) return null;
    final plain = _deobfuscate(raw);
    if (plain == null) return null;
    return SyncAccount.decode(plain);
  }

  static Future<void> write(SyncAccount account) async {
    await AppPreferencesStore.instance.setString(
      _prefKey(account.service),
      _obfuscate(account.encode()),
    );
  }

  static Future<void> clear(SyncService service) async {
    await AppPreferencesStore.instance.remove(_prefKey(service));
  }
}
