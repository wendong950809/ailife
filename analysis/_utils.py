"""
Analysis Engine 内部工具函数
============================
供各子模块复用，避免循环导入。
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

# 中国时区 UTC+8
_CHINA_TZ = timezone(timedelta(hours=8))


def parse_period(period: Optional[str]) -> Optional[datetime]:
    """
    将 period 字符串解析为起始 datetime（中国时区）。
    "90d" -> 90天前的此刻
    "1y"  -> 1年前
    "1w"  -> 1周前
    "all" / None -> None (不限制)
    """
    if not period or period == "all":
        return None
    now = china_now()
    period = period.strip().lower()

    if period.endswith("d"):
        days = int(period[:-1])
        return now - timedelta(days=days)
    if period.endswith("w"):
        weeks = int(period[:-1])
        return now - timedelta(weeks=weeks)
    if period.endswith("y"):
        years = int(period[:-1])
        return now - timedelta(days=365 * years)
    if period.endswith("m"):
        months = int(period[:-1])
        return now - timedelta(days=30 * months)

    return None


def build_query(client, table: str, filters: dict, period: Optional[str]):
    """
    构建带过滤条件的 Supabase 查询。
    返回 query 对象（调用方负责 .execute()）。

    filters 支持的 key（全部业务无关）:
      - text_contains: str        -> title/summary ilike 模糊匹配
      - field_eq: {col: val}      -> 精确匹配
      - field_in: {col: [vals]}   -> IN 匹配
      - date_column: str          -> 日期过滤的列名 (默认 occurred_at / created_at)
    """
    query = client.table(table).select("*")

    date_col = filters.get("date_column")
    if date_col is None:
        date_col = "occurred_at" if table == "timeline" else "created_at"

    # 时间范围
    start = parse_period(period)
    if start is not None:
        query = query.gte(date_col, start.astimezone(_CHINA_TZ).isoformat())

    # 文本模糊匹配
    text = filters.get("text_contains")
    if text:
        query = query.or_(
            f"title.ilike.%{text}%,summary.ilike.%{text}%"
        )

    # 字段精确匹配
    for col, val in (filters.get("field_eq") or {}).items():
        query = query.eq(col, val)

    # 字段 IN 匹配
    for col, vals in (filters.get("field_in") or {}).items():
        if vals:
            query = query.in_(col, vals)

    return query


def to_evidence(rows: list, source: str, limit: int = 50) -> list:
    """将查询结果行转为证据列表。"""
    evidence = []
    for row in rows[:limit]:
        evidence.append({
            "source": source,
            "id": row.get("id"),
            "title": row.get("title") or row.get("summary") or "",
            "occurred_at": to_china_iso(row.get("occurred_at") or row.get("created_at")),
        })
    return evidence


def china_now() -> datetime:
    return datetime.now(_CHINA_TZ)


def china_now_iso() -> str:
    return china_now().strftime("%Y-%m-%dT%H:%M:%S+08:00")


def to_china_iso(dt_str) -> Optional[str]:
    if not dt_str:
        return None
    try:
        if isinstance(dt_str, str):
            dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
        else:
            dt = dt_str
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(_CHINA_TZ).strftime("%Y-%m-%dT%H:%M:%S+08:00")
    except Exception:
        return str(dt_str)


# 时区常量，供子模块使用
CHINA_TZ = _CHINA_TZ
