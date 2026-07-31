#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI Life 后台管理系统服务器 (Python Flask 版)
完全替代 admin_server.dart
"""

import os
import json
import time
from concurrent.futures import ThreadPoolExecutor
from flask import Flask, request, jsonify, send_from_directory, redirect
import requests
from dotenv import load_dotenv

# ============================================
# 配置加载
# ============================================

load_dotenv()

SUPABASE_URL = os.getenv('SUPABASE_URL', 'https://vjwolnmswmhpxdsskrmg.supabase.co')
SERVICE_KEY = os.getenv('SUPABASE_SERVICE_ROLE_KEY', '')
ANON_KEY = os.getenv('SUPABASE_ANON_KEY', '')
DEEPSEEK_API_KEY = os.getenv('DEEPSEEK_API_KEY', '')

if not SERVICE_KEY:
    print('❌ 需要在 .env 文件中配置 SUPABASE_SERVICE_ROLE_KEY')
    exit(1)

print('✅ 配置加载完成')
print(f'   Supabase URL: {SUPABASE_URL}')
print(f'   Anon Key: {"已配置" if ANON_KEY else "未配置"}')
print(f'   Service Key: {SERVICE_KEY[:10]}...')

# ============================================
# 常量定义
# ============================================

FACT_EXTRACTION_SYSTEM_PROMPT = """你是信息抽取器，从用户消息中抽取最小事实单元，组织为事实组。

核心原则：
1. 只抽取不理解，不推理不猜测
2. 不做业务分类
3. 成组输出，同一句话的事实归为一组
4. 不确定就跳过
5. 粒度统一

事实类型（仅9种）：
- action(name): 行为动作
- person(name/role/relation): 明确身份的人
- reference(type/value/resolved): 代词指向未知身份
- time(date/duration/frequency/milestone/relative): 时间信息
- location(place/from/to): 地点信息
- emotion(feeling/trigger): 真实情绪
- object(name): 对象物品
- intent(type/content): 意图类型，type 仅使用枚举值：request/question/plan/need/consult
- state(status): 状态描述

可信度规则：1.0明确事实, 0.8略有修饰, 0.6暗示, 0.4以下跳过

格式约束：
- 输出必须是纯 JSON，不要 Markdown 代码块
- 无事实时输出：{"summary":"","facts":[]}
- summary 是事实摘要，不超过50字"""

AI_PRICING = {
    'deepseek-chat': {'input': 1.0, 'output': 2.0},
    'deepseek-reasoner': {'input': 4.0, 'output': 16.0},
    'gpt-4o-mini': {'input': 0.15, 'output': 0.6},
    'gpt-3.5-turbo': {'input': 0.5, 'output': 1.5},
    'gpt-4o': {'input': 2.5, 'output': 10.0},
}

CATEGORY_MAP = {
    'message': ['message_send', 'message_delete', 'message_update'],
    'ai': ['ai_call', 'ai_error', 'ai_timeout'],
    'fact': ['fact_extract', 'fact_delete', 'fact_update'],
    'auth': ['auth_login', 'auth_logout', 'auth_register'],
    'user': ['user_create', 'user_update', 'user_delete'],
    'system': ['system_start', 'system_stop', 'system_error'],
}

OPERATION_TYPE_DISPLAY = {
    'message_send': '发送消息',
    'message_delete': '删除消息',
    'message_update': '更新消息',
    'ai_call': 'AI调用',
    'ai_error': 'AI错误',
    'ai_timeout': 'AI超时',
    'fact_extract': '事实提取',
    'fact_delete': '删除事实',
    'fact_update': '更新事实',
    'auth_login': '登录',
    'auth_logout': '退出',
    'auth_register': '注册',
    'user_create': '创建用户',
    'user_update': '更新用户',
    'user_delete': '删除用户',
    'system_start': '系统启动',
    'system_stop': '系统停止',
    'system_error': '系统错误',
}

CATEGORY_DISPLAY = {
    'message': '消息',
    'ai': 'AI',
    'fact': '事实提取',
    'auth': '认证',
    'user': '用户',
    'system': '系统',
    'database': '数据库',
    'http': '网络',
    'business': '业务',
    'other': '其他',
}

ADMIN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'admin')

# ============================================
# 用户缓存
# ============================================

user_cache = {}


def load_user_cache():
    global user_cache
    try:
        users = supabase_select('profiles', select='*')
        user_cache = {u['id']: u for u in users if u.get('id')}
        print(f'✅ 用户缓存已加载: {len(user_cache)} 个用户')
    except Exception as e:
        print(f'⚠️ 用户缓存加载失败: {e}')


def get_user_name(user_id):
    if not user_id:
        return '-'
    user = user_cache.get(user_id)
    if not user:
        return user_id[:8]
    return user.get('username') or user.get('email') or user_id[:8]


# ============================================
# Supabase REST API 辅助函数
# ============================================

def supabase_headers():
    return {
        'apikey': SERVICE_KEY,
        'Authorization': f'Bearer {SERVICE_KEY}',
        'Content-Type': 'application/json',
    }


def supabase_select(table, select='*', filters=None, order=None, ascending=False, limit=10000, offset=None):
    params = {'select': select}
    if filters:
        for k, v in filters.items():
            params[k] = v
    if order:
        params['order'] = f'{order}.{"asc" if ascending else "desc"}'
    if limit:
        params['limit'] = limit
    if offset:
        params['offset'] = offset

    resp = requests.get(
        f'{SUPABASE_URL}/rest/v1/{table}',
        headers=supabase_headers(),
        params=params,
        timeout=15,
    )
    if resp.status_code != 200:
        raise Exception(f'Supabase GET {table} 失败: {resp.status_code} - {resp.text}')
    return resp.json()


def supabase_insert(table, data):
    headers = supabase_headers()
    headers['Prefer'] = 'return=representation'
    resp = requests.post(
        f'{SUPABASE_URL}/rest/v1/{table}',
        headers=headers,
        json=data,
        timeout=15,
    )
    if resp.status_code != 201:
        raise Exception(f'Supabase INSERT {table} 失败: {resp.status_code} - {resp.text}')
    result = resp.json()
    return result[0] if result else {}


def supabase_update(table, data, filter_str):
    headers = supabase_headers()
    headers['Prefer'] = 'return=minimal'
    resp = requests.patch(
        f'{SUPABASE_URL}/rest/v1/{table}?{filter_str}',
        headers=headers,
        json=data,
        timeout=15,
    )
    if resp.status_code not in (200, 204):
        raise Exception(f'Supabase UPDATE {table} 失败: {resp.status_code} - {resp.text}')


def supabase_delete(table, filter_str):
    resp = requests.delete(
        f'{SUPABASE_URL}/rest/v1/{table}?{filter_str}',
        headers=supabase_headers(),
        timeout=15,
    )
    if resp.status_code not in (200, 204):
        raise Exception(f'Supabase DELETE {table} 失败: {resp.status_code} - {resp.text}')


# ============================================
# DeepSeek API
# ============================================

def call_deepseek(system_prompt, user_prompt, temperature=0.2, call_type=None, user_id=None, extra=None):
    """调用 DeepSeek API，可选记录到 ai_call_logs"""
    start_time = time.time()
    resp = requests.post(
        'https://api.deepseek.com/v1/chat/completions',
        headers={
            'Authorization': f'Bearer {DEEPSEEK_API_KEY}',
            'Content-Type': 'application/json',
        },
        json={
            'model': 'deepseek-chat',
            'messages': [
                {'role': 'system', 'content': system_prompt},
                {'role': 'user', 'content': user_prompt},
            ],
            'stream': False,
            'temperature': temperature,
            'top_p': 0.3,
            'max_tokens': 1500,
        },
        timeout=60,
    )
    latency_ms = int((time.time() - start_time) * 1000)

    if resp.status_code != 200:
        if call_type:
            try:
                supabase_insert('ai_call_logs', {
                    'call_type': call_type,
                    'model': 'deepseek-chat',
                    'provider': 'deepseek',
                    'user_id': user_id,
                    'prompt': user_prompt[:500],
                    'system_prompt_preview': system_prompt[:200],
                    'status': 'failed',
                    'error_message': f'HTTP {resp.status_code}: {resp.text[:500]}',
                    'latency_ms': latency_ms,
                    'extra': extra,
                })
            except Exception:
                pass
        raise Exception(f'DeepSeek API 调用失败: {resp.status_code} - {resp.text}')

    result = resp.json()
    choices = result.get('choices', [])
    if not choices:
        if call_type:
            try:
                supabase_insert('ai_call_logs', {
                    'call_type': call_type,
                    'model': 'deepseek-chat',
                    'provider': 'deepseek',
                    'user_id': user_id,
                    'prompt': user_prompt[:500],
                    'system_prompt_preview': system_prompt[:200],
                    'status': 'failed',
                    'error_message': '返回空结果',
                    'latency_ms': latency_ms,
                    'extra': extra,
                })
            except Exception:
                pass
        raise Exception('DeepSeek 返回空结果')

    content = choices[0]['message']['content']
    usage = result.get('usage', {})
    prompt_tokens = usage.get('prompt_tokens', 0)
    completion_tokens = usage.get('completion_tokens', 0)
    total_tokens = usage.get('total_tokens', 0)

    if call_type:
        try:
            supabase_insert('ai_call_logs', {
                'call_type': call_type,
                'model': 'deepseek-chat',
                'provider': 'deepseek',
                'user_id': user_id,
                'prompt': user_prompt[:500],
                'system_prompt_preview': system_prompt[:200],
                'response': content[:1000],
                'prompt_tokens': prompt_tokens,
                'completion_tokens': completion_tokens,
                'total_tokens': total_tokens,
                'status': 'success',
                'latency_ms': latency_ms,
                'temperature': temperature,
                'extra': extra,
            })
        except Exception:
            pass

    return {
        'content': content,
        'prompt_tokens': prompt_tokens,
        'completion_tokens': completion_tokens,
        'total_tokens': total_tokens,
    }


# ============================================
# 费用计算
# ============================================

def calculate_cost(model, prompt_tokens, completion_tokens):
    price = AI_PRICING.get(model)
    if not price:
        return 0.0
    input_cost = (prompt_tokens / 1000000) * price['input']
    output_cost = (completion_tokens / 1000000) * price['output']
    return input_cost + output_cost


def format_cost(cost):
    if cost < 0.01:
        return f'¥{cost:.6f}'
    if cost < 1:
        return f'¥{cost:.4f}'
    return f'¥{cost:.2f}'


# ============================================
# 事实提取
# ============================================

def extract_facts_from_message(message_id):
    messages = supabase_select('messages', filters={'id': f'eq.{message_id}'})
    if not messages:
        raise Exception(f'消息不存在: {message_id}')
    msg = messages[0]
    user_id = msg['user_id']
    content = msg['content']

    user_prompt = (
        f'请从以下用户消息中提取所有客观事实，按 JSON 对象格式输出（包含 summary 和 facts）：\n\n'
        f'用户消息："""{content}"""\n\n'
        f'请只输出 JSON，不要输出任何其他文字。'
    )

    best_result = None
    best_fact_count = -1
    best_summary = ''

    for attempt in range(3):
        try:
            ai_result = call_deepseek(
                FACT_EXTRACTION_SYSTEM_PROMPT,
                user_prompt,
                temperature=0.1,
                call_type='fact_extraction',
                user_id=user_id,
                extra=json.dumps({'message_id': message_id, 'attempt': attempt}, ensure_ascii=False),
            )
            ai_response = ai_result['content']

            json_str = ai_response.strip()
            if json_str.startswith('```json'):
                json_str = json_str[7:]
            if json_str.startswith('```'):
                json_str = json_str[3:]
            if json_str.endswith('```'):
                json_str = json_str[:-3]
            json_str = json_str.strip()

            json_obj = json.loads(json_str)
            summary = (json_obj.get('summary') or '').strip()
            facts = json_obj.get('facts') or []

            if len(facts) > best_fact_count or (
                len(facts) == best_fact_count and summary and not best_summary
            ):
                best_result = json_obj
                best_fact_count = len(facts)
                best_summary = summary

            if len(facts) >= 1:
                break
        except Exception as e:
            print(f'提取尝试 {attempt} 失败: {e}')
            if attempt == 2 and best_result is None:
                raise

    if best_result is None:
        best_result = {'summary': '', 'facts': []}
        best_summary = ''
        best_fact_count = 0

    summary = (best_result.get('summary') or '').strip()
    facts = best_result.get('facts') or []

    # 删除旧数据
    supabase_delete('extracted_facts', f'message_id=eq.{message_id}')
    supabase_delete('fact_groups', f'message_id=eq.{message_id}')

    # 插入新事实组
    group_result = supabase_insert('fact_groups', {
        'message_id': message_id,
        'user_id': user_id,
        'summary': summary,
        'fact_count': len(facts),
        'raw_content': json.dumps(best_result, ensure_ascii=False),
    })
    group_id = group_result['id']

    # 插入事实
    for fact in facts:
        supabase_insert('extracted_facts', {
            'message_id': message_id,
            'user_id': user_id,
            'fact_group_id': group_id,
            'fact_type': fact.get('fact_type', 'other'),
            'fact_key': fact.get('fact_key', 'content'),
            'fact_value': str(fact.get('fact_value', '')),
            'confidence': float(fact.get('confidence', 0.0)),
            'raw_content': json.dumps(best_result, ensure_ascii=False),
        })

    # 更新消息
    supabase_update('messages', {'extracted': True, 'extraction_error': None}, f'id=eq.{message_id}')

    return {
        'success': True,
        'fact_count': len(facts),
        'summary': summary,
        'group_id': group_id,
        'facts': facts,
    }


# ============================================
# 日志分类辅助函数
# ============================================

def get_log_category(op_type):
    """根据操作类型前缀归类"""
    if op_type.startswith('message_'):
        return 'message'
    elif op_type.startswith('ai_'):
        return 'ai'
    elif op_type.startswith('fact_'):
        return 'fact'
    elif op_type.startswith('auth_'):
        return 'auth'
    elif op_type.startswith('user_') or op_type.startswith('profile_'):
        return 'user'
    elif op_type.startswith('system'):
        return 'system'
    elif op_type.startswith('database'):
        return 'database'
    elif op_type.startswith('http'):
        return 'http'
    elif op_type.startswith('memory') or op_type.startswith('daily_log'):
        return 'business'
    else:
        return 'other'


# ============================================
# Flask 应用
# ============================================

app = Flask(__name__, static_folder=None)


@app.before_request
def handle_options():
    if request.method == 'OPTIONS':
        return '', 200


@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    return response


# ============================================
# 静态文件服务
# ============================================

@app.route('/')
@app.route('/admin')
@app.route('/admin/')
def serve_index():
    return send_from_directory(ADMIN_DIR, 'index.html')


@app.route('/admin/<path:path>')
def serve_admin_static(path):
    return send_from_directory(ADMIN_DIR, path)


# ============================================
# API 接口
# ============================================

@app.route('/api/config', methods=['GET'])
def api_config():
    return jsonify({
        'supabaseUrl': SUPABASE_URL,
        'anonKey': ANON_KEY,
    })


@app.route('/api/dashboard', methods=['GET'])
def api_dashboard():
    try:
        with ThreadPoolExecutor(max_workers=5) as executor:
            fut_users = executor.submit(supabase_select, 'profiles', select='id')
            fut_messages = executor.submit(supabase_select, 'messages', select='id')
            fut_user_msgs = executor.submit(supabase_select, 'messages', select='id,extracted', filters={'role': 'eq.user'})
            fut_facts = executor.submit(supabase_select, 'extracted_facts', select='id')
            fut_msgs_with_facts = executor.submit(supabase_select, 'extracted_facts', select='message_id')

            users = fut_users.result()
            messages = fut_messages.result()
            all_user_msgs = fut_user_msgs.result()
            facts = fut_facts.result()
            messages_with_facts = fut_msgs_with_facts.result()

        fact_message_ids = {m['message_id'] for m in messages_with_facts if m.get('message_id')}

        unextracted = [m for m in all_user_msgs if not (m.get('extracted') or False)]

        inconsistent = 0
        for msg in unextracted:
            msg_id = msg.get('id')
            if msg_id and msg_id in fact_message_ids:
                inconsistent += 1

        failed_logs = 0
        try:
            logs = supabase_select('operation_logs', select='id', filters={'status': 'eq.failed'})
            failed_logs = len(logs)
        except Exception:
            pass

        return jsonify({
            'users': len(users),
            'messages': len(messages),
            'userMessages': len(all_user_msgs),
            'facts': len(facts),
            'failedLogs': failed_logs,
            'unextracted': len(unextracted),
            'inconsistent': inconsistent,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/messages', methods=['GET'])
def api_messages():
    try:
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '20'))
        keyword = (request.args.get('keyword') or '').strip()

        filters = {}
        role = request.args.get('role')
        if role:
            filters['role'] = f'eq.{role}'

        all_data = supabase_select(
            'messages',
            select='id,user_id,role,content,extracted,extraction_error,created_at',
            filters=filters if filters else None,
            order='created_at',
            ascending=False,
        )

        # 按 keyword 搜索
        if keyword:
            kw = keyword.lower()
            all_data = [m for m in all_data if kw in (m.get('content') or '').lower()]

        # 查询 extracted_facts 统计每条消息的事实数
        all_facts = supabase_select('extracted_facts', select='message_id')
        fact_counts = {}
        for f in all_facts:
            mid = f.get('message_id')
            if mid:
                fact_counts[mid] = fact_counts.get(mid, 0) + 1

        # 查询已存在的 fact_groups
        all_groups = supabase_select('fact_groups', select='message_id')
        existing_group_message_ids = {g.get('message_id') for g in all_groups if g.get('message_id')}

        # 为已提取但没有事实组的消息补建空事实组
        for m in all_data:
            msg_id = m.get('id')
            extracted = m.get('extracted') or False
            if msg_id and extracted and msg_id not in existing_group_message_ids:
                try:
                    supabase_insert('fact_groups', {
                        'message_id': msg_id,
                        'user_id': m.get('user_id'),
                        'summary': '(未提取到事实)',
                        'fact_count': 0,
                        'raw_content': '{"summary":"(未提取到事实)","facts":[]}',
                    })
                    existing_group_message_ids.add(msg_id)
                except Exception:
                    pass

        # 按 extracted 参数过滤
        extracted_param = request.args.get('extracted')
        if extracted_param == 'true':
            filtered = [m for m in all_data if m.get('extracted') or False]
        elif extracted_param == 'false':
            filtered = [m for m in all_data if not (m.get('extracted') or False)]
        else:
            filtered = all_data

        # 内存分页
        offset = (page - 1) * limit
        paged = filtered[offset:offset + limit]

        # 添加用户名和事实条数
        result = []
        for m in paged:
            msg_id = m.get('id')
            item = dict(m)
            item['user_name'] = get_user_name(m.get('user_id'))
            item['fact_count'] = fact_counts.get(msg_id, 0) if msg_id else 0
            result.append(item)

        return jsonify({
            'data': result,
            'page': page,
            'limit': limit,
            'total': len(filtered),
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/fact-groups', methods=['GET'])
def api_fact_groups():
    try:
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '20'))
        keyword = (request.args.get('keyword') or '').strip()
        fact_type_filter = request.args.get('fact_type')

        all_groups = supabase_select(
            'fact_groups',
            select='id,message_id,user_id,summary,fact_count,created_at',
            order='created_at',
            ascending=False,
        )

        # 按 keyword 搜索
        if keyword:
            kw = keyword.lower()
            all_groups = [g for g in all_groups if kw in (g.get('summary') or '').lower()]

        # 按 fact_type 过滤
        if fact_type_filter:
            facts = supabase_select(
                'extracted_facts',
                select='fact_group_id',
                filters={'fact_type': f'eq.{fact_type_filter}'},
            )
            groups_with_type = {f.get('fact_group_id') for f in facts if f.get('fact_group_id')}
            all_groups = [g for g in all_groups if g.get('id') in groups_with_type]

        # 内存分页
        offset = (page - 1) * limit
        paged = all_groups[offset:offset + limit]
        total = len(all_groups)

        # 批量查询 extracted_facts
        group_ids = [g['id'] for g in paged if g.get('id')]
        facts_by_group = {}
        if group_ids:
            facts = supabase_select(
                'extracted_facts',
                select='id,fact_group_id,fact_type,fact_key,fact_value,confidence',
                filters={'fact_group_id': f'in.({",".join(group_ids)})'},
            )
            for f in facts:
                gid = f.get('fact_group_id')
                if gid:
                    facts_by_group.setdefault(gid, []).append(f)

        # 批量查询 messages 取 content
        message_ids = list({g.get('message_id') for g in paged if g.get('message_id')})
        message_map = {}
        if message_ids:
            msgs = supabase_select(
                'messages',
                select='id,content',
                filters={'id': f'in.({",".join(message_ids)})'},
            )
            for m in msgs:
                message_map[m['id']] = m.get('content') or ''

        # 拼接结果
        result = []
        for g in paged:
            item = dict(g)
            item['user_name'] = get_user_name(g.get('user_id'))
            item['message_content'] = message_map.get(g.get('message_id'), '')
            item['facts'] = facts_by_group.get(g.get('id'), [])
            result.append(item)

        return jsonify({
            'data': result,
            'page': page,
            'limit': limit,
            'total': total,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/logs', methods=['GET'])
def api_logs():
    try:
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '20'))
        keyword = (request.args.get('keyword') or '').strip()

        data = []
        try:
            data = supabase_select(
                'operation_logs',
                select='*',
                order='created_at',
                ascending=False,
            )

            # 按 keyword 搜索
            if keyword:
                kw = keyword.lower()
                data = [l for l in data if kw in (l.get('description') or '').lower() or kw in (l.get('details') or '').lower()]

            # 按 status 过滤
            status = request.args.get('status')
            if status:
                data = [l for l in data if l.get('status') == status]

            # 按 operation_type 过滤
            op_type = request.args.get('operation_type')
            if op_type:
                data = [l for l in data if l.get('operation_type') == op_type]

            # 按 category 过滤（前缀匹配）
            category = request.args.get('category')
            if category:
                cat_types = CATEGORY_MAP.get(category, [])
                if cat_types:
                    data = [l for l in data if l.get('operation_type') in cat_types]
                else:
                    # 前缀匹配兜底
                    prefix = category + '_'
                    data = [l for l in data if (l.get('operation_type') or '').startswith(prefix)]

            total = len(data)

            # 内存分页
            offset = (page - 1) * limit
            paged = data[offset:offset + limit]

            # 映射中文分类和操作类型名
            result = []
            for log in paged:
                op = log.get('operation_type') or ''
                cat_key = get_log_category(op)
                item = dict(log)
                item['user_name'] = get_user_name(log.get('user_id'))
                item['category'] = CATEGORY_DISPLAY.get(cat_key, cat_key)
                item['operation_type_display'] = OPERATION_TYPE_DISPLAY.get(op, op)
                result.append(item)

            data = result
        except Exception:
            pass

        return jsonify({
            'data': data,
            'page': page,
            'limit': limit,
            'total': len(data),
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/logs/statistics', methods=['GET'])
def api_logs_statistics():
    try:
        stats = {
            'message': 0, 'ai': 0, 'fact': 0, 'auth': 0, 'user': 0,
            'system': 0, 'database': 0, 'http': 0, 'business': 0, 'other': 0,
            'success': 0, 'failed': 0, 'pending': 0, 'info': 0,
            'total': 0,
        }

        try:
            data = supabase_select('operation_logs', select='operation_type,status')
            stats['total'] = len(data)

            for log in data:
                op_type = log.get('operation_type') or ''
                status = log.get('status') or ''

                if status in stats:
                    stats[status] += 1

                cat = get_log_category(op_type)
                if cat in stats:
                    stats[cat] += 1
                else:
                    stats['other'] += 1
        except Exception:
            pass

        return jsonify(stats)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/ai-logs', methods=['GET'])
def api_ai_logs():
    try:
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '20'))
        keyword = (request.args.get('keyword') or '').strip()

        data = []
        total = 0
        try:
            data = supabase_select(
                'ai_call_logs',
                select='*',
                order='created_at',
                ascending=False,
            )

            # 按 keyword 搜索
            if keyword:
                kw = keyword.lower()
                data = [l for l in data if kw in (l.get('call_type') or '').lower()
                        or kw in (l.get('prompt') or '').lower()
                        or kw in (l.get('response') or '').lower()]

            # 按 call_type 过滤
            call_type = request.args.get('call_type')
            if call_type:
                data = [l for l in data if l.get('call_type') == call_type]

            # 按 status 过滤
            status = request.args.get('status')
            if status:
                data = [l for l in data if l.get('status') == status]

            total = len(data)

            # 内存分页
            offset = (page - 1) * limit
            paged = data[offset:offset + limit]

            # 计算费用并拼接 user_name
            result = []
            for log in paged:
                model = log.get('model') or ''
                prompt_tokens = log.get('prompt_tokens') or 0
                completion_tokens = log.get('completion_tokens') or 0
                cost = calculate_cost(model, prompt_tokens, completion_tokens)
                price = AI_PRICING.get(model)
                item = dict(log)
                item['user_name'] = get_user_name(log.get('user_id'))
                item['cost'] = cost
                item['cost_display'] = format_cost(cost)
                item['input_price'] = price['input'] if price else 0
                item['output_price'] = price['output'] if price else 0
                result.append(item)

            return jsonify({
                'data': result,
                'page': page,
                'limit': limit,
                'total': total,
            })
        except Exception as e:
            return jsonify({
                'data': [],
                'page': page,
                'limit': limit,
                'total': 0,
                'error': str(e),
            })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/ai-logs/statistics', methods=['GET'])
def api_ai_logs_statistics():
    try:
        stats = {
            'total': 0,
            'success': 0,
            'failed': 0,
            'total_tokens': 0,
            'prompt_tokens': 0,
            'completion_tokens': 0,
            'total_latency_ms': 0,
            'total_cost': 0.0,
            'fact_extraction': 0,
            'intent_detection': 0,
            'chat': 0,
            'other': 0,
        }

        try:
            data = supabase_select('ai_call_logs', select='call_type,status,prompt_tokens,completion_tokens,total_tokens,latency_ms,model')
            stats['total'] = len(data)

            for log in data:
                status = log.get('status') or ''
                call_type = log.get('call_type') or ''
                model = log.get('model') or ''
                prompt_tokens = log.get('prompt_tokens') or 0
                completion_tokens = log.get('completion_tokens') or 0

                if status == 'success':
                    stats['success'] += 1
                elif status == 'failed':
                    stats['failed'] += 1

                stats['prompt_tokens'] += prompt_tokens
                stats['completion_tokens'] += completion_tokens
                stats['total_tokens'] += log.get('total_tokens') or 0
                stats['total_latency_ms'] += log.get('latency_ms') or 0
                stats['total_cost'] += calculate_cost(model, prompt_tokens, completion_tokens)

                if call_type == 'fact_extraction':
                    stats['fact_extraction'] += 1
                elif call_type == 'intent_detection':
                    stats['intent_detection'] += 1
                elif call_type == 'chat':
                    stats['chat'] += 1
                else:
                    stats['other'] += 1

            total_count = stats['total']
            total_latency = stats['total_latency_ms']
            stats['avg_latency_ms'] = round(total_latency / total_count) if total_count > 0 else 0
            stats['total_cost_display'] = format_cost(stats['total_cost'])
            stats['avg_cost'] = stats['total_cost'] / total_count if total_count > 0 else 0.0
            stats['avg_cost_display'] = format_cost(stats['avg_cost'])
        except Exception:
            pass

        return jsonify(stats)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/users', methods=['GET'])
def api_users():
    try:
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '20'))
        keyword = (request.args.get('keyword') or '').strip()

        data = supabase_select('profiles', select='*', order='created_at', ascending=False)

        # 按 keyword 搜索
        if keyword:
            kw = keyword.lower()
            data = [u for u in data
                    if kw in (u.get('username') or '').lower()
                    or kw in (u.get('nickname') or '').lower()
                    or kw in (u.get('email') or '').lower()]

        total = len(data)

        # 内存分页
        offset = (page - 1) * limit
        paged = data[offset:offset + limit]

        return jsonify({
            'data': paged,
            'page': page,
            'limit': limit,
            'total': total,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/users/refresh', methods=['POST'])
def api_users_refresh():
    try:
        load_user_cache()
        return jsonify({'success': True, 'count': len(user_cache)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/check', methods=['GET'])
def api_check():
    try:
        user_messages = supabase_select(
            'messages',
            select='id,content,extracted',
            filters={'role': 'eq.user'},
        )
        all_facts = supabase_select('extracted_facts', select='id,message_id')
        fact_message_ids = {f.get('message_id') for f in all_facts if f.get('message_id')}

        issues = []
        for msg in user_messages:
            msg_id = msg.get('id')
            extracted = msg.get('extracted') or False
            has_facts = msg_id in fact_message_ids

            if has_facts and not extracted:
                content = msg.get('content') or ''
                issues.append({
                    'type': 'inconsistent',
                    'message_id': msg_id,
                    'content': content[:50],
                    'issue': '已有事实数据但 extracted=false',
                })

        return jsonify({
            'totalMessages': len(user_messages),
            'totalFacts': len(all_facts),
            'issues': issues,
            'issueCount': len(issues),
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/fix', methods=['POST'])
def api_fix():
    try:
        body = request.get_json(silent=True) or {}
        action = body.get('action')

        if action == 'fix_extracted':
            user_messages = supabase_select(
                'messages',
                select='id',
                filters={'role': 'eq.user', 'extracted': 'neq.true'},
            )
            all_facts = supabase_select('extracted_facts', select='message_id')
            fact_message_ids = {f.get('message_id') for f in all_facts if f.get('message_id')}

            fixed = 0
            for msg in user_messages:
                msg_id = msg.get('id')
                if msg_id and msg_id in fact_message_ids:
                    supabase_update('messages', {'extracted': True, 'extraction_error': None}, f'id=eq.{msg_id}')
                    fixed += 1

            return jsonify({'fixed': fixed})

        return jsonify({'error': '未知的修复操作'}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/reextract', methods=['POST'])
def api_reextract():
    try:
        if not DEEPSEEK_API_KEY:
            return jsonify({'error': 'DEEPSEEK_API_KEY 未配置'}), 400

        body = request.get_json(silent=True) or {}
        message_id = body.get('message_id')

        if not message_id:
            return jsonify({'error': '缺少 message_id'}), 400

        result = extract_facts_from_message(message_id)
        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/facts/<fact_id>', methods=['DELETE'])
def api_delete_fact(fact_id):
    try:
        supabase_delete('extracted_facts', f'id=eq.{fact_id}')
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/reextract/all', methods=['POST'])
def api_reextract_all():
    try:
        if not DEEPSEEK_API_KEY:
            return jsonify({'error': 'DEEPSEEK_API_KEY 未配置'}), 400

        unextracted = supabase_select(
            'messages',
            select='id',
            filters={'role': 'eq.user', 'extracted': 'eq.false'},
        )

        if not unextracted:
            return jsonify({
                'success': True,
                'count': 0,
                'success_count': 0,
                'failed_count': 0,
                'failed_messages': [],
            })

        success_count = 0
        failed_count = 0
        failed_messages = []

        for msg in unextracted:
            msg_id = msg.get('id')
            try:
                extract_facts_from_message(msg_id)
                success_count += 1
                print(f'✅ 消息 {msg_id} 提取成功')
            except Exception as e:
                failed_count += 1
                failed_messages.append(f'{msg_id}: {e}')
                print(f'❌ 消息 {msg_id} 提取失败: {e}')

        return jsonify({
            'success': True,
            'count': len(unextracted),
            'success_count': success_count,
            'failed_count': failed_count,
            'failed_messages': failed_messages,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ============================================
# 404 处理：非 API 路径重定向到 /admin/
# ============================================

@app.errorhandler(404)
def not_found(e):
    if request.path.startswith('/api/'):
        return jsonify({'error': f'未知的 API 路径: {request.path}'}), 404
    return redirect('/admin/', code=302)


# ============================================
# 主函数
# ============================================

if __name__ == '__main__':
    load_user_cache()
    print('🚀 AI Life 后台管理系统已启动')
    print('   本机访问: http://127.0.0.1:8081')
    print('')
    app.run(host='0.0.0.0', port=8081, debug=False)
