"""
Analysis Engine - AI Life OS 客观计算中心
=========================================
定位：只负责查询(Query)、统计(Statistics)、计算(Computation)。
永远不负责：AI推理、更新Memory、分类、做建议、做决策。它只返回数据。

设计原则：
1. 不含任何业务名词（wife/health/goal/work 等），只认识 source/operation/filters/period
2. 统一接口 execute(operation, source, filters, period, ...)
3. 统一返回格式 {success, operation, source, result, evidence, generated_at}
4. 直接查数据库，不持久化计算结果
5. 所有计算无状态、可复现
"""

import os
from typing import Optional

from ._utils import (
    parse_period, build_query, to_evidence,
    china_now as _china_now, china_now_iso as _china_now_iso,
    to_china_iso as _to_china_iso,
)
from .search import search
from .statistics import count, statistics
from .frequency import frequency
from .trend import trend
from .streak import streak
from .compare import compare
from .correlation import correlation

# 支持的数据源 -> 实际表名
_SOURCE_TABLE = {
    "timeline": "timeline",
    "facts": "extracted_facts",
    "messages": "messages",
    "memories": "memories",
    "daily_logs": "daily_logs",
}

# 支持的操作
_OPERATIONS = {
    "search", "count", "statistics", "frequency",
    "trend", "streak", "compare", "correlation",
}


class AnalysisEngine:
    """
    客观计算引擎。

    用法:
        engine = AnalysisEngine(supabase_url, supabase_key)
        result = engine.execute(
            operation="count",
            source="timeline",
            filters={"text_contains": "睡眠"},
            period="90d",
        )
    """

    def __init__(self, supabase_url: str, supabase_key: str):
        from supabase import create_client, Client
        self._client: Client = create_client(supabase_url, supabase_key)

    # ============================================
    # 统一入口
    # ============================================
    def execute(
        self,
        operation: str,
        source: str,
        filters: Optional[dict] = None,
        period: Optional[str] = None,
        metric: Optional[str] = None,
        **kwargs,
    ) -> dict:
        """
        统一计算接口。

        参数:
            operation: 操作类型 (search/count/statistics/frequency/trend/streak/compare/correlation)
            source:    数据源   (timeline/facts/messages/memories/daily_logs)
            filters:   查询条件，业务无关的通用过滤
                       {
                           "text_contains": "创业",   # title+summary 模糊匹配
                           "field_eq": {"icon": "🛌"}, # 字段精确匹配
                           "field_in": {"event_source": ["chat", "photo"]},
                       }
            period:    时间范围 ("90d" / "30d" / "180d" / "1y" / "1w" / "all")
            metric:    指标名，用于 trend / frequency 等 (如 "sleep")
            **kwargs:  操作特定参数 (如 compare 的 period_b, correlation 的 metric_b)

        返回:
            {
                "success": bool,
                "operation": str,
                "source": str,
                "result": dict,
                "evidence": list[dict],   # 证据，用于溯源
                "generated_at": str,      # ISO8601 中国时间
            }
        """
        operation = operation.lower().strip()
        source = source.lower().strip()

        # 校验
        if operation not in _OPERATIONS:
            return self._error(operation, source, f"未知操作: {operation}")
        if source not in _SOURCE_TABLE:
            return self._error(operation, source, f"未知数据源: {source}")

        table = _SOURCE_TABLE[source]
        filters = filters or {}

        try:
            if operation == "search":
                result, evidence = search(
                    self._client, table, source, filters, period
                )
            elif operation == "count":
                result, evidence = count(
                    self._client, table, source, filters, period
                )
            elif operation == "statistics":
                result, evidence = statistics(
                    self._client, table, source, filters, period, **kwargs
                )
            elif operation == "frequency":
                result, evidence = frequency(
                    self._client, table, source, filters, period, **kwargs
                )
            elif operation == "trend":
                result, evidence = trend(
                    self._client, table, source, filters, period, metric, **kwargs
                )
            elif operation == "streak":
                result, evidence = streak(
                    self._client, table, source, filters, period, **kwargs
                )
            elif operation == "compare":
                period_b = kwargs.pop("period_b", None)
                result, evidence = compare(
                    self._client, table, source, filters,
                    period, period_b, **kwargs
                )
            elif operation == "correlation":
                metric_b = kwargs.pop("metric_b", None)
                result, evidence = correlation(
                    self._client, table, source, filters, period,
                    metric, metric_b, **kwargs
                )
            else:
                return self._error(operation, source, f"操作未实现: {operation}")

            return self._success(operation, source, result, evidence)

        except Exception as e:
            return self._error(operation, source, str(e))

    # ============================================
    # 返回格式构造
    # ============================================
    @staticmethod
    def _success(operation, source, result, evidence) -> dict:
        return {
            "success": True,
            "operation": operation,
            "source": source,
            "result": result,
            "evidence": evidence,
            "generated_at": _china_now_iso(),
        }

    @staticmethod
    def _error(operation, source, message) -> dict:
        return {
            "success": False,
            "operation": operation,
            "source": source,
            "result": {"error": message},
            "evidence": [],
            "generated_at": _china_now_iso(),
        }


# ============================================
# 模块级便捷函数（用默认引擎实例）
# ============================================
_default_engine: Optional[AnalysisEngine] = None


def _get_default_engine() -> AnalysisEngine:
    global _default_engine
    if _default_engine is None:
        url = os.environ.get("SUPABASE_URL", "")
        key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not url or not key:
            raise RuntimeError(
                "需要设置 SUPABASE_URL 和 SUPABASE_SERVICE_ROLE_KEY 环境变量"
            )
        _default_engine = AnalysisEngine(url, key)
    return _default_engine


def execute(
    operation: str,
    source: str,
    filters: Optional[dict] = None,
    period: Optional[str] = None,
    metric: Optional[str] = None,
    **kwargs,
) -> dict:
    """模块级便捷调用，使用默认引擎实例。"""
    return _get_default_engine().execute(
        operation, source, filters, period, metric, **kwargs
    )
