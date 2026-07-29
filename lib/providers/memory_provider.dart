import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/memory.dart';

class MemoryProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Memory> _memories = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Memory> get memories => _memories;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMemories() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase
          .from('memories')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      _memories = (response as List)
          .map((item) => Memory.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _errorMessage = '加载记忆失败';
      debugPrint('加载记忆失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addMemory({
    required String title,
    required String content,
    String category = 'general',
    List<String> tags = const [],
    int importance = 5,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase
          .from('memories')
          .insert({
            'user_id': user.id,
            'title': title,
            'content': content,
            'category': category,
            'tags': tags,
            'importance': importance,
          })
          .select()
          .single();

      final memory = Memory.fromMap(response);
      _memories.insert(0, memory);
      return true;
    } catch (e) {
      _errorMessage = '添加记忆失败';
      debugPrint('添加记忆失败: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteMemory(String id) async {
    try {
      await _supabase.from('memories').delete().eq('id', id);
      _memories.removeWhere((m) => m.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '删除记忆失败';
      debugPrint('删除记忆失败: $e');
      return false;
    }
  }
}
