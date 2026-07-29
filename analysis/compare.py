"""
Compare - 对比能力
===================
负责：对比两个时间段的同一指标。
返回：变化率（百分比）。

对比逻辑:
  period="30d" → A = 最近30天, B = 再往前30天
  即 A=[now-30d, now], B=[now-60d, now-30d]
"""

from datetime import timedelta, timezone
from ._utils import build_query, to_evidence, parse_period, china_now


def compare(
    client, table: str, source: str, filters: dict,
    period, period_b, **kwargs
):
    """
    对比两个时间段。

    参数:
        period:   时间段 A (如 "30d" = 最近30天)
        period_b: 时间段 B 的长度 (如 "30d")。
                  若为 None 则默认与 A 等长。

    返回:
        result: {
            "period_a": {"label": "30d", "count": int},
            "period_b": {"label": "prev_30d", "count": int},
            "diff": int,
            "change_rate": float,
            "direction": "up" | "down" | "same",
        }
        evidence: 证据列表（来自两个时段）
    """
    now = china_now()
    start_a = parse_period(period)

    if start_a is None:
        # 无 period 默认 30 天
        start_a = now - timedelta(days=30)

    duration_days = max((now - start_a).days, 1)

    # B 的长度：用 period_b 解析，如果没给就用 A 的长度
    if period_b:
        start_b_temp = parse_period(period_b)
        if start_b_temp is not None:
            b_duration = max((now - start_b_temp).days, 1)
        else:
            b_duration = duration_days
    else:
        b_duration = duration_days

    # B 区间: [start_a - b_duration, start_a]
    b_start = start_a - timedelta(days=b_duration)
    b_end = start_a

    date_col = "occurred_at" if table == "timeline" else "created_at"

    # --- 查询 A ---
    query_a = build_query(client, table, filters, period)
    resp_a = query_a.order(date_col, desc=True).limit(5000).execute()
    rows_a = resp_a.data or []
    count_a = len(rows_a)

    # --- 查询 B ---
    query_b = client.table(table).select("*")
    query_b = query_b.gte(date_col, b_start.astimezone(timezone.utc).isoformat())
    query_b = query_b.lt(date_col, b_end.astimezone(timezone.utc).isoformat())

    # 应用相同 filters
    text = filters.get("text_contains")
    if text:
        query_b = query_b.or_(f"title.ilike.%{text}%,summary.ilike.%{text}%")
    for col, val in (filters.get("field_eq") or {}).items():
        query_b = query_b.eq(col, val)
    for col, vals in (filters.get("field_in") or {}).items():
        if vals:
            query_b = query_b.in_(col, vals)

    resp_b = query_b.order(date_col, desc=True).limit(5000).execute()
    rows_b = resp_b.data or []
    count_b = len(rows_b)

    # 证据
    evidence_a = to_evidence(rows_a, source, limit=25)
    evidence_b = to_evidence(rows_b, source, limit=25)

    # 变化率
    if count_b == 0:
        change_rate = 1.0 if count_a > 0 else 0.0
    else:
        change_rate = round((count_a - count_b) / count_b, 4)

    if change_rate > 0.05:
        direction = "up"
    elif change_rate < -0.05:
        direction = "down"
    else:
        direction = "same"

    return {
        "period_a": {"label": period or f"{duration_days}d", "count": count_a},
        "period_b": {"label": f"prev_{b_duration}d", "count": count_b},
        "diff": count_a - count_b,
        "change_rate": change_rate,
        "direction": direction,
    }, evidence_a + evidence_b
