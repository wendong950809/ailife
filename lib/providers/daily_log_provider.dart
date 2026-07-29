import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/daily_log.dart';

class DailyLogProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  DailyLog? _todayLog;
  bool _isLoading = false;
  String? _errorMessage;

  DailyLog? get todayLog => _todayLog;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTodayLog() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final response = await _supabase
          .from('daily_logs')
          .select()
          .eq('user_id', user.id)
          .eq('log_date', today)
          .maybeSingle();

      if (response != null) {
        _todayLog = DailyLog.fromMap(response);
      } else {
        _todayLog = null;
      }
    } catch (e) {
      _errorMessage = '加载今日日志失败';
      debugPrint('加载今日日志失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateMood(int mood) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final today = DateTime.now().toIso8601String().split('T').first;

      if (_todayLog == null) {
        final response = await _supabase
            .from('daily_logs')
            .insert({
              'user_id': user.id,
              'log_date': today,
              'mood': mood,
            })
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      } else {
        final response = await _supabase
            .from('daily_logs')
            .update({'mood': mood})
            .eq('id', _todayLog!.id)
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      }
      return true;
    } catch (e) {
      _errorMessage = '更新心情失败';
      debugPrint('更新心情失败: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addHighlight(String highlight) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      List<String> newHighlights = _todayLog?.highlights ?? [];
      newHighlights.add(highlight);

      if (_todayLog == null) {
        final response = await _supabase
            .from('daily_logs')
            .insert({
              'user_id': user.id,
              'log_date': today,
              'highlights': newHighlights,
            })
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      } else {
        final response = await _supabase
            .from('daily_logs')
            .update({'highlights': newHighlights})
            .eq('id', _todayLog!.id)
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      }
      return true;
    } catch (e) {
      _errorMessage = '添加亮点失败';
      debugPrint('添加亮点失败: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateNotes(String notes) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final today = DateTime.now().toIso8601String().split('T').first;

      if (_todayLog == null) {
        final response = await _supabase
            .from('daily_logs')
            .insert({
              'user_id': user.id,
              'log_date': today,
              'notes': notes,
            })
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      } else {
        final response = await _supabase
            .from('daily_logs')
            .update({'notes': notes})
            .eq('id', _todayLog!.id)
            .select()
            .single();
        _todayLog = DailyLog.fromMap(response);
      }
      return true;
    } catch (e) {
      _errorMessage = '更新笔记失败';
      debugPrint('更新笔记失败: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
