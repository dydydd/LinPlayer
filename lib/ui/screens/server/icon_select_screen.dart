import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/providers/app_providers.dart';

/// 图标选择页面
class IconSelectScreen extends ConsumerStatefulWidget {
  final String serverId;
  
  const IconSelectScreen({super.key, required this.serverId});
  
  @override
  ConsumerState<IconSelectScreen> createState() => _IconSelectScreenState();
}

class _IconSelectScreenState extends ConsumerState<IconSelectScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _urlController = TextEditingController();
  
  final List<IconLibrary> _libraries = [];
  bool _isLoading = true;
  String? _loadError;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDefaultLibraries();
  }

  Future<void> _loadDefaultLibraries() async {
    final defaultLibraries = [
      _IconLibSource(
        name: 'Zzzの方形Emby图标',
        url: 'https://juhe.greentea520.xyz/share/78aspf.json',
      ),
    ];

    for (final source in defaultLibraries) {
      try {
        final dio = Dio();
        final resp = await dio.get(source.url);
        final icons = _parseIconJson(jsonEncode(resp.data));
        if (mounted) {
          setState(() {
            _libraries.add(IconLibrary(
              name: source.name,
              url: source.url,
              icons: icons,
            ));
          });
        }
      } catch (e) {
        debugPrint('加载图标库失败: ${source.url}, 错误: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (_libraries.isEmpty) {
          _loadError = '未能加载任何图标库，请检查网络连接或手动添加';
        }
      });
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图标选择'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '本地图片'),
            Tab(text: '网络图标库'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLocalTab(),
          _buildNetworkTab(),
        ],
      ),
    );
  }
  
  Widget _buildLocalTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '从相册或文件选择',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _pickFromGallery(),
            icon: const Icon(Icons.photo_library),
            label: const Text('从相册选择'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickFromFiles(),
            icon: const Icon(Icons.folder_open),
            label: const Text('从文件选择'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        _updateServerIcon(image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }
  
  Future<void> _pickFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          _updateServerIcon(path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败: $e')),
        );
      }
    }
  }
  
  void _updateServerIcon(String imagePath) {
    final servers = ref.read(serverListProvider);
    final server = servers.firstWhere((s) => s.id == widget.serverId);
    ref.read(serverListProvider.notifier).updateServer(
      server.copyWith(iconUrl: imagePath),
    );
    Navigator.pop(context);
  }
  
  Widget _buildNetworkTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载图标库...'),
          ],
        ),
      );
    }

    if (_libraries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _loadError ?? '暂无图标库',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddLibraryDialog(),
              icon: const Icon(Icons.add),
              label: const Text('添加网络图标库'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Library list
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('图标库', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '共 ${_libraries.expand((l) => l.icons).length} 个图标',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._libraries.map((lib) => Card(
                child: ListTile(
                  title: Text(lib.name),
                  subtitle: Text(lib.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('${lib.icons.length} 个图标'),
                ),
              )),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showAddLibraryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('添加网络图标库'),
              ),
            ],
          ),
        ),
        const Divider(),
        // Icon grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _libraries.expand((l) => l.icons).length,
            itemBuilder: (context, index) {
              final icon = _libraries.expand((l) => l.icons).elementAt(index);
              return _IconGridItem(
                icon: icon,
                onTap: () => _selectIcon(icon),
              );
            },
          ),
        ),
      ],
    );
  }
  
  Future<void> _showAddLibraryDialog() async {
    final urlController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加图标库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '图标库名称',
                hintText: '我的图标库',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'JSON URL',
                hintText: 'https://example.com/icons.json',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持直接粘贴JSON数组或URL',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final result = await _loadIconLibrary(urlController.text, _urlController.text);
              if (!mounted) return;
              _showAddResult(result);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showAddResult(String? result) {
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
    }
    Navigator.pop(context);
  }

  Future<String?> _loadIconLibrary(String name, String urlOrJson) async {
    if (urlOrJson.isEmpty) return null;

    try {
      List<IconItem> icons = [];

      // 尝试解析JSON
      if (urlOrJson.trim().startsWith('[') || urlOrJson.trim().startsWith('{')) {
        // 直接是JSON文本
        icons = _parseIconJson(urlOrJson);
      } else if (urlOrJson.startsWith('http')) {
        // 是URL，使用dio加载
        final dio = Dio();
        final resp = await dio.get(urlOrJson);
        icons = _parseIconJson(jsonEncode(resp.data));
      }

      if (icons.isNotEmpty) {
        setState(() {
          _libraries.add(IconLibrary(
            name: name.isNotEmpty ? name : '自定义图标库',
            url: urlOrJson,
            icons: icons,
          ));
        });

        return '成功加载 ${icons.length} 个图标';
      }
      return '未找到有效图标';
    } catch (e) {
      return '加载失败: ${e.toString()}';
    }
  }
  
  List<IconItem> _parseIconJson(String jsonText) {
    final icons = <IconItem>[];
    
    // 简单正则解析，提取name和url
    final nameRegex = RegExp(r'["]name["]\s*:\s*["]([^"]+)["]');
    final urlRegex = RegExp(r'["]url["]\s*:\s*["](https?://[^"]+)["]');
    
    final names = nameRegex.allMatches(jsonText).map((m) => m.group(1)!).toList();
    final urls = urlRegex.allMatches(jsonText).map((m) => m.group(1)!).toList();
    
    for (var i = 0; i < urls.length; i++) {
      icons.add(IconItem(
        name: i < names.length ? names[i] : '图标 ${i + 1}',
        url: urls[i],
      ));
    }
    
    return icons;
  }
  
  void _selectIcon(IconItem icon) {
    final servers = ref.read(serverListProvider);
    final server = servers.firstWhere((s) => s.id == widget.serverId);
    ref.read(serverListProvider.notifier).updateServer(
      server.copyWith(iconUrl: icon.url),
    );
    Navigator.pop(context);
  }
}

class _IconLibSource {
  final String name;
  final String url;

  _IconLibSource({required this.name, required this.url});
}

class IconLibrary {
  final String name;
  final String url;
  final List<IconItem> icons;
  
  IconLibrary({required this.name, required this.url, required this.icons});
}

class IconItem {
  final String name;
  final String url;
  
  IconItem({required this.name, required this.url});
}

class _IconGridItem extends StatelessWidget {
  final IconItem icon;
  final VoidCallback onTap;
  
  const _IconGridItem({required this.icon, required this.onTap});
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  icon.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            icon.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
