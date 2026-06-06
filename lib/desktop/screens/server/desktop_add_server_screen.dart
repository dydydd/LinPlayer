import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';

/// 桌面端添加服务器页
class DesktopAddServerScreen extends ConsumerStatefulWidget {
  const DesktopAddServerScreen({super.key});
  
  @override
  ConsumerState<DesktopAddServerScreen> createState() => _DesktopAddServerScreenState();
}

class _DesktopAddServerScreenState extends ConsumerState<DesktopAddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _pathController = TextEditingController(text: '/emby');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  @override
  void dispose() {
    _urlController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加服务器'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  const Text(
                    '连接到 Emby 服务器',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '输入服务器信息以连接到您的媒体库',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // 服务器地址
                  _buildTextField(
                    controller: _urlController,
                    label: '服务器地址',
                    hint: 'https://example.com',
                    prefixIcon: Icons.link,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入服务器地址';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 路径
                  _buildTextField(
                    controller: _pathController,
                    label: '路径',
                    hint: '/emby',
                    prefixIcon: Icons.folder,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 服务器名称
                  _buildTextField(
                    controller: _nameController,
                    label: '服务器名称（可选）',
                    hint: '我的服务器',
                    prefixIcon: Icons.edit,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 分隔线
                  const Divider(),
                  
                  const SizedBox(height: 24),
                  
                  // 用户名
                  _buildTextField(
                    controller: _usernameController,
                    label: '用户名',
                    hint: '输入用户名',
                    prefixIcon: Icons.person,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 密码
                  _buildTextField(
                    controller: _passwordController,
                    label: '密码',
                    hint: '输入密码',
                    prefixIcon: Icons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // 连接按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _connectServer,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '连接',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 批量解析按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.paste),
                      label: const Text('批量解析分享文本'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 20),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF5B8DEF), width: 2),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
  
  Future<void> _connectServer() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      // 这里实现连接逻辑
      final url = _urlController.text.trim();
      final path = _pathController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      // TODO: 实现实际的认证逻辑，当前仅保存服务器配置
      debugPrint('Password length: ${password.length}'); // 避免未使用警告
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : '服务器';
      
      // 创建服务器配置
      final server = ServerConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        baseUrl: '$url$path',
        username: username,
      );
      
      ref.read(serverListProvider.notifier).addServer(server);
      
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器添加成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
