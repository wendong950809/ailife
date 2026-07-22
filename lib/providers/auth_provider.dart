import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/user_profile.dart';
import '../data/services/logging_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final LoggingService _loggingService;

  User? _user;
  UserProfile? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _loggingService = LoggingService(supabase: _supabase);
    _user = _supabase.auth.currentUser;
    if (_user != null) {
      _loadProfile();
    }
    _supabase.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      if (_user != null) {
        _loadProfile();
        _loggingService.logSystemStartup(userId: _user!.id);
      } else {
        _profile = null;
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile() async {
    if (_user == null) return;
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', _user!.id)
          .single();
      _profile = UserProfile.fromMap(response);
    } catch (e) {
      debugPrint('加载用户资料失败: $e');
    }
  }

  String _translateAuthError(String error) {
    if (error.contains('Invalid login credentials') || error.contains('email or password')) {
      return '邮箱或密码错误';
    }
    if (error.contains('User not found')) {
      return '用户不存在，请先注册';
    }
    if (error.contains('Email not confirmed')) {
      return '邮箱尚未验证，请检查邮件';
    }
    if (error.contains('Password should be at least')) {
      return '密码长度不够';
    }
    if (error.contains('Email already registered')) {
      return '该邮箱已被注册';
    }
    if (error.contains('Rate limit exceeded')) {
      return '请求过于频繁，请稍后重试';
    }
    return error;
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _isLoading = false;
      if (response.session?.user != null) {
        await _loggingService.logAuthLogin(
          userId: response.session!.user.id,
          email: email,
          success: true,
        );
      }
      return true;
    } on AuthException catch (e) {
      _errorMessage = _translateAuthError(e.message);
      _isLoading = false;
      notifyListeners();
      await _loggingService.logAuthLogin(
        userId: '',
        email: email,
        success: false,
        error: e.message,
      );
      return false;
    } catch (e) {
      _errorMessage = '登录失败，请稍后重试';
      _isLoading = false;
      notifyListeners();
      await _loggingService.logAuthLogin(
        userId: '',
        email: email,
        success: false,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: username != null ? {'username': username} : null,
      );
      _isLoading = false;
      notifyListeners();
      if (response.user != null) {
        await _loggingService.logAuthRegister(
          userId: response.user!.id,
          email: email,
          success: true,
        );
      }
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      await _loggingService.logAuthRegister(
        userId: '',
        email: email,
        success: false,
        error: e.message,
      );
      return false;
    } catch (e) {
      _errorMessage = '注册失败，请稍后重试';
      _isLoading = false;
      notifyListeners();
      await _loggingService.logAuthRegister(
        userId: '',
        email: email,
        success: false,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> signOut() async {
    final userId = _user?.id ?? '';
    await _supabase.auth.signOut();
    if (userId.isNotEmpty) {
      await _loggingService.logAuthLogout(userId: userId);
    }
    _user = null;
    _profile = null;
    notifyListeners();
  }

  Future<void> updateProfile({
    String? username,
    String? bio,
    String? avatarUrl,
    DateTime? birthday,
  }) async {
    if (_user == null) return;

    final data = <String, dynamic>{};
    if (username != null) data['username'] = username;
    if (bio != null) data['bio'] = bio;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (birthday != null) data['birthday'] = birthday.toIso8601String().split('T')[0];

    if (data.isEmpty) return;

    try {
      await _supabase
          .from('profiles')
          .update(data)
          .eq('id', _user!.id);

      if (username != null && _profile != null) {
        _profile = _profile!.copyWith(username: username);
      }
      if (bio != null && _profile != null) {
        _profile = _profile!.copyWith(bio: bio);
      }
      if (avatarUrl != null && _profile != null) {
        _profile = _profile!.copyWith(avatarUrl: avatarUrl);
      }
      if (birthday != null && _profile != null) {
        _profile = _profile!.copyWith(birthday: birthday);
      }

      await _loggingService.logProfileUpdate(
        userId: _user!.id,
        changes: data,
        success: true,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('更新用户资料失败: $e');
      await _loggingService.logProfileUpdate(
        userId: _user!.id,
        changes: data,
        success: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
