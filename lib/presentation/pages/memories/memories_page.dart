import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/memory.dart';
import '../../../data/services/stats_service.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final StatsService _statsService = StatsService();

  int _selectedFilter = 0;
  final List<String> _filters = ['全部', '工作', '家庭', '重要'];
  List<Memory> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    try {
      final memories = await _statsService.getMemories(limit: 50);
      if (mounted) {
        setState(() {
          _memories = memories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Memory> get _filteredMemories {
    if (_selectedFilter == 0) return _memories;
    final filter = _filters[_selectedFilter];
    return _memories.where((m) {
      if (filter == '工作') return m.category == 'work';
      if (filter == '家庭') return m.category == 'family';
      if (filter == '重要') return m.importance >= 8;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStr = DateFormat('yyyy年 / M月', 'zh_CN').format(now);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(monthStr),
            _buildFilterTabs(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _filteredMemories.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadMemories,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                            itemCount: _filteredMemories.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildTimelineCard(_filteredMemories[index]),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String monthStr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          const Text(
            '我的人生',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.chevron_left,
            size: 16,
            color: AppColors.textTertiary,
          ),
          Text(
            monthStr,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: List.generate(_filters.length, (index) {
            final isSelected = _selectedFilter == index;
            return Padding(
              padding: EdgeInsets.only(right: index == _filters.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = index;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    _filters[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: AppColors.textTertiary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有记忆记录',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '跟知伴聊聊天，你的人生故事都会被记录',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(Memory memory) {
    final dateStr = memory.createdAt != null
        ? DateFormat('M月d日', 'zh_CN').format(memory.createdAt!)
        : '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            memory.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            memory.content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildCategoryTag(_getCategoryLabel(memory.category)),
              if (memory.tags.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...memory.tags.take(2).map(
                  (tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildTag(tag),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'work':
        return '工作';
      case 'family':
        return '家庭';
      case 'health':
        return '健康';
      case 'growth':
        return '成长';
      case 'travel':
        return '旅行';
      default:
        return '生活';
    }
  }

  Widget _buildCategoryTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
