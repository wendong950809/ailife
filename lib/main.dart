import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/daily_log_provider.dart';
import 'providers/memory_provider.dart';
import 'providers/ai_provider.dart';
import 'data/services/ai_service.dart';

// 集中管理运行时配置
// 云端 build:由 --dart-define 注入(Vercel 环境变量)
// 本地开发:由 .env 文件加载
class AppConfig {
  static String deepseekKey = '';
  static String openaiKey = '';
  static String zhipuKey = '';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter 错误: ${details.exception}');
    print('错误堆栈: ${details.stack}');
  };

  try {
    // 优先 build-time 注入(--dart-define,云端部署用)
    var supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    var supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    AppConfig.deepseekKey = const String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: '');
    AppConfig.openaiKey = const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
    AppConfig.zhipuKey = const String.fromEnvironment('ZHIPU_API_KEY', defaultValue: '');

    // 本地开发 fallback:加载 .env
    if (supabaseUrl.isEmpty) {
      print('本地开发模式:加载 .env...');
      await dotenv.load(fileName: '.env');
      supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      AppConfig.deepseekKey = dotenv.env['DEEPSEEK_API_KEY'] ?? '';
      AppConfig.openaiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
      AppConfig.zhipuKey = dotenv.env['ZHIPU_API_KEY'] ?? '';
    }

    print('SUPABASE_URL: ${supabaseUrl.isNotEmpty ? '已配置' : '未配置'}');
    print('SUPABASE_ANON_KEY: ${supabaseAnonKey.isNotEmpty ? '已配置' : '未配置'}');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception('Supabase 配置不完整');
    }

    print('正在初始化 Supabase...');
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    print('Supabase 初始化完成');

    print('正在检查并添加 profiles 表字段...');
    try {
      await Supabase.instance.client.rpc('add_profile_columns');
    } catch (_) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .select('id')
            .limit(1);
      } catch (e) {
        print('检查 profiles 表失败: $e');
      }
    }
    print('profiles 表检查完成');

    print('正在初始化日期格式化...');
    await initializeDateFormatting('zh_CN', null);
    print('日期格式化初始化完成');

    print('正在启动应用...');
    runApp(const AiLifeApp());
    print('应用启动完成');
  } catch (e, stackTrace) {
    print('启动错误: $e');
    print('堆栈跟踪: $stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AiLifeApp extends StatelessWidget {
  const AiLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DailyLogProvider()),
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        ChangeNotifierProvider(
          create: (_) => AiProvider(
            aiService: AiService(
              deepseekKey: AppConfig.deepseekKey,
              openaiKey: AppConfig.openaiKey,
              zhipuKey: AppConfig.zhipuKey,
            ),
          ),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          return MaterialApp.router(
            title: 'AI人生',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            routerConfig: AppRouter.createRouter(auth),
          );
        },
      ),
    );
  }
}
