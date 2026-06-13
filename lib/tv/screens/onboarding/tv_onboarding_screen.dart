import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';

/// TV 引导页
/// 3 页引导（遥控器/导航栏/焦点系统），首次启动时展示
class TvOnboardingScreen extends StatefulWidget {
  const TvOnboardingScreen({super.key});

  @override
  State<TvOnboardingScreen> createState() => _TvOnboardingScreenState();
}

class _TvOnboardingScreenState extends State<TvOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: TvDesignTokens.pageTransitionDuration,
        curve: TvDesignTokens.pageTransitionCurve,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: TvDesignTokens.pageTransitionDuration,
        curve: TvDesignTokens.pageTransitionCurve,
      );
    }
  }

  void _finishOnboarding() {
    // TODO: 保存 hasSeenOnboarding 到 shared_preferences
    TvToast.show(context, '欢迎使用 LinPlayer TV！');
    Navigator.pop(context);
  }

  void _skipOnboarding() {
    // TODO: 保存 hasSeenOnboarding 到 shared_preferences
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _nextPage();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _previousPage();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (_currentPage == _totalPages - 1) {
                _finishOnboarding();
              } else {
                _nextPage();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // 页面内容
            PageView.builder(
              controller: _pageController,
              itemCount: _totalPages,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) => _buildPage(index),
            ),
            // 跳过按钮
            Positioned(
              top: TvDesignTokens.spacingLg,
              right: TvDesignTokens.spacingLg,
              child: TvFocusable(
                onSelect: _skipOnboarding,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TvDesignTokens.spacingMd,
                    vertical: TvDesignTokens.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    color: TvDesignTokens.surface,
                    borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                  ),
                  child: const Text(
                    '跳过',
                    style: TextStyle(
                      fontSize: TvDesignTokens.fontSizeSm,
                      color: TvDesignTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            // 底部指示器和导航
            Positioned(
              bottom: TvDesignTokens.spacingXxl,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // 圆点指示器
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalPages, (index) {
                      return AnimatedContainer(
                        duration: TvDesignTokens.focusAnimationDuration,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? TvDesignTokens.brand
                              : const Color(0x40FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: TvDesignTokens.spacingLg),
                  // 完成按钮（最后一页）
                  if (_currentPage == _totalPages - 1)
                    TvFocusable(
                      onSelect: _finishOnboarding,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TvDesignTokens.spacingLg,
                          vertical: TvDesignTokens.spacingSm,
                        ),
                        decoration: BoxDecoration(
                          color: TvDesignTokens.brand,
                          borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                        ),
                        child: const Text(
                          '开始使用',
                          style: TextStyle(
                            fontSize: TvDesignTokens.fontSizeMd,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    final pages = [
      _OnboardingPageData(
        icon: Icons.gamepad,
        title: '使用遥控器导航',
        description: '使用方向键移动焦点，确认键选择，返回键返回',
      ),
      _OnboardingPageData(
        icon: Icons.view_sidebar,
        title: '左侧导航栏',
        description: '按左右键在导航栏和内容区之间切换',
      ),
      _OnboardingPageData(
        icon: Icons.highlight_alt,
        title: '焦点指示',
        description: '当前项高亮放大表示选中，可执行操作',
      ),
    ];

    final page = pages[index];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: TvDesignTokens.brand.withOpacity(0.15),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              page.icon,
              color: TvDesignTokens.brand,
              size: 40,
            ),
          ),
          const SizedBox(height: TvDesignTokens.spacingLg),
          // 标题
          Text(
            page.title,
            style: const TextStyle(
              fontSize: TvDesignTokens.fontSizeXl,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: TvDesignTokens.spacingMd),
          // 说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TvDesignTokens.spacingXxl),
            child: Text(
              page.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TvDesignTokens.fontSizeMd,
                color: TvDesignTokens.textSecondary,
                height: TvDesignTokens.lineHeightRelaxed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;

  _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}
