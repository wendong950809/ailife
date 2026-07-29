# AI Life - 系统架构说明

## 项目概述

AI Life（数字自我）是一个基于 AI 的个人生活记录与记忆管理系统。用户通过日常聊天与 AI 对话，系统自动从对话中抽取事实，构建个人时间线，最终形成可追溯的个人数字记忆。

## 技术栈

| 层次 | 技术 | 说明 |
|------|------|------|
| 前端 | Flutter Web | 移动端/Web 应用 |
| 后端 | Supabase | 数据库与认证 |
| AI | DeepSeek API | 事实抽取与时间线生成 |
| 服务器 | Dart HttpServer | 静态文件托管与 API |

## 三层架构

### 第一层：事实抽取（Fact Extraction）

**职责**：从用户消息中抽取最小事实单元，组织为事实组。

**核心原则**：
1. 只抽取不理解，不推理不猜测
2. 不做业务分类（目标/工作/家庭等交给第二层）
3. 成组输出，同一句话的事实归为一组
4. 不确定就跳过
5. 粒度统一：每种事实类型都有明确边界

**事实类型（9种）**：
- action(name): 行为动作
- person(name/role/relation): 明确身份的人
- reference(type/value/resolved): 代词指向未知身份
- time(date/duration/frequency/milestone/relative): 时间信息
- location(place/from/to): 地点信息
- emotion(feeling/trigger): 真实情绪
- object(name): 对象物品
- intent(type/content): 意图类型
- state(status): 状态描述

**可信度规则**：
- 1.0: 明确事实
- 0.8: 略有修饰
- 0.6: 暗示
- 0.4以下: 跳过

### 第二层：时间线生成（Timeline Generation）

**职责**：将 Fact Group + 原始 Message 转换为 Timeline 事件卡片。

**核心原则**：
1. Timeline 是产品，不是 AI 分析
2. 只呈现，不评判
3. 不做业务分类
4. 用用户的语言
5. Fact 提供结构，Message 提供细节

**输出字段**：
- title: 一句话标题（≤30字）
- summary: 2-3句话摘要
- occurred_at: ISO 8601 时间格式
- time_precision: day/week/month/year/unknown
- icon: emoji 图标

### 第三层：记忆（Memory）

**状态**：规划中

**职责**：基于时间线事件构建长期记忆，支持智能查询与关联。

## 目录结构

```
lib/
├── core/
│   ├── agents/           # AI Agent 定义
│   │   ├── agent_definition.dart
│   │   ├── fact_extraction_agent.dart
│   │   └── timeline_agent.dart
│   ├── constants/        # 常量定义
│   ├── router/           # 路由管理
│   └── theme/            # 主题配置
├── data/
│   ├── models/           # 数据模型
│   └── services/         # 业务服务
├── presentation/
│   ├── pages/            # 页面组件
│   └── widgets/          # 通用组件
├── providers/            # 状态管理
└── main.dart             # 入口文件
```

## 数据库表结构

| 表名 | 用途 |
|------|------|
| profiles | 用户配置（ai_name, nickname, ai_avatar_url） |
| messages | 聊天消息 |
| fact_groups | 事实组（summary, fact_count） |
| extracted_facts | 提取的事实单元 |
| timeline | 时间线事件 |
| ai_call_logs | AI 调用日志 |
| operation_logs | 操作日志 |

## 数据流

```
用户消息 → Message 表 → Fact Extraction Agent → Fact Group + Facts
                                                    ↓
                                        Timeline Agent → Timeline 事件
```

## 关键设计决策

1. **分离事实抽取与时间线生成**：确保数据完整性，时间线可从事实重新生成
2. **统一事实粒度**：9种事实类型，明确边界，避免越界
3. **时间精度标注**：每个时间线事件标注精度（day/week/month/year/unknown）
4. **用户语言优先**：时间线标题和摘要使用用户口语化表达
5. **去重规则**：同一组内相同事实只保留一个，person 不重复
