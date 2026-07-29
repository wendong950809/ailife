"""
Search - 查询能力
=================
负责：从数据源中找数据，返回匹配的记录列表。
不做任何计算，只做过滤和返回。
"""

from ._utils import build_query, to_evidence


def search(client, table: str, source: str, filters: dict, period):
    """
    查询数据。

    返回:
        result: {"items": [...], "count": int}
        evidence: [{source, id, title, occurred_at}, ...]
    """
    query = build_query(client, table, filters, period)

    # 排序：timeline 按 occurred_at，其他按 created_at
    date_col = "occurred_at" if table == "timeline" else "created_at"
    response = query.order(date_col, desc=True).limit(200).execute()

    rows = response.data or []
    items = [_row_to_dict(row, source) for row in rows]
    evidence = to_evidence(rows, source)

    return {"items": items, "count": len(items)}, evidence


def _row_to_dict(row: dict, source: str) -> dict:
    """将数据库行转为输出 dict，去掉内部字段。"""
    result = dict(row)
    # 去掉 user_id 等敏感字段
    result.pop("user_id", None)
    result.pop("raw_content", None)
    return result
