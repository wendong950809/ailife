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

  TimePrecision _zoomLevel = TimePrecision.day;
  EventSource? _sourceFilter;
  String _searchQuery = '';
  List<TimelineEvent> _events = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _pageSize = 20;
  DateTime? _lastDate;

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
          .order('occurred_at', ascending: false)
          .limit(_pageSize);

      if (_sourceFilter != null) {
        query = query.eq('event_source', _sourceFilter!.name);
      }

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

  void _zoomIn() {
    final levels = TimePrecision.values;
    final currentIndex = levels.indexOf(_zoomLevel);
    if (currentIndex > 0) {
      setState(() => _zoomLevel = levels[currentIndex - 1]);
    }
  }

  void _zoomOut() {
    final levels = TimePrecision.values;
    final currentIndex = levels.indexOf(_zoomLevel);
    if (currentIndex < levels.length - 2) {
      setState(() => _zoomLevel = levels[currentIndex + 1]);
    }
  }

  String get _zoomLabel {
    switch (_zoomLevel) {
      case TimePrecision.day:
        return '按天';
      case TimePrecision.week:
        return '按周';
      case TimePrecision.month:
        return '按月';
      case TimePrecision.year:
        return '按年';
      case TimePrecision.unknown:
        return '全部';
    }
  }

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
    switch (_zoomLevel) {
      case TimePrecision.day:
        return DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(date);
      case TimePrecision.week:
        final weekStart = date.subtract(Duration(days: date.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${DateFormat('M月d日', 'zh_CN').format(weekStart)} - ${DateFormat('M月d日', 'zh_CN').format(weekEnd)}';
      case TimePrecision.month:
        return DateFormat('yyyy年M月', 'zh_CN').format(date);
      case TimePrecision.year:
        return DateFormat('yyyy年', 'zh_CN').format(date);
      case TimePrecision.unknown:
        return '全部时间';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildZoomBar(),
            _buildSearchBar(),
            Expanded(
              child: _isLoading && _events.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _events.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadEvents,
                          color: AppColors.primary,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                            itemCount: _groupedEvents.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _groupedEvents.length) {
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
                              final keys = _groupedEvents.keys.toList();
                              final key = keys[index];
                              final events = _groupedEvents[key]!;
                              return _buildTimelineGroup(key, events, index == 0);
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
        children: const [
          Text(
            '我的时间线',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _zoomIn,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Icon(
                      Icons.zoom_in,
                      size: 18,
                      color: _zoomLevel == TimePrecision.day
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 16,
                  color: AppColors.borderLight,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _zoomLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 16,
                  color: AppColors.borderLight,
                ),
                GestureDetector(
                  onTap: _zoomOut,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Icon(
                      Icons.zoom_out,
                      size: 18,
                      color: _zoomLevel == TimePrecision.year
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _buildSourceFilter(),
        ],
      ),
    );
  }

  Widget _buildSourceFilter() {
    return PopupMenuButton<EventSource?>(
      onSelected: (source) {
        setState(() {
          _sourceFilter = source;
          _loadEvents();
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem<EventSource?>(
          value: null,
          child: Text('全部来源'),
        ),
        ...EventSource.values.map((s) => PopupMenuItem<EventSource?>(
              value: s,
              child: Text(_sourceLabel(s)),
            )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              _sourceFilter == null ? '筛选' : _sourceLabel(_sourceFilter!),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(EventSource source) {
    switch (source) {
      case EventSource.chat:
        return '聊天';
      case EventSource.photo:
        return '照片';
      case EventSource.voice:
        return '语音';
      case EventSource.calendar:
        return '日历';
      case EventSource.document:
        return '文档';
      case EventSource.health:
        return '健康';
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                onSubmitted: (_) => _loadEvents(),
                decoration: const InputDecoration(
                  hintText: '搜索时间线事件...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
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
                child: Icon(
                  Icons.clear,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineGroup(String title, List<TimelineEvent> events, bool isFirst) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupHeader(title, events.length),
          const SizedBox(height: 12),
          ...events.asMap().entries.map((entry) {
            final index = entry.key;
            final event = entry.value;
            final isLast = index == events.length - 1;
            return _buildTimelineItem(event, isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title, int count) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(TimelineEvent event, bool isLast) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatDate(event.occurredAt),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (event.occurredAt != null && event.timePrecision != TimePrecision.month && event.timePrecision != TimePrecision.year)
                        Text(
                          _formatHour(event.occurredAt!),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (!isLast)
                  const SizedBox(height: 4),
                if (!isLast)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 2,
                          margin: const EdgeInsets.only(right: 13),
                          decoration: const BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(2)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 3,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => _showEventDetail(event),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              event.icon ?? '📝',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        _buildPrecisionBadge(event.timePrecision),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      event.summary,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSourceChip(event.eventSource),
                        const Spacer(),
                        if (event.occurredAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _precisionLabel(event.timePrecision),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrecisionBadge(TimePrecision precision) {
    Color color;
    String label;
    switch (precision) {
      case TimePrecision.day:
        color = AppColors.stateSuccess;
        label = '精确';
        break;
      case TimePrecision.week:
        color = AppColors.primary;
        label = '周';
        break;
      case TimePrecision.month:
        color = Colors.orange;
        label = '月';
        break;
      case TimePrecision.year:
        color = Colors.purple;
        label = '年';
        break;
      case TimePrecision.unknown:
        color = AppColors.textTertiary;
        label = '模糊';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSourceChip(EventSource source) {
    IconData icon;
    String label;
    switch (source) {
      case EventSource.chat:
        icon = Icons.chat_bubble_outline;
        label = '聊天';
        break;
      case EventSource.photo:
        icon = Icons.photo_outlined;
        label = '照片';
        break;
      case EventSource.voice:
        icon = Icons.mic_none;
        label = '语音';
        break;
      case EventSource.calendar:
        icon = Icons.event_outlined;
        label = '日历';
        break;
      case EventSource.document:
        icon = Icons.description_outlined;
        label = '文档';
        break;
      case EventSource.health:
        icon = Icons.favorite_border;
        label = '健康';
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
      ],
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

  String _formatDate(DateTime? date) {
    if (date == null) return '未知时间';
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    if (diff < 7) return '${7 - diff}天前';
    
    if (date.year == now.year) {
      return DateFormat('M月d日', 'zh_CN').format(date);
    }
    return DateFormat('yyyy年M月d日', 'zh_CN').format(date);
  }

  String _formatHour(DateTime date) {
    return DateFormat('HH:mm', 'zh_CN').format(date);
  }

  void _showEventDetail(TimelineEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              event.icon ?? '📝',
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (event.occurredAt != null)
                                Text(
                                  DateFormat('yyyy年M月d日 HH:mm', 'zh_CN')
                                      .format(event.occurredAt!),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 24),
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
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textTertiary,
                    size: 24,
                  ),
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
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(3),
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

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
          ),
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

  String _precisionLabel(TimePrecision precision) {
    switch (precision) {
      case TimePrecision.day:
        return '精确到天';
      case TimePrecision.week:
        return '精确到周';
      case TimePrecision.month:
        return '精确到月';
      case TimePrecision.year:
        return '精确到年';
      case TimePrecision.unknown:
        return '时间模糊';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timeline,
            size: 48,
            color: Color(0xFFCCCCCC),
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有时间线记录',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '聊聊天，你的生活就会被记录在这里',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
