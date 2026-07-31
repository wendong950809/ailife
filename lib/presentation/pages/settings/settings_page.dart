import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/services/ai_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ai_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _chatStyles = ['自然', '简洁', '温柔', '幽默', '理性', '活泼'];
  bool _settingsLoaded = false;

  /// 加载保存的 AI 设置（从 AiProvider 统一加载）
  Future<void> _loadSettingsIfNeeded() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await context.read<AiProvider>().loadSettings();
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> _uploadAvatar() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 75,
      );
      if (image == null) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last.toLowerCase();
      final base64Image = 'data:image/$fileExt;base64,${base64Encode(bytes)}';

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': base64Image})
          .eq('id', user.id);

      if (mounted) {
        context.read<AuthProvider>().updateProfile(avatarUrl: base64Image);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('头像更新成功'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      debugPrint('头像上传失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), duration: Duration(seconds: 3)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profile = auth.profile;
    _loadSettingsIfNeeded();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 48, 0, 0),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildProfileSection(profile),
          const SizedBox(height: 16),
          _buildAiPreferencesSection(),
          const SizedBox(height: 16),
          _buildDataPrivacySection(),
          const SizedBox(height: 24),
          _buildLogoutButton(auth),
          const SizedBox(height: 16),
          Center(
            child: Consumer<AiProvider>(
              builder: (context, aiProvider, _) => Text(
                '${aiProvider.aiName} v0.4.4',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              context.go('/');
            },
            child: const Icon(
              Icons.chevron_left,
              size: 24,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            '设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(UserProfile? profile) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          _buildSettingRow(
            title: '头像',
            trailing: _buildAvatar(profile),
            onTap: _uploadAvatar,
          ),
          _buildDivider(),
          _buildSettingRow(
            title: '昵称',
            subtitle: profile?.username ?? '未设置',
            onTap: () => _showEditDialog(
              title: '修改昵称',
              initialValue: profile?.username ?? '',
              onSave: (value) async {
                await context.read<AuthProvider>().updateProfile(
                  username: value,
                );
              },
            ),
          ),
          _buildDivider(),
          _buildSettingRow(
            title: '生日（阳历）',
            subtitle: profile?.birthday != null
                ? '${profile!.birthday!.year}年${profile.birthday!.month}月${profile.birthday!.day}日'
                : '未设置（可在聊天中告诉AI）',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: profile?.birthday ?? DateTime(1995, 1, 1),
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
                // 移除 locale: zh_CN，避免 Flutter Web 因缺少中文本地化资源而白屏
                // main.dart 中已初始化 zh_CN 日期格式，但 DatePicker 还需要 GlobalMaterialLocalizations
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primary,
                      onPrimary: Colors.white,
                      surface: AppColors.surface,
                      onSurface: AppColors.textPrimary,
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                await context.read<AuthProvider>().updateProfile(
                  birthday: picked,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(UserProfile? profile) {
    final auth = context.watch<AuthProvider>();
    final email = auth.user?.email;
    final displayChar = profile?.username?.isNotEmpty == true
        ? profile!.username![0]
        : (email?.isNotEmpty == true
            ? email![0].toUpperCase()
            : '?');

    // 如果有头像URL，显示网络图片
    final avatarUrl = profile?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: _buildAvatarImage(avatarUrl, 32, 32, _buildDefaultAvatar(displayChar)),
      );
    }
    return _buildDefaultAvatar(displayChar);
  }

  Widget _buildAvatarImage(String url, double width, double height, Widget fallback) {
    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.split(',')[1]);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }

  Widget _buildDefaultAvatar(String displayChar) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D26),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          displayChar,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAiPreferencesSection() {
    return Consumer<AiProvider>(
      builder: (context, aiProvider, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            children: [
              _buildSectionTitle('${aiProvider.aiName}偏好'),
              _buildSettingRow(
                title: '${aiProvider.aiName}的头像',
                trailing: _buildAiAvatarWidget(aiProvider),
                onTap: _uploadAiAvatar,
              ),
              _buildDivider(),
              _buildSettingRow(
                title: '${aiProvider.aiName}的名字',
                subtitle: aiProvider.aiName,
                onTap: () => _showEditDialog(
                  title: '修改${aiProvider.aiName}的名字',
                  initialValue: aiProvider.aiName,
                  onSave: (value) async {
                    await _saveAiName(value, aiProvider);
                  },
                ),
              ),
              _buildDivider(),
              _buildSettingRow(
                title: '${aiProvider.aiName}叫我',
                subtitle: aiProvider.userNickname.isNotEmpty ? aiProvider.userNickname : '未设置',
                onTap: () => _showEditDialog(
                  title: '设置${aiProvider.aiName}怎么称呼你',
                  initialValue: aiProvider.userNickname,
                  onSave: (value) async {
                    await _saveUserNickname(value, aiProvider);
                  },
                ),
              ),
              _buildDivider(),
              _buildSettingRow(
                title: '洞察频率',
                subtitle: '每天',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('偏好设置开发中')),
                  );
                },
              ),
              _buildDivider(),
              _buildSettingRow(
                title: '提醒方式',
                subtitle: '通知',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('偏好设置开发中')),
                  );
                },
              ),
              _buildDivider(),
              _buildSettingRow(
                title: '对话风格',
                subtitle: aiProvider.chatStyle,
                onTap: () => _showChatStylePicker(aiProvider),
              ),
              _buildDivider(),
              _buildSettingRow(
                title: 'AI模型',
                subtitle: '${aiProvider.currentModel.name}（${aiProvider.currentModel.description}）',
                onTap: () => _showModelPicker(aiProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAiName(String name, AiProvider aiProvider) async {
    aiProvider.setAiName(name);
    await aiProvider.saveSettings();
  }

  Future<void> _saveUserNickname(String nickname, AiProvider aiProvider) async {
    aiProvider.setUserNickname(nickname);
    await aiProvider.saveSettings();
  }

  Future<void> _uploadAiAvatar() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 75,
      );
      if (image == null) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last.toLowerCase();
      final avatarUrl = 'data:image/$fileExt;base64,${base64Encode(bytes)}';

      await Supabase.instance.client
          .from('profiles')
          .update({'ai_avatar_url': avatarUrl})
          .eq('id', user.id);

      await context.read<AuthProvider>().updateProfile(aiAvatarUrl: avatarUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI头像更新成功'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), duration: Duration(seconds: 3)),
        );
      }
    }
  }

  Widget _buildAiAvatarWidget(AiProvider aiProvider) {
    final auth = context.watch<AuthProvider>();
    final avatarUrl = auth.profile?.aiAvatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: _buildAvatarImage(avatarUrl, 32, 32, _buildDefaultAiAvatar()),
      );
    }
    return _buildDefaultAiAvatar();
  }

  Widget _buildDefaultAiAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
      ),
      child: const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 16),
    );
  }

  Future<void> _showChatStylePicker(AiProvider aiProvider) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  '选择对话风格',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _chatStyles.map((style) {
                final isSelected = style == aiProvider.chatStyle;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, style),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.borderLight,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      style,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'AI 会根据你选择的风格来回复消息',
              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != aiProvider.chatStyle) {
      // 同步到 AiProvider -> AiService
      aiProvider.setChatStyle(result);
      // 保存到数据库
      await aiProvider.saveSettings();
    }
  }

  Future<void> _showModelPicker(AiProvider aiProvider) async {
    final result = await showModalBottomSheet<AiModel>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('选择AI模型', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ...AiModel.values.map((model) {
                final isSelected = model == aiProvider.currentModel;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, model),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.06) : AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.borderLight,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(model.name, style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              )),
                              const SizedBox(height: 2),
                              Text(model.description, style: TextStyle(
                                fontSize: 12, color: AppColors.textTertiary,
                              )),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );

    if (result != null && result != aiProvider.currentModel) {
      aiProvider.setModel(result);
      // 保存到数据库
      await aiProvider.saveSettings();
    }
  }

  Widget _buildDataPrivacySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          _buildSectionTitle('数据与隐私'),
          _buildSettingRow(
            title: '数据导出',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('数据导出功能开发中')),
              );
            },
          ),
          _buildDivider(),
          _buildSettingRow(
            title: '隐私政策',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('隐私政策开发中')),
              );
            },
          ),
          _buildDivider(),
          _buildSettingRow(
            title: '清除数据',
            textColor: AppColors.stateError,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('清除数据功能开发中')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () {
          _showLogoutDialog(context, auth);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: const Center(
            child: Text(
              '退出登录',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.stateError,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await auth.signOut();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog({
    required String title,
    required String initialValue,
    required Future<void> Function(String value) onSave,
  }) {
    final controller = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                await onSave(value);
              }
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: textColor ?? AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor ?? AppColors.textSecondary,
                ),
              ),
            if (trailing != null) trailing,
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.borderLight,
    );
  }
}
