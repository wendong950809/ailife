"""
Streak - 连续性能力
====================
负责：计算事件的最长连续天数和当前连续天数。
只看日期（年月日），不看具体时间。
"""

from datetime import datetime, timedelta, timezone
from ._utils import build_query, to_evidence, parse_period, china_now, CHINA_TZ


def streak(
    client, table: str, source: str, filters: dict, period,
    **kwargs
):
    """
    计算连续性。

    返回:
        result: {
            "current_streak": int,   # 当前连续天数（到今天为止）
            "longest_streak": int,   # 历史最长连续天数
            "total_active_days": int, # 有记录的总天数
            "last_active_date": str | None,  # 最近一次记录日期
        }
        evidence: 证据列表
    """
    query = build_query(client, table, filters, period)
    date_col = "occurred_at" if table == "timeline" else "created_at"
    response = query.order(date_col, desc=False).limit(10000).execute()

    rows = response.data or []
    evidence = to_evidence(rows, source, limit=30)

    # 提取所有有记录的日期（去重，只保留年月日）
    active_dates = set()
    for row in rows:
        dt_str = row.get(date_col)
        if not dt_str:
            continue
        try:
            dt = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            dt_china = dt.astimezone(CHINA_TZ)
            active_dates.add(dt_china.date())
        except Exception:
            continue

    if not active_dates:
        return {
            "current_streak": 0,
            "longest_streak": 0,
            "total_active_days": 0,
            "last_active_date": None,
        }, evidence

    sorted_dates = sorted(active_dates)
    today = china_now().date()
    last_date = sorted_dates[-1]

    # 计算当前连续天数（从最后记录日往前数）
    current_streak = 0
    check_date = last_date
    while check_date in active_dates:
        current_streak += 1
        check_date -= timedelta(days=1)

    # 如果最后记录不是今天也不是昨天，当前连续为 0
    if (today - last_date).days > 1:
        current_streak = 0

    # 计算最长连续天数
    longest_streak = 0
    temp_streak = 1
    for i in range(1, len(sorted_dates)):
        if (sorted_dates[i] - sorted_dates[i - 1]).days == 1:
            temp_streak += 1
        else:
            longest_streak = max(longest_streak, temp_streak)
            temp_streak = 1
    longest_streak = max(longest_streak, temp_streak)

    return {
        "current_streak": current_streak,
        "longest_streak": longest_streak,
        "total_active_days": len(active_dates),
        "last_active_date": last_date.strftime("%Y-%m-%d"),
    }, evidence
