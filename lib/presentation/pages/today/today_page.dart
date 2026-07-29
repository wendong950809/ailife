import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/stats_service.dart';
import '../../../providers/auth_provider.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final StatsService _statsService = StatsService();

  Map<String, int> _dailyBriefing = {'goals': 0, 'events': 0, 'reminders': 0};
  Map<String, dynamic> _lifeScore = {
    'total': 0,
    'work': 0.0,
    'family': 0.0,
    'growth': 0.0,
    'health': 0.0,
  };
  List<Map<String, dynamic>> _todayFocus = [];
  String _aiInsight = '';
  String _userName = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    _userName = auth.profile?.username ??
        auth.user?.email?.split('@').first ??
        '朋友';

    try {
      final results = await Future.wait([
        _statsService.getDailyBriefing(),
        _statsService.getLifeScore(),
        _statsService.getTodayFocus(),
        _statsService.getAiInsight(),
      ]);

      if (mounted) {
        setState(() {
          _dailyBriefing = results[0] as Map<String, int>;
          _lifeScore = results[1] as Map<String, dynamic>;
          _todayFocus = results[2] as List<Map<String, dynamic>>;
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
    final now = DateTime.now();
    final greeting = _getGreeting(now);
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(now);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 96),
              children: [
                _buildHeader(greeting, dateStr),
                const SizedBox(height: 24),
                _buildDailyBriefing(),
                const SizedBox(height: 12),
                _buildLifeScore(),
                const SizedBox(height: 12),
                _buildTodayFocus(),
                const SizedBox(height: 12),
                _buildTodayDiscovery(),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 80,
            child: _buildQuickRecordFab(),
          ),
        ],
      ),
    );
  }

  String _getGreeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return '早上好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  Widget _buildHeader(String greeting, String dateStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting，$_userName',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dateStr,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '有什么想跟我聊的？',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyBriefing() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          top: BorderSide(color: AppColors.borderLight),
          right: BorderSide(color: AppColors.borderLight),
          bottom: BorderSide(color: AppColors.borderLight),
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.message_outlined,
                  size: 12,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '每日简报',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildBriefingStat('${_dailyBriefing['goals']}', '待办'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBriefingStat('${_dailyBriefing['events']}', '日程'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBriefingStat('${_dailyBriefing['reminders']}', '提醒'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _aiInsight.isEmpty ? '多跟我聊聊你的生活吧，我会帮你记录和分析每一天。' : _aiInsight,
            style: const TextStyle(
              fontSize: 12,
              height: 1.65,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBriefingStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifeScore() {
    final workScore = (_lifeScore['work'] as num?)?.toDouble() ?? 0.0;
    final familyScore = (_lifeScore['family'] as num?)?.toDouble() ?? 0.0;
    final growthScore = (_lifeScore['growth'] as num?)?.toDouble() ?? 0.0;
    final healthScore = (_lifeScore['health'] as num?)?.toDouble() ?? 0.0;

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
          const Text(
            '综合人生状态',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_lifeScore['total']}',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              _buildScoreBar('事业', workScore, AppColors.primary),
              const SizedBox(height: 10),
              _buildScoreBar('家庭', familyScore, AppColors.primary),
              const SizedBox(height: 10),
              _buildScoreBar('成长', growthScore, AppColors.primary),
              const SizedBox(height: 10),
              _buildScoreBar('健康', healthScore, AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar(String label, double progress, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
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
                    width: constraints.maxWidth * progress,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 32,
          child: Text(
            '${(progress * 100).toInt()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayFocus() {
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
          const Text(
            '今日重点',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (_todayFocus.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '暂无今日重点，跟知伴聊聊天，你的事情我会帮你记录。',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            Column(
              children: _todayFocus.asMap().entries.map((entry) {
                final item = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: entry.key == _todayFocus.length - 1 ? 0 : 12),
                  child: _buildTodoItem(
                    title: item['title'] as String? ?? '',
                    category: _getCategoryLabel(item['category'] as String?),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _getCategoryLabel(String? type) {
    switch (type) {
      case 'goal':
        return '目标';
      case 'event':
        return '事件';
      case 'work':
        return '工作';
      default:
        return '其他';
    }
  }

  Widget _buildTodoItem({required String title, required String category}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.border,
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            category,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayDiscovery() {
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
            children: const [
              Icon(
                Icons.info_outline,
                size: 14,
                color: AppColors.primary,
              ),
              SizedBox(width: 6),
              Text(
                '今日发现',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isLoading
                ? '正在分析中...'
                : (_aiInsight.isEmpty
                    ? '多跟我聊聊，我会帮你发现你的成长轨迹和潜在风险。'
                    : _aiInsight),
            style: const TextStyle(
              fontSize: 12,
              height: 1.65,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickRecordFab() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音记录功能开发中')),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.mic_none,
          size: 20,
          color: Colors.white,
        ),
      ),
    );
  }
}
