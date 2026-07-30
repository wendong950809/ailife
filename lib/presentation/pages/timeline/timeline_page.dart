import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/timeline_event.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<TimelineEvent> _events = [];
  bool _isLoading = true;
  bool _hasMore = true;
  final int _pageSize = 30;
  DateTime? _lastDate;
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isLoading) {
        _loadMore();
      }
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _events = [];
      _lastDate = null;
    });
    await _fetchEvents();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    setState(() => _isLoading = true);
    await _fetchEvents(isMore: true);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchEvents({bool isMore = false}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      dynamic query = _supabase
          .from('timeline')
          .select()
          .eq('user_id', userId)
          .order('occurred_at', ascending: false, nullsFirst: false)
          .limit(_pageSize);

      if (_searchQuery.isNotEmpty) {
        query = query.or('title.ilike.%$_searchQuery%,summary.ilike.%$_searchQuery%');
      }

      if (isMore && _lastDate != null) {
        query = query.lt('occurred_at', _lastDate!.toIso8601String());
      }

      final response = await query;

      if (response is List) {
        final newEvents = response
            .map((e) => TimelineEvent.fromMap(e as Map<String, dynamic>))
            .toList();

        if (newEvents.length < _pageSize) {
          _hasMore = false;
        }

        if (newEvents.isNotEmpty) {
          _lastDate = newEvents.last.occurredAt;
        }

        if (mounted) {
          setState(() {
            if (isMore) {
              _events.addAll(newEvents);
            } else {
              _events = newEvents;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('加载时间线失败: $e');
    }
  }

  /// 按日期分组事件
  Map<String, List<TimelineEvent>> get _groupedEvents {
    final groups = <String, List<TimelineEvent>>{};
    for (final event in _events) {
      final key = _groupKey(event);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(event);
    }
    return groups;
  }

  String _groupKey(TimelineEvent event) {
    final date = event.occurredAt ?? DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final eventDate = DateTime(date.year, date.month, date.day);

    if (eventDate == today) return '今天';
    if (eventDate == yesterday) return '昨天';
    if (date.year == now.year) {
      return DateFormat('M月d日 EEEE', 'zh_CN').format(date);
    }
    return DateFormat('yyyy年M月d日', 'zh_CN').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: _isLoading && _events.isEmpty
                  ? _buildSkeletonLoading()
                  : _events.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadEvents,
                          color: AppColors.primary,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: _groupedEvents.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _groupedEvents.length) {
                                return _buildLoadingMore();
                              }
                              final keys = _groupedEvents.keys.toList();
                              final key = keys[index];
                              final events = _groupedEvents[key]!;
                              return _buildDateGroup(key, events, index == 0);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const Text(
            '我的时间线',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          if (_events.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_events.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: _loadEvents,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: const Icon(
                Icons.refresh,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                onSubmitted: (_) => _loadEvents(),
                decoration: const InputDecoration(
                  hintText: '搜索时间线...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                ),
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _searchQuery = '';
                    _loadEvents();
                  });
                },
                child: const Icon(Icons.clear, size: 16, color: AppColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  /// 日期分组
  Widget _buildDateGroup(String title, List<TimelineEvent> events, bool isFirst) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期标题
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${events.length}条',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // 事件列表
          ...events.asMap().entries.map((entry) {
            return _buildEventCard(entry.value);
          }),
        ],
      ),
    );
  }

  /// 事件卡片
  Widget _buildEventCard(TimelineEvent event) {
    return GestureDetector(
      onTap: () => _showEventDetail(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  event.icon ?? '📝',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 摘要
                  Text(
                    event.summary,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // 底部信息
                  Row(
                    children: [
                      if (event.occurredAt != null)
                        Text(
                          _formatTime(event.occurredAt!, event.timePrecision),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      const SizedBox(width: 8),
                      _buildSourceChip(event.eventSource),
                      const Spacer(),
                      _buildPrecisionBadge(event.timePrecision),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChip(EventSource source) {
    final sourceMap = {
      EventSource.chat: {'icon': Icons.chat_bubble_outline, 'label': '聊天'},
      EventSource.photo: {'icon': Icons.photo_outlined, 'label': '照片'},
      EventSource.voice: {'icon': Icons.mic_none, 'label': '语音'},
      EventSource.calendar: {'icon': Icons.event_outlined, 'label': '日历'},
      EventSource.document: {'icon': Icons.description_outlined, 'label': '文档'},
      EventSource.health: {'icon': Icons.favorite_border, 'label': '健康'},
    };
    final info = sourceMap[source]!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(info['icon'] as IconData, size: 11, color: AppColors.textTertiary),
        const SizedBox(width: 3),
        Text(
          info['label'] as String,
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildPrecisionBadge(TimePrecision precision) {
    final badgeMap = {
      TimePrecision.day: {'color': AppColors.stateSuccess, 'label': '精确'},
      TimePrecision.week: {'color': AppColors.primary, 'label': '周'},
      TimePrecision.month: {'color': Colors.orange, 'label': '月'},
      TimePrecision.year: {'color': Colors.purple, 'label': '年'},
      TimePrecision.unknown: {'color': AppColors.textTertiary, 'label': '模糊'},
    };
    final info = badgeMap[precision]!;
    final color = info['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        info['label'] as String,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }

  String _formatTime(DateTime date, TimePrecision precision) {
    switch (precision) {
      case TimePrecision.day:
        return DateFormat('HH:mm', 'zh_CN').format(date);
      case TimePrecision.week:
        return DateFormat('M月d日', 'zh_CN').format(date);
      case TimePrecision.month:
        return DateFormat('M月d日', 'zh_CN').format(date);
      case TimePrecision.year:
        return DateFormat('M月', 'zh_CN').format(date);
      case TimePrecision.unknown:
        return '';
    }
  }

  /// 事件详情弹窗
  void _showEventDetail(TimelineEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              event.icon ?? '📝',
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (event.occurredAt != null)
                                Text(
                                  DateFormat('yyyy年M月d日 HH:mm', 'zh_CN')
                                      .format(event.occurredAt!),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        event.summary,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.7,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildDetailItem('来源', _sourceLabel(event.eventSource)),
                        const SizedBox(width: 32),
                        _buildDetailItem('时间精度', _precisionLabel(event.timePrecision)),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textTertiary, size: 22),
                  onPressed: () => Navigator.pop(context),
                  padding: const EdgeInsets.all(8),
                  splashRadius: 20,
                ),
              ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(EventSource source) {
    switch (source) {
      case EventSource.chat: return '聊天';
      case EventSource.photo: return '照片';
      case EventSource.voice: return '语音';
      case EventSource.calendar: return '日历';
      case EventSource.document: return '文档';
      case EventSource.health: return '健康';
    }
  }

  String _precisionLabel(TimePrecision precision) {
    switch (precision) {
      case TimePrecision.day: return '精确到天';
      case TimePrecision.week: return '精确到周';
      case TimePrecision.month: return '精确到月';
      case TimePrecision.year: return '精确到年';
      case TimePrecision.unknown: return '时间模糊';
    }
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 骨架屏加载
  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.bgTertiary,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.bgTertiary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 200,
                    decoration: BoxDecoration(
                      color: AppColors.bgTertiary,
                      borderRadius: BorderRadius.circular(4),
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

  Widget _buildLoadingMore() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
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
            Icons.timeline,
            size: 56,
            color: AppColors.textTertiary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            '还没有时间线记录',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '去聊天页面发条消息，\n你的生活就会自动记录在这里',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textTertiary.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
