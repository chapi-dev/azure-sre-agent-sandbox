from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any


def _to_decimal(value: Any, default: str = '0') -> Decimal:
    try:
        return Decimal(str(value))
    except Exception:
        return Decimal(default)


def _round_currency(value: Decimal) -> float:
    return float(value.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))


def main(args: dict[str, Any]) -> dict[str, Any]:
    downtime_minutes = max(_to_decimal(args.get('downtime_minutes')), Decimal('0'))
    affected_users = max(_to_decimal(args.get('affected_users')), Decimal('0'))
    arpu_per_hour = max(_to_decimal(args.get('arpu_per_hour', 20)), Decimal('0'))

    downtime_hours = downtime_minutes / Decimal('60')
    lost_revenue = downtime_hours * affected_users * arpu_per_hour
    sla_credits = lost_revenue * Decimal('0.25')
    productivity_loss = downtime_hours * affected_users * (arpu_per_hour * Decimal('0.15'))
    estimated_cost = lost_revenue + sla_credits + productivity_loss

    return {
        'downtime_minutes': int(downtime_minutes),
        'affected_users': int(affected_users),
        'arpu_per_hour': _round_currency(arpu_per_hour),
        'estimated_cost_usd': _round_currency(estimated_cost),
        'breakdown': {
            'lost_revenue_usd': _round_currency(lost_revenue),
            'sla_credits_usd': _round_currency(sla_credits),
            'productivity_loss_usd': _round_currency(productivity_loss),
        },
        'assumptions': {
            'sla_credit_rate': 0.25,
            'productivity_loss_rate': 0.15,
            'formula': 'lost_revenue + 25% SLA credits + 15% productivity loss proxy',
        },
    }