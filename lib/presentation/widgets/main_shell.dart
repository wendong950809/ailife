import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/today/today_page.dart';
import '../pages/timeline/timeline_page.dart';
import '../pages/chat/chat_page.dart';
import '../pages/profile/profile_page.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/ai_provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 2;

  final List<Widget> _pages = [
    const TodayPage(),
    const TimelinePage(),
    const ChatPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.borderLight, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabItem(
                  index: 0,
                  icon: Icons.access_time,
                  label: '首页',
                ),
                _buildTabItem(
                  index: 1,
                  icon: Icons.timeline,
                  label: '时间',
                ),
                Consumer<AiProvider>(
                  builder: (context, aiProvider, child) => _buildTabItem(
                    index: 2,
                    icon: Icons.star,
                    label: aiProvider.aiName,
                    isStarIcon: true,
                  ),
                ),
                _buildTabItem(
                  index: 3,
                  icon: Icons.person_outline,
                  label: '我的',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required IconData icon,
    required String label,
    bool isStarIcon = false,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isStarIcon
                ? Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  )
                : Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
