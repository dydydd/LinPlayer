import 'dart:convert';
import 'package:crypto/crypto.dart';

/// OAuth 凭据的轻量混淆存储。
///
/// 重要安全说明：
/// 任何随客户端二进制分发的密钥，理论上都可被逆向提取——混淆只能提高门槛，
/// 并非真正安全。若未来出现滥用，应改用后端代理（由服务端持有 secret，
/// 客户端只与自有后端交换 token）。这里的目标仅是「不以明文形式出现在源码/
/// 二进制的可检索字符串中」，避免被简单 grep/strings 直接捞走。
///
/// 实现：密文字节 = 明文 UTF8 字节 XOR keystream，
/// keystream = SHA256(passphrase) 的 32 字节循环。
class ObfuscatedSecrets {
  ObfuscatedSecrets._();

  static const String _passphrase = 'LinPlayer::oauth::keystream::v1';
  static List<int>? _keyCache;

  static List<int> get _key =>
      _keyCache ??= sha256.convert(utf8.encode(_passphrase)).bytes;

  static String _reveal(List<int> cipher) {
    final key = _key;
    final out = List<int>.filled(cipher.length, 0);
    for (var i = 0; i < cipher.length; i++) {
      out[i] = cipher[i] ^ key[i % key.length];
    }
    return utf8.decode(out);
  }

  // 以下为 XOR 密文字节（由 SHA256 keystream 混淆），非明文。
  static const List<int> _traktId = [
    94, 64, 7, 107, 88, 45, 161, 24, 109, 207, 251, 44, 74, 86, 128, 57, //
    28, 25, 181, 219, 228, 246, 2, 118, 33, 9, 178, 128, 140, 203, 179, 119,
    12, 30, 3, 103, 92, 36, 250, 79, 111, 206, 250, 40, 27, 0, 140, 56,
    26, 76, 182, 143, 229, 240, 82, 115, 44, 95, 184, 208, 142, 157, 230, 39
  ];
  static const List<int> _traktSecret = [
    88, 64, 84, 111, 86, 39, 161, 25, 106, 146, 250, 125, 70, 4, 142, 59, //
    29, 28, 177, 141, 176, 167, 82, 113, 47, 11, 227, 129, 139, 203, 228, 119,
    90, 27, 81, 110, 86, 35, 167, 27, 111, 206, 161, 115, 73, 7, 222, 63,
    27, 73, 228, 142, 180, 245, 84, 35, 44, 7, 226, 133, 216, 200, 230, 113
  ];
  static const List<int> _bangumiId = [
    8, 31, 88, 107, 89, 35, 247, 29, 50, 150, 245, 40, 76, 85, 220, 59, //
    28, 72, 179, 139
  ];
  static const List<int> _bangumiSecret = [
    90, 74, 12, 106, 10, 114, 163, 30, 58, 199, 247, 44, 71, 1, 217, 106, //
    29, 77, 227, 138, 224, 247, 86, 47, 45, 14, 225, 129, 139, 145, 182, 113
  ];

  static String get traktClientId => _reveal(_traktId);
  static String get traktClientSecret => _reveal(_traktSecret);
  static String get bangumiAppId => _reveal(_bangumiId);
  static String get bangumiAppSecret => _reveal(_bangumiSecret);
}
