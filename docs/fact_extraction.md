# AI Life - 事实抽取设计

## 核心原则

1. **只抽取不理解**：只提取事实，不进行推理或猜测
2. **不做业务分类**：目标/工作/家庭等分类交给第二层 Timeline Agent
3. **成组输出**：同一句话的事实归为一组
4. **不确定就跳过**：可信度低于 0.4 的事实不输出
5. **粒度统一**：每种事实类型都有明确边界，不要越界

## 事实类型详解

### 1. action(name)

**定义**：行为动作，只回答"发生了什么？"，不含人物/地点/时间

**正确示例**：
- "骑车"（不是"陪女儿去公园骑车"）
- "创业"（不是"去年开始创业"）
- "赚到利润"（不是"今年赚到第一笔利润"）

**错误示例**：
- ❌ "陪女儿去公园骑车"（包含了 person 和 location）
- ❌ "去年开始创业"（包含了 time）

### 2. person(name/role/relation)

**定义**：明确身份的人

**事实键**：
- name: 姓名，如"张三"
- role: 角色，如"老板"、"同事"
- relation: 关系，如"女儿"、"父亲"、"朋友"

**正确示例**：
- {"fact_type":"person","fact_key":"relation","fact_value":"女儿"}
- {"fact_type":"person","fact_key":"name","fact_value":"张三"}
- {"fact_type":"person","fact_key":"role","fact_value":"老板"}

### 3. reference(type/value/resolved)

**定义**：代词指向未知身份

**事实键**：
- type: 指向类型（person/object/location/time）
- value: 代词值，如"她"、"他"、"它"、"那里"
- resolved: 是否已解析（true/false）

**正确示例**：
- {"fact_type":"reference","fact_key":"type","fact_value":"person"}
- {"fact_type":"reference","fact_key":"value","fact_value":"她"}
- {"fact_type":"reference","fact_key":"resolved","fact_value":false}

### 4. time(date/duration/frequency/milestone/relative)

**定义**：时间信息

**事实键**：
- date: 具体日期，如"今天"、"昨天"、"7月21日"、"2023年"
- duration: 持续时间，如"两小时"、"三天"、"一个月"
- frequency: 频率，如"每天"、"每周"、"偶尔"
- milestone: 里程碑，如"第一次"、"毕业"、"结婚"
- relative: 相对时间，如"小时候"、"最近"、"之前"

**正确示例**：
- {"fact_type":"time","fact_key":"date","fact_value":"今天"}
- {"fact_type":"time","fact_key":"duration","fact_value":"一个多小时"}
- {"fact_type":"time","fact_key":"frequency","fact_value":"每天"}
- {"fact_type":"time","fact_key":"milestone","fact_value":"第一次"}

### 5. location(place/from/to)

**定义**：地点信息

**事实键**：
- place: 地点名称，如"公司"、"北京"、"公园"
- from: 出发地
- to: 目的地

**正确示例**：
- {"fact_type":"location","fact_key":"place","fact_value":"公园"}
- {"fact_type":"location","fact_key":"from","fact_value":"家"}
- {"fact_type":"location","fact_key":"to","fact_value":"公司"}

### 6. emotion(feeling/trigger)

**定义**：真实情绪，仅限基本情绪词，不含价值判断

**约束**：
- 仅限基本情绪词：开心、难过、焦虑、放松、生气、兴奋、沮丧、平静等
- 不包含价值判断："值得"、"应该"、"重要"、"好"、"坏"等

**事实键**：
- feeling: 情绪词
- trigger: 情绪触发原因（可选）

**正确示例**：
- {"fact_type":"emotion","fact_key":"feeling","fact_value":"开心"}
- {"fact_type":"emotion","fact_key":"feeling","fact_value":"沮丧"}

**错误示例**：
- ❌ {"fact_type":"emotion","fact_key":"feeling","fact_value":"值得"}（价值判断）
- ❌ {"fact_type":"emotion","fact_key":"feeling","fact_value":"应该"}（价值判断）

### 7. object(name)

**定义**：对象物品，仅当 Action 无法完整表达时使用

**约束**：
- 如果 Action 已经完整表达了事件，不需要 Object
- 例如 Action="赚到第一笔利润"已完整，则不需要 Object="利润"

**正确示例**：
- Action="骑车" + Object="自行车"
- Action="写" + Object="合同"

**错误示例**：
- ❌ Action="赚到利润" + Object="利润"（Action 已完整）

### 8. intent(type/content)

**定义**：意图类型

**事实键**：
- type: 意图类型，仅使用枚举值：request/question/plan/need/consult
- content: 意图内容，只描述意图类型，不重复 Action 内容

**type 枚举值**：
- request: 请求帮助
- question: 提出问题
- plan: 计划安排
- need: 需求表达
- consult: 咨询建议

**正确示例**：
- {"fact_type":"intent","fact_key":"type","fact_value":"plan"}
- {"fact_type":"intent","fact_key":"content","fact_value":"成立公司"}

**错误示例**：
- ❌ {"fact_type":"intent","fact_key":"content","fact_value":"骑车去公园"}（重复了 Action 内容）

### 9. state(status)

**定义**：状态描述

**正确示例**：
- {"fact_type":"state","fact_key":"status","fact_value":"腰疼"}
- {"fact_type":"state","fact_key":"status","fact_value":"身体不舒服"}
- {"fact_type":"state","fact_key":"status","fact_value":"业务增长"}

## 可信度规则

| 可信度 | 含义 | 是否输出 |
|--------|------|---------|
| 1.0 | 明确事实 | ✅ |
| 0.8 | 略有修饰 | ✅ |
| 0.6 | 暗示 | ✅ |
| 0.4 | 不确定 | ❌ |
| < 0.4 | 高度不确定 | ❌ |

## 去重规则

1. **同一组内去重**：相同 fact_type + fact_key + fact_value 的事实只保留一个
2. **person 去重**：同一组内相同身份的 person 只保留一次
3. **Action 与 Intent 去重**：不要表达同一件事（Intent 描述意图类型，Action 描述具体行为）

## 格式约束

### 输出格式

必须是纯 JSON，不要 Markdown 代码块：

```json
{
  "summary": "事实摘要，不超过50字",
  "facts": [
    {"fact_type": "...", "fact_key": "...", "fact_value": "...", "confidence": 1.0}
  ]
}
```

### 无事实时输出

```json
{"summary":"","facts":[]}
```

### summary 要求

- 不超过 50 字
- 只描述事实，不做推理
- 非推理性事实压缩

## 输入输出示例

### 示例 1

**输入**："今天陪女儿去公园骑自行车"

**输出**：
```json
{
  "summary": "今天陪女儿去公园骑自行车",
  "facts": [
    {"fact_type":"action","fact_key":"name","fact_value":"骑自行车","confidence":1.0},
    {"fact_type":"person","fact_key":"relation","fact_value":"女儿","confidence":1.0},
    {"fact_type":"location","fact_key":"place","fact_value":"公园","confidence":1.0},
    {"fact_type":"time","fact_key":"date","fact_value":"今天","confidence":1.0},
    {"fact_type":"reference","fact_key":"type","fact_value":"person","confidence":1.0},
    {"fact_type":"reference","fact_key":"value","fact_value":"她","confidence":1.0},
    {"fact_type":"reference","fact_key":"resolved","fact_value":false,"confidence":1.0}
  ]
}
```

### 示例 2

**输入**："去年开始创业，今年赚到第一笔利润，希望明年成立自己的公司"

**输出**：
```json
{
  "summary": "去年创业今年盈利，计划明年成立公司",
  "facts": [
    {"fact_type":"action","fact_key":"name","fact_value":"开始创业","confidence":1.0},
    {"fact_type":"action","fact_key":"name","fact_value":"赚到利润","confidence":1.0},
    {"fact_type":"time","fact_key":"date","fact_value":"去年","confidence":1.0},
    {"fact_type":"time","fact_key":"date","fact_value":"今年","confidence":1.0},
    {"fact_type":"time","fact_key":"date","fact_value":"明年","confidence":1.0},
    {"fact_type":"intent","fact_key":"type","fact_value":"plan","confidence":0.8},
    {"fact_type":"intent","fact_key":"content","fact_value":"成立公司","confidence":0.8}
  ]
}
```

### 示例 3

**输入**："父亲腰疼不愿去大医院"

**输出**：
```json
{
  "summary": "父亲腰疼不愿去大医院",
  "facts": [
    {"fact_type":"person","fact_key":"relation","fact_value":"父亲","confidence":1.0},
    {"fact_type":"state","fact_key":"status","fact_value":"腰疼","confidence":1.0},
    {"fact_type":"location","fact_key":"place","fact_value":"大医院","confidence":1.0},
    {"fact_type":"intent","fact_key":"type","fact_value":"need","confidence":0.8},
    {"fact_type":"intent","fact_key":"content","fact_value":"去医院","confidence":0.8}
  ]
}
```

## 数据模型

### fact_groups 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| message_id | UUID | 关联消息 ID |
| user_id | UUID | 用户 ID |
| summary | TEXT | 事实组摘要（≤50字） |
| fact_count | INTEGER | 事实数量 |
| raw_content | TEXT | AI 原始响应 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

### extracted_facts 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | 主键 |
| fact_group_id | UUID | 关联事实组 ID |
| message_id | UUID | 关联消息 ID |
| user_id | UUID | 用户 ID |
| fact_type | TEXT | 事实类型（9种） |
| fact_key | TEXT | 事实键 |
| fact_value | TEXT | 事实值 |
| confidence | DOUBLE | 可信度（0-1） |
| raw_content | TEXT | AI 原始响应 |
| created_at | TIMESTAMP | 创建时间 |

## 处理流程

```
用户消息 → AI 调用（FactExtractionAgent）→ JSON 解析
                                                ↓
                              删除旧的 facts 和 fact_group
                                                ↓
                              创建新的 fact_group
                                                ↓
                              写入 extracted_facts
                                                ↓
                              更新 messages 表的 extracted 标识
                                                ↓
                              记录操作日志
```

## 关键设计决策

1. **9种事实类型**：经过反复讨论确定，覆盖日常聊天中最常见的信息类型
2. **粒度统一**：Action 只回答"发生了什么"，不含人物/地点/时间，确保数据结构一致性
3. **reference 类型**：处理代词问题，为后续指代消解预留空间
4. **summary 限制 50 字**：确保事实摘要简洁，用于时间线标题生成
5. **emotion 不含价值判断**：避免 AI 主观评价，保持事实客观性
6. **intent type 枚举值**：限制意图类型，避免重复和混乱
