import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/timeline_event.dart';

// ============================================
// 页面名称配置（可在此统一修改）
// ============================================
// 备选：记忆长廊 | 时光印记 | 我的足迹 | 岁月笔记 | 人生编年史 | 心境录
const String _kPageTitle = '记忆长廊';
const String _kSearchHint = '搜索记忆...';
const String _kEmptyTitle = '这里还是一片空白';
const String _kEmptySubtitle = '去聊聊天，\n生活的点滴会自动流淌到这里';

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
  DateTime? _lastDate; // 用于加载更早的事件
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载事件：倒序查询，内存反转（顶部旧、底部新）
  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _events = [];
      _lastDate = null;
    });

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      dynamic query = _supabase
          .from('timeline')
          .select()
          .eq('user_id', userId)
          .order('occurred_at', ascending: false)
          .limit(_pageSize);

      if (_searchQuery.isNotEmpty) {
        query = query.or('title.ilike.%$_searchQuery%,summary.ilike.%$_searchQuery%');
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
            // 反转：顶部旧，底部新
            _events = newEvents.reversed.toList();
          });
          // 自动滚动到底部（最新事件）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(animate: true);
          });
        }
      }
    } catch (e) {
      debugPrint('加载记忆失败: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// 向上滑动加载更早的事件（插入列表头部）
  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading || _events.isEmpty) return;

    setState(() => _isLoading = true);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 当前列表中最早的事件
      final earliestDate = _events.first.occurredAt;
      if (earliestDate == null) {
        setState(() => _isLoading = false);
        return;
      }

      dynamic query = _supabase
          .from('timeline')
          .select()
          .eq('user_id', userId)
          .lt('occurred_at', earliestDate.toIso8601String())
          .order('occurred_at', ascending: false)
          .limit(_pageSize);

      if (_searchQuery.isNotEmpty) {
        query = query.or('title.ilike.%$_searchQuery%,summary.ilike.%$_searchQuery%');
      }

      final response = await query;

      if (response is List) {
        final olderEvents = response
            .map((e) => TimelineEvent.fromMap(e as Map<String, dynamic>))
            .toList();

        if (olderEvents.length < _pageSize) {
          _hasMore = false;
        }

        if (mounted) {
          setState(() {
            // 反转后插入头部
            _events.insertAll(0, olderEvents.reversed.toList());
          });
        }
      }
    } catch (e) {
      debugPrint('加载更多记忆失败: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(max);
    }
  }

  /// 删除事件
  Future<void> _deleteEvent(TimelineEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text('确定要删除「${event.title}」这条记忆吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.from('timeline').delete().eq('id', event.id!);
      if (mounted) {
        setState(() => _events.removeWhere((e) => e.id == event.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('删除失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请重试')),
        );
      }
    }
  }

  /// 编辑事件
  Future<void> _editEvent(TimelineEvent event) async {
    final titleController = TextEditingController(text: event.title);
    final summaryController = TextEditingController(text: event.summary);
    DateTime? pickedDate = event.occurredAt;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽指示条
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('编辑记忆', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                  )),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: _inputDecoration('标题'),
                    style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: summaryController,
                    decoration: _inputDecoration('摘要').copyWith(
                      alignLabelWithHint: true,
                    ),
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    maxLines: 4,
                    minLines: 2,
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: pickedDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: AppColors.primary,
                              onPrimary: Colors.white,
                              surface: AppColors.surface,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (date != null) {
                        setModalState(() => pickedDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: AppColors.textTertiary),
                          const SizedBox(width: 8),
                          Text(
                            pickedDate != null
                                ? DateFormat('yyyy年M月d日', 'zh_CN').format(pickedDate!)
                                : '选择日期',
                            style: TextStyle(
                              fontSize: 14,
                              color: pickedDate != null ? AppColors.textPrimary : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await _supabase.from('timeline').update({
                            'title': titleController.text.trim(),
                            'summary': summaryController.text.trim(),
                            'occurred_at': pickedDate?.toIso8601String(),
                          }).eq('id', event.id!);
                          if (mounted) {
                            final idx = _events.indexWhere((e) => e.id == event.id);
                            if (idx != -1) {
                              setState(() {
                                _events[idx] = event.copyWith(
                                  title: titleController.text.trim(),
                                  summary: summaryController.text.trim(),
                                  occurredAt: pickedDate,
                                );
                                // 重新按时间排序
                                _events.sort((a, b) {
                                  final da = a.occurredAt ?? DateTime(1900);
                                  final db = b.occurredAt ?? DateTime(1900);
                                  return da.compareTo(db);
                                });
                              });
                            }
                            Navigator.pop(context, true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
                            );
                          }
                        } catch (e) {
                          debugPrint('保存失败: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('保存失败')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  /// 按日期分组（正序排列后，分组也按正序）
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
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollUpdateNotification) {
                              if (notification.metrics.pixels <= 100 &&
                                  !_isLoading &&
                                  _hasMore) {
                                _loadMore();
                              }
                            }
                            return false;
                          },
                          child: RefreshIndicator(
                            onRefresh: _loadEvents,
                            color: AppColors.primary,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(0, 0, 16, 96),
                              itemCount: _groupedEvents.length + 1, // +1 for "正在记录"
                              itemBuilder: (context, index) {
                                if (index == _groupedEvents.length) {
                                  return _buildRecordingFooter();
                                }
                                final keys = _groupedEvents.keys.toList();
                                final key = keys[index];
                                final events = _groupedEvents[key]!;
                                return _buildDateGroup(key, events, index == 0, index == _groupedEvents.length - 1);
                              },
                            ),
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
          Text(
            _kPageTitle,
            style: const TextStyle(
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
                onChanged: (value) => setState(() => _searchQuery = value),
                onSubmitted: (_) => _loadEvents(),
                decoration: InputDecoration(
                  hintText: _kSearchHint,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
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

  /// 日期分组 + 连贯时间轴
  Widget _buildDateGroup(String title, List<TimelineEvent> events, bool isFirst, bool isLast) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期标题
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 10),
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
          // 事件列表（带时间轴）
          ...events.asMap().entries.map((entry) {
            final isLastInGroup = entry.key == events.length - 1;
            return _buildEventCardWithTimeline(entry.value, isLastInGroup && isLast);
          }),
        ],
      ),
    );
  }

  /// 带时间轴的事件卡片
  Widget _buildEventCardWithTimeline(TimelineEvent event, bool isLastEvent) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间轴
          SizedBox(
            width: 44,
            child: Column(
              children: [
                // 节点圆点
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 18),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                // 向下延伸的竖线
                if (!isLastEvent)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primary.withOpacity(0.3),
                            AppColors.primary.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 右侧卡片
          Expanded(
            child: _buildEventCard(event),
          ),
        ],
      ),
    );
  }

  /// 事件卡片
  Widget _buildEventCard(TimelineEvent event) {
    return GestureDetector(
      onTap: () => _showEventDetail(event),
      onLongPress: () => _showActionMenu(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                // 标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 2),
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
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
    );
  }

  /// 长按操作菜单
  void _showActionMenu(TimelineEvent event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 22),
                title: const Text('编辑', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _editEvent(event);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                title: const Text('删除', style: TextStyle(fontSize: 15, color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteEvent(event);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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
      case TimePrecision.month:
        return DateFormat('M月d日', 'zh_CN').format(date);
      case TimePrecision.year:
        return DateFormat('M月', 'zh_CN').format(date);
      case TimePrecision.unknown:
        return '';
    }
  }

  /// 底部"正在记录..."
  Widget _buildRecordingFooter() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 18),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withOpacity(0.1),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10, right: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  _buildPulsingDot(),
                  const SizedBox(width: 10),
                  Text(
                    '正在记录生活的点滴...',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.3 + value * 0.4),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2 * (1 - value)),
                blurRadius: 6 * value,
                spreadRadius: 2 * value,
              ),
            ],
          ),
        );
      },
      onEnd: () {
        if (mounted) setState(() {}); // 重新触发动画
      },
    );
  }

  /// 事件详情弹窗（优化版）
  void _showEventDetail(TimelineEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {}, // 阻止冒泡
            child: DraggableScrollableSheet(
              initialChildSize: 0.55,
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
                      padding: const EdgeInsets.fromLTRB(20, 44, 20, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                    // 顶部拖拽条
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
                    // 关闭按钮
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 底部操作栏
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _editEvent(event);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                                label: const Text('编辑', style: TextStyle(color: AppColors.primary)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteEvent(event);
                                },
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                label: const Text('删除', style: TextStyle(color: Colors.red)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red.withOpacity(0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 骨架屏加载
  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(44, 0, 16, 96),
      itemCount: 5,
      itemBuilder: (context, index) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.only(top: 18),
                    decoration: BoxDecoration(
                      color: AppColors.bgTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (index < 4)
                    Expanded(
                      child: Container(
                        width: 2, margin: const EdgeInsets.only(top: 4),
                        color: AppColors.bgTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10, right: 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
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
                          Container(height: 14, width: double.infinity,
                            decoration: BoxDecoration(color: AppColors.bgTertiary, borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(height: 8),
                          Container(height: 12, width: 150,
                            decoration: BoxDecoration(color: AppColors.bgTertiary, borderRadius: BorderRadius.circular(4)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            Icons.auto_stories_outlined,
            size: 56,
            color: AppColors.textTertiary.withOpacity(0.35),
          ),
          const SizedBox(height: 16),
          Text(
            _kEmptyTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _kEmptySubtitle,
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
