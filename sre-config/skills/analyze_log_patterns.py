from __future__ import annotations

import json
import math
import re
from collections import Counter
from datetime import datetime, timezone
from statistics import mean, pstdev
from typing import Any

try:
    import numpy as np
except Exception:  # pragma: no cover - dependency fallback
    np = None

try:
    from sklearn.ensemble import IsolationForest
except Exception:  # pragma: no cover - dependency fallback
    IsolationForest = None

TIMESTAMP_PATTERNS = [
    re.compile(r'(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)'),
    re.compile(r'(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)'),
    re.compile(r'(?P<ts>\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2})'),
]
MESSAGE_KEYS = [
    'message',
    'Message',
    'log',
    'LogMessage',
    'LogEntry',
    'RenderedDescription',
    'renderedMessage',
    'details',
    'RawData',
    'line',
]
TIMESTAMP_KEYS = ['TimeGenerated', 'timeGenerated', 'timestamp', 'Timestamp', 'time', 'Time']
SEVERITY_TERMS = {
    'critical': 4.0,
    'fatal': 4.0,
    'panic': 4.0,
    'oom': 4.0,
    'error': 3.0,
    'exception': 3.0,
    'timeout': 3.0,
    'throttl': 3.0,
    '429': 3.0,
    '5xx': 3.0,
    'warn': 2.0,
    'failed': 2.0,
}


def _parse_timestamp(value: Any) -> str | None:
    if value is None:
        return None

    text = str(value).strip()
    if not text:
        return None

    candidates = [text]
    if text.endswith('Z'):
        candidates.append(text[:-1] + '+00:00')

    for candidate in candidates:
        try:
            dt = datetime.fromisoformat(candidate)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')
        except ValueError:
            pass

    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M:%S.%f', '%m/%d/%Y %H:%M:%S'):
        try:
            dt = datetime.strptime(text, fmt).replace(tzinfo=timezone.utc)
            return dt.isoformat().replace('+00:00', 'Z')
        except ValueError:
            continue

    return None


def _extract_timestamp_from_line(line: str) -> str | None:
    for pattern in TIMESTAMP_PATTERNS:
        match = pattern.search(line)
        if match:
            parsed = _parse_timestamp(match.group('ts'))
            if parsed:
                return parsed
    return None


def _normalize_template(message: str) -> str:
    template = message.lower()
    for pattern in TIMESTAMP_PATTERNS:
        template = pattern.sub('<timestamp>', template)
    template = re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', '<ip>', template)
    template = re.sub(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<guid>', template, flags=re.IGNORECASE)
    template = re.sub(r'0x[0-9a-f]+', '<hex>', template, flags=re.IGNORECASE)
    template = re.sub(r'\b\d+\b', '<num>', template)
    template = re.sub(r'\s+', ' ', template).strip()
    return template


def _severity_weight(message: str) -> tuple[float, int]:
    lowered = message.lower()
    total = 0.0
    hits = 0
    for term, weight in SEVERITY_TERMS.items():
        if term in lowered:
            total += weight
            hits += 1
    return total, hits


def _rows_from_kql_result(payload: dict[str, Any]) -> list[dict[str, Any]]:
    tables = payload.get('tables')
    if not isinstance(tables, list):
        return []

    rows: list[dict[str, Any]] = []
    for table in tables:
        columns = [column.get('name') for column in table.get('columns', []) if isinstance(column, dict)]
        for row in table.get('rows', []):
            if isinstance(row, dict):
                rows.append(row)
                continue
            if isinstance(row, list):
                mapped = {}
                for index, column_name in enumerate(columns):
                    mapped[column_name] = row[index] if index < len(row) else None
                rows.append(mapped)
    return rows


def _coerce_records(payload: Any) -> list[Any]:
    if payload is None:
        return []

    if isinstance(payload, str):
        stripped = payload.strip()
        if not stripped:
            return []
        if stripped.startswith('{') or stripped.startswith('['):
            try:
                decoded = json.loads(stripped)
                return _coerce_records(decoded)
            except json.JSONDecodeError:
                pass
        return [line for line in payload.splitlines() if line.strip()]

    if isinstance(payload, dict):
        kql_rows = _rows_from_kql_result(payload)
        if kql_rows:
            return kql_rows
        return [payload]

    if isinstance(payload, list):
        records: list[Any] = []
        for item in payload:
            records.extend(_coerce_records(item))
        return records

    return [str(payload)]


def _record_to_entry(record: Any) -> dict[str, Any] | None:
    if isinstance(record, str):
        line = record.strip()
        if not line:
            return None
        timestamp = _extract_timestamp_from_line(line)
    elif isinstance(record, dict):
        timestamp = None
        for key in TIMESTAMP_KEYS:
            if key in record:
                timestamp = _parse_timestamp(record.get(key))
                if timestamp:
                    break

        line = ''
        for key in MESSAGE_KEYS:
            value = record.get(key)
            if value:
                line = str(value).strip()
                break

        if not line:
            values = [str(value).strip() for value in record.values() if value not in (None, '')]
            line = ' | '.join(values)

        if not line:
            return None

        if not timestamp:
            timestamp = _extract_timestamp_from_line(line)
    else:
        line = str(record).strip()
        if not line:
            return None
        timestamp = _extract_timestamp_from_line(line)

    severity_weight, severity_hits = _severity_weight(line)
    return {
        'timestamp': timestamp,
        'line': line,
        'template': _normalize_template(line),
        'severity_weight': severity_weight,
        'severity_hits': severity_hits,
        'length': len(line),
    }


def _build_reason(entry: dict[str, Any], template_count: int, rarity_score: float, length_z: float, method: str) -> str:
    reasons: list[str] = []

    if template_count <= 2:
        reasons.append(f'Only {template_count} log line(s) matched this template in the provided batch.')
    elif rarity_score >= 1.5:
        reasons.append('The template frequency is significantly lower than the batch average.')

    if entry['severity_weight'] >= 3:
        reasons.append('The message contains high-severity terms such as error, timeout, OOM, or critical.')

    if length_z >= 2:
        reasons.append('The message length deviates sharply from the surrounding log distribution.')

    if method == 'IsolationForest':
        reasons.append('IsolationForest classified the line as an outlier against the batch feature set.')
    else:
        reasons.append('A deterministic rarity and severity score marked the line as anomalous.')

    return ' '.join(reasons[:3])


def main(args: dict[str, Any]) -> dict[str, Any]:
    payload = args.get('log_lines')
    window_minutes = int(args.get('window_minutes', 15) or 15)

    raw_records = _coerce_records(payload)
    entries = [entry for entry in (_record_to_entry(record) for record in raw_records) if entry]

    if not entries:
        return {
            'analysis_method': 'none',
            'window_minutes': window_minutes,
            'analyzed_lines': 0,
            'anomalies': [],
            'message': 'No log lines were supplied or no parsable records were found.',
        }

    template_counts = Counter(entry['template'] for entry in entries)
    template_frequency_values = list(template_counts.values())
    template_frequency_mean = mean(template_frequency_values)
    template_frequency_std = pstdev(template_frequency_values) if len(template_frequency_values) > 1 else 0.0

    lengths = [entry['length'] for entry in entries]
    length_mean = mean(lengths)
    length_std = pstdev(lengths) if len(lengths) > 1 else 0.0

    rarity_scores: list[float] = []
    length_z_scores: list[float] = []
    feature_rows: list[list[float]] = []

    for entry in entries:
        template_count = template_counts[entry['template']]
        rarity_score = 0.0
        if template_frequency_std > 0:
            rarity_score = max(0.0, (template_frequency_mean - template_count) / template_frequency_std)
        length_z = 0.0
        if length_std > 0:
            length_z = abs(entry['length'] - length_mean) / length_std

        rarity_scores.append(rarity_score)
        length_z_scores.append(length_z)
        feature_rows.append([
            float(template_count),
            float(entry['length']),
            float(entry['severity_weight']),
            float(entry['severity_hits']),
            float(length_z),
        ])

    method = 'z-score'
    base_scores: list[float] = []

    if IsolationForest is not None and np is not None and len(entries) >= 15:
        model = IsolationForest(
            contamination=min(0.2, max(5 / len(entries), 0.05)),
            n_estimators=200,
            random_state=42,
        )
        matrix = np.asarray(feature_rows, dtype=float)
        isolation_scores = -model.fit(matrix).decision_function(matrix)
        base_scores = isolation_scores.tolist()
        method = 'IsolationForest'
    else:
        for index, entry in enumerate(entries):
            score = rarity_scores[index] + (entry['severity_weight'] * 0.35) + (entry['severity_hits'] * 0.15) + (length_z_scores[index] * 0.1)
            base_scores.append(score)

    scored_entries = []
    for index, entry in enumerate(entries):
        composite_score = base_scores[index] + (rarity_scores[index] * 0.3) + (entry['severity_weight'] * 0.1)
        template_count = template_counts[entry['template']]
        scored_entries.append({
            'timestamp': entry['timestamp'],
            'log_line': entry['line'],
            'template': entry['template'],
            'score': round(composite_score, 4),
            'reason': _build_reason(entry, template_count, rarity_scores[index], length_z_scores[index], method),
        })

    scored_entries.sort(key=lambda item: item['score'], reverse=True)

    return {
        'analysis_method': method,
        'window_minutes': window_minutes,
        'analyzed_lines': len(entries),
        'distinct_templates': len(template_counts),
        'anomalies': scored_entries[:5],
    }