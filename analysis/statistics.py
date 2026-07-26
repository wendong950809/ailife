"""
Statistics - 统计能力
=====================
负责：统计数量。
支持简单计数和分组计数（如按正/负情绪、按 icon 分组）。
"""

from ._utils import build_query, to_evidence


def count(client, table: str, source: str, filters: dict, period):
    """
    简单计数：返回匹配条件的记录总数。

    返回:
        result: {"count": int}
        evidence: 证据列表（最多返回 50 条摘要）
    """
    query = build_query(client, table, filters, period)
    response = query.order(
        "occurred_at" if table == "timeline" else "created_at", desc=True
    ).limit(500).execute()

    rows = response.data or []
    evidence = to_evidence(rows, source)

    return {"count": len(rows)}, evidence


def statistics(
    client, table: str, source: str, filters: dict, period,
    group_by: str = None, **kwargs
):
    """
    分组统计：按指定字段分组计数。

    参数:
        group_by: 分组字段名 (如 "icon", "event_source", "time_precision")

    返回:
        result: {"total": int, "groups": {"icon_value": count, ...}}
        evidence: 证据列表
    """
    query = build_query(client, table, filters, period)
    response = query.order(
        "occurred_at" if table == "timeline" else "created_at", desc=True
    ).limit(1000).execute()

    rows = response.data or []
    evidence = to_evidence(rows, source)

    if group_by:
        groups = {}
        for row in rows:
            key = str(row.get(group_by, "unknown"))
            groups[key] = groups.get(key, 0) + 1
        return {"total": len(rows), "groups": groups, "group_by": group_by}, evidence

    return {"total": len(rows)}, evidence
