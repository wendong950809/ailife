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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter 错误: ${details.exception}');
    print('错误堆栈: ${details.stack}');
  };

  try {
    print('正在加载 .env 文件...');
    await dotenv.load(fileName: '.env');
    print('.env 加载完成，变量数量: ${dotenv.env.length}');

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    print('SUPABASE_URL: ${supabaseUrl != null ? '已配置' : '未配置'}');
    print('SUPABASE_ANON_KEY: ${supabaseAnonKey != null ? '已配置' : '未配置'}');

    if (supabaseUrl == null || supabaseAnonKey == null) {
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
              deepseekKey: dotenv.env['DEEPSEEK_API_KEY'],
              openaiKey: dotenv.env['OPENAI_API_KEY'],
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
