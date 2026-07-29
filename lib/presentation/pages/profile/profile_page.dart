import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/services/stats_service.dart';
import '../../../providers/auth_provider.dart';
import '../settings/settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final StatsService _statsService = StatsService();

  List<String> _roles = [];
  Map<String, int> _dimensions = {'relations': 0, 'goals': 0, 'events': 0, 'values': 0};
  Map<String, dynamic> _growth = {'days': 0, 'facts': 0, 'understanding': 0.0};
  String _aiInsight = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _statsService.getPersonRoles(),
        _statsService.getLifeDimensions(),
        _statsService.getGrowthStats(),
        _statsService.getAiInsight(),
      ]);

      if (mounted) {
        setState(() {
          _roles = results[0] as List<String>;
          _dimensions = results[1] as Map<String, int>;
          _growth = results[2] as Map<String, dynamic>;
          _aiInsight = results[3] as String;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.profile;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 96),
          children: [
            _buildProfileHeader(profile),
            const SizedBox(height: 16),
            _buildAiSummary(),
            const SizedBox(height: 16),
            _buildWhoAmI(),
            const SizedBox(height: 16),
            _buildMyLife(),
            const SizedBox(height: 16),
            _buildGrowthCard(),
            const SizedBox(height: 16),
            _buildSettingsButton(),
            const SizedBox(height: 20),
            const Text(
              '知伴 v0.1',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(UserProfile? profile) {
    final auth = context.read<AuthProvider>();
    final email = auth.user?.email;

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1D26),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              profile?.username?.isNotEmpty == true
                  ? profile!.username![0]
                  : (email?.isNotEmpty == true
                      ? email![0].toUpperCase()
                      : '用'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          profile?.username ?? email?.split('@').first ?? '用户',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _roles.isEmpty ? '跟知伴多聊聊，我会慢慢认识你' : _roles.join(' · '),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAiSummary() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        _isLoading
            ? '"正在认识你..."'
            : (_aiInsight.isEmpty
                ? '"多跟我聊聊你的生活吧，我会慢慢了解你的性格、目标和价值观。"'
                : '"$_aiInsight"'),
        style: const TextStyle(
          fontSize: 12,
          height: 1.65,
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildWhoAmI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我是谁',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (_roles.isEmpty)
          const Text(
            '还没有角色标签，跟知伴聊聊你是谁',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _roles.map((role) => _buildRoleTag(role)).toList(),
          ),
      ],
    );
  }

  Widget _buildRoleTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMyLife() {
    final items = [
      LifeItem(
        title: '关系',
        subtitle: '${_dimensions['relations']}位重要人物',
        icon: Icons.group_outlined,
      ),
      LifeItem(
        title: '目标',
        subtitle: '${_dimensions['goals']}个进行中',
        icon: Icons.flag_outlined,
      ),
      LifeItem(
        title: '经历',
        subtitle: '${_dimensions['events']}个事件',
        icon: Icons.menu_book_outlined,
      ),
      LifeItem(
        title: '价值观',
        subtitle: '${_dimensions['values']}条核心价值观',
        icon: Icons.favorite_outline,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的人生',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return _buildLifeCard(items[index]);
          },
        ),
      ],
    );
  }

  Widget _buildLifeCard(LifeItem item) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthCard() {
    final understanding = (_growth['understanding'] as double? ?? 0.0);
    final days = _growth['days'] as int? ?? 0;
    final percent = (understanding * 100).toInt();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '数字自我成长',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '理解度 $percent%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '知伴已陪伴你 $days 天',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: constraints.maxWidth * understanding,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return GestureDetector(
      onTap: () {
        context.go('/settings');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(
              Icons.settings_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            const Text(
              '设置',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class LifeItem {
  final String title;
  final String subtitle;
  final IconData icon;

  LifeItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
