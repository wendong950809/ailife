import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_profile.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ai_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _uploadAvatar() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (image == null) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 读取文件bytes
      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last.toLowerCase();
      final fileName = '${user.id}/avatar.$fileExt';

      // 上传到 Supabase Storage
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$fileExt',
              upsert: true,
            ),
          );

      // 获取公开URL
      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      // 更新 profiles 表
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      // 更新 AuthProvider
      if (mounted) {
        context.read<AuthProvider>().updateProfile(avatarUrl: publicUrl);
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
          const Center(
            child: Text(
              '知伴 v0.1',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
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
            title: '生日',
            subtitle: profile?.birthday != null
                ? '${profile!.birthday!.year}年${profile.birthday!.month}月'
                : '未设置',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: profile?.birthday ?? DateTime(1990, 1, 1),
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
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
    final auth = context.read<AuthProvider>();
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
        child: Image.network(
          avatarUrl,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildDefaultAvatar(displayChar),
        ),
      );
    }
    return _buildDefaultAvatar(displayChar);
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
                title: '${aiProvider.aiName}的名字',
                subtitle: aiProvider.aiName,
                onTap: () => _showEditDialog(
                  title: '修改${aiProvider.aiName}的名字',
                  initialValue: aiProvider.aiName,
                  onSave: (value) async {
                    aiProvider.setAiName(value);
                    await _saveAiName(value);
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
                    aiProvider.setUserNickname(value);
                    await _saveUserNickname(value);
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
                subtitle: '简洁',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('偏好设置开发中')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAiName(String name) async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'ai_name': name})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('保存AI名称失败: $e');
    }
  }

  Future<void> _saveUserNickname(String nickname) async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'nickname': nickname})
          .eq('id', user.id);
    } catch (e) {
      debugPrint('保存用户昵称失败: $e');
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
