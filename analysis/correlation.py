"""
Correlation - 相关性能力
=========================
负责：计算两个指标（事件集合）在时间上的共现相关程度。
返回：相关系数 (-1.0 ~ 1.0)，仅返回数值，不解释原因。

算法:
  将时间按天分桶，统计指标 A 和指标 B 每天各自的出现次数。
  用皮尔逊相关系数衡量两个日序列的线性相关程度。
"""

from datetime import datetime, timedelta, timezone
from ._utils import build_query, parse_period, china_now, to_china_iso, CHINA_TZ


def correlation(
    client, table: str, source: str, filters: dict, period,
    metric, metric_b, **kwargs
):
    """
    计算两个指标的相关性。

    参数:
        metric:   指标 A 的文本过滤词 (如 "开心")
        metric_b: 指标 B 的文本过滤词 (如 "陪孩子")

    返回:
        result: {
            "metric_a": str,
            "metric_b": str,
            "correlation": float,   # -1.0 ~ 1.0
            "strength": str,        # "strong" / "moderate" / "weak" / "none"
            "direction": str,       # "positive" / "negative" / "neutral"
            "co_occurrence_days": int,  # 两个指标在同一天都出现的次数
            "total_days": int,          # 时间跨度总天数
        }
        evidence: 证据列表
    """
    if not metric or not metric_b:
        return {
            "metric_a": metric,
            "metric_b": metric_b,
            "correlation": 0.0,
            "strength": "none",
            "direction": "neutral",
            "co_occurrence_days": 0,
            "total_days": 0,
        }, []

    start = parse_period(period)
    if start is None:
        start = china_now() - timedelta(days=180)

    now = china_now()
    total_days = max((now - start).days, 1)

    date_col = "occurred_at" if table == "timeline" else "created_at"

    # 查询指标 A 的所有记录
    filters_a = dict(filters)
    filters_a["text_contains"] = metric
    rows_a = _fetch_rows(client, table, filters_a, period, date_col)

    # 查询指标 B 的所有记录
    filters_b = dict(filters)
    filters_b["text_contains"] = metric_b
    rows_b = _fetch_rows(client, table, filters_b, period, date_col)

    # 按天分桶
    days_a = _to_daily_counts(rows_a, date_col, start, now, total_days)
    days_b = _to_daily_counts(rows_b, date_col, start, now, total_days)

    # 计算皮尔逊相关系数
    correlation_value = _pearson(days_a, days_b)

    # 共现天数
    co_occurrence = sum(1 for a, b in zip(days_a, days_b) if a > 0 and b > 0)

    # 强度判断
    abs_corr = abs(correlation_value)
    if abs_corr >= 0.7:
        strength = "strong"
    elif abs_corr >= 0.4:
        strength = "moderate"
    elif abs_corr >= 0.2:
        strength = "weak"
    else:
        strength = "none"

    if correlation_value > 0.1:
        direction = "positive"
    elif correlation_value < -0.1:
        direction = "negative"
    else:
        direction = "neutral"

    # 证据（合并 A 和 B 的部分记录）
    evidence = []
    for row in rows_a[:15]:
        evidence.append({
            "source": source,
            "id": row.get("id"),
            "title": row.get("title") or "",
            "metric": metric,
            "occurred_at": to_china_iso(row.get(date_col)),
        })
    for row in rows_b[:15]:
        evidence.append({
            "source": source,
            "id": row.get("id"),
            "title": row.get("title") or "",
            "metric": metric_b,
            "occurred_at": to_china_iso(row.get(date_col)),
        })

    return {
        "metric_a": metric,
        "metric_b": metric_b,
        "correlation": round(correlation_value, 4),
        "strength": strength,
        "direction": direction,
        "co_occurrence_days": co_occurrence,
        "total_days": total_days,
    }, evidence


def _fetch_rows(client, table, filters, period, date_col):
    """执行查询并返回行列表。"""
    query = build_query(client, table, filters, period)
    response = query.order(date_col, desc=False).limit(5000).execute()
    return response.data or []


def _to_daily_counts(rows, date_col, start, now, total_days):
    """将记录转为按天的计数序列。"""
    counts = [0] * total_days
    for row in rows:
        dt_str = row.get(date_col)
        if not dt_str:
            continue
        try:
            dt = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            dt_china = dt.astimezone(CHINA_TZ)
            day_idx = (dt_china - start).days
            if 0 <= day_idx < total_days:
                counts[day_idx] += 1
        except Exception:
            continue
    return counts


def _pearson(x: list, y: list) -> float:
    """皮尔逊相关系数。"""
    n = len(x)
    if n != len(y) or n == 0:
        return 0.0

    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))
    sum_x2 = sum(xi * xi for xi in x)
    sum_y2 = sum(yi * yi for yi in y)

    numerator = n * sum_xy - sum_x * sum_y
    denominator = (
        (n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y)
    ) ** 0.5

    if denominator == 0:
        return 0.0

    return numerator / denominator


def to_china_iso(dt_str):
    """转为中国时区 ISO 字符串。"""
    if not dt_str:
        return None
    try:
        dt = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(CHINA_TZ).strftime("%Y-%m-%dT%H:%M:%S+08:00")
    except Exception:
        return str(dt_str)
