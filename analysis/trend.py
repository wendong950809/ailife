"""
Trend - 趋势能力
=================
负责：计算事件随时间的变化趋势。
返回：up / down / stable + 详细分时段数据。
"""

from datetime import datetime, timedelta, timezone
from ._utils import build_query, to_evidence, parse_period, china_now, CHINA_TZ


def trend(
    client, table: str, source: str, filters: dict, period,
    metric: str = None, buckets: int = 4, **kwargs
):
    """
    计算变化趋势。

    参数:
        metric:  指标名（用于标识，不影响计算逻辑）
        buckets: 将时间范围分为几段来比较趋势 (默认 4 段)

    返回:
        result: {
            "trend": "up" | "down" | "stable",
            "metric": str | None,
            "buckets": [{"label": "Q1", "count": int}, ...],
            "change_rate": float,   # 首尾变化率 (如 0.35 = +35%)
        }
        evidence: 证据列表
    """
    start = parse_period(period)
    if start is None:
        # 无 period 默认取最近 180 天
        start = china_now() - timedelta(days=180)

    now = china_now()
    total_days = max((now - start).days, 1)
    bucket_days = total_days / buckets

    query = build_query(client, table, filters, period)
    date_col = "occurred_at" if table == "timeline" else "created_at"
    response = query.order(date_col, desc=False).limit(5000).execute()

    rows = response.data or []
    evidence = to_evidence(rows, source)

    # 按时间分桶计数
    bucket_counts = [0] * buckets
    for row in rows:
        dt_str = row.get(date_col)
        if not dt_str:
            continue
        try:
            dt = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            dt_china = dt.astimezone(CHINA_TZ)
            days_from_start = (dt_china - start).days
            idx = int(days_from_start / bucket_days)
            if 0 <= idx < buckets:
                bucket_counts[idx] += 1
        except Exception:
            continue

    # 构建分桶标签
    bucket_labels = []
    for i in range(buckets):
        bucket_start = start + timedelta(days=i * bucket_days)
        bucket_labels.append({
            "label": f"T{i+1}",
            "range_start": bucket_start.strftime("%Y-%m-%d"),
            "count": bucket_counts[i],
        })

    # 计算趋势：比较前半段和后半段
    first_half = sum(bucket_counts[:buckets // 2])
    second_half = sum(bucket_counts[buckets // 2:])

    if first_half == 0 and second_half == 0:
        trend_str = "stable"
        change_rate = 0.0
    elif first_half == 0:
        trend_str = "up"
        change_rate = 1.0
    else:
        change_rate = round((second_half - first_half) / first_half, 4)
        if change_rate > 0.15:
            trend_str = "up"
        elif change_rate < -0.15:
            trend_str = "down"
        else:
            trend_str = "stable"

    return {
        "trend": trend_str,
        "metric": metric,
        "buckets": bucket_labels,
        "change_rate": change_rate,
    }, evidence
