"""
Frequency - 频率能力
=====================
负责：计算事件在指定时间范围内的出现频率。
返回：每周/每天/每月的平均次数。
"""

from datetime import timedelta
from ._utils import build_query, to_evidence, parse_period, china_now


def frequency(
    client, table: str, source: str, filters: dict, period,
    unit: str = "week", **kwargs
):
    """
    计算出现频率。

    参数:
        unit: 频率单位 ("day" / "week" / "month")

    返回:
        result: {
            "total": int,          # 总次数
            "period_days": int,    # 时间跨度天数
            "per_day": float,      # 每天平均次数
            "per_week": float,     # 每周平均次数
            "per_month": float,    # 每月平均次数
            "unit": str,           # 主单位
            "value": float,        # 主单位的值
        }
        evidence: 证据列表
    """
    # 计算时间跨度
    start = parse_period(period)
    if start is not None:
        days = (china_now() - start).days
        if days <= 0:
            days = 1
    else:
        # 无时间范围时，用数据本身的跨度
        days = None

    query = build_query(client, table, filters, period)
    date_col = "occurred_at" if table == "timeline" else "created_at"
    response = query.order(date_col, desc=True).limit(2000).execute()

    rows = response.data or []
    total = len(rows)
    evidence = to_evidence(rows, source)

    # 如果没有指定 period，用数据首尾日期算跨度
    if days is None and rows:
        dates = []
        for row in rows:
            dt_str = row.get(date_col)
            if dt_str:
                dates.append(dt_str)
        if dates:
            dates.sort()
            from datetime import datetime, timezone, timedelta
            china_tz = timezone(timedelta(hours=8))
            try:
                earliest = datetime.fromisoformat(dates[0].replace("Z", "+00:00"))
                latest = datetime.fromisoformat(dates[-1].replace("Z", "+00:00"))
                days = max((latest - earliest).days, 1)
            except Exception:
                days = max(total, 1)
        else:
            days = max(total, 1)
    elif days is None:
        days = 1

    per_day = round(total / days, 2) if days > 0 else 0
    per_week = round(total / (days / 7), 2) if days > 0 else 0
    per_month = round(total / (days / 30), 2) if days > 0 else 0

    unit_map = {"day": per_day, "week": per_week, "month": per_month}
    primary_value = unit_map.get(unit, per_week)

    return {
        "total": total,
        "period_days": days,
        "per_day": per_day,
        "per_week": per_week,
        "per_month": per_month,
        "unit": unit,
        "value": primary_value,
    }, evidence
