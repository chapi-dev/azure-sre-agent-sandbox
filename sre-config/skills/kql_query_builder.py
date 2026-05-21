from __future__ import annotations

import re
from typing import Any

TIME_PATTERNS = [
    (re.compile(r'last\s+(\d+)\s*(minute|minutes|min)'), lambda match: f"{match.group(1)}m"),
    (re.compile(r'last\s+(\d+)\s*(hour|hours|hr|hrs)'), lambda match: f"{match.group(1)}h"),
    (re.compile(r'last\s+(\d+)\s*(day|days)'), lambda match: f"{match.group(1)}d"),
]
SERVICE_PATTERN = re.compile(r'\b([a-z0-9-]+-service)\b')
POD_PATTERN = re.compile(r'\bpod\s+([a-z0-9-]+)\b')
CONTAINER_PATTERN = re.compile(r'\bcontainer\s+([a-z0-9-]+)\b')
NODE_PATTERN = re.compile(r'\bnode\s+([a-z0-9-]+)\b')
NAMESPACE_PATTERNS = [
    re.compile(r'\bin\s+([a-z0-9-]+)\s+namespace\b'),
    re.compile(r'\bnamespace\s+([a-z0-9-]+)\b'),
    re.compile(r'\bns\s+([a-z0-9-]+)\b'),
]


def _parse_timeframe(intent: str) -> tuple[str, str]:
    lowered = intent.lower()
    for pattern, formatter in TIME_PATTERNS:
        match = pattern.search(lowered)
        if match:
            timeframe = formatter(match)
            return timeframe, f'Using the explicit time window from the prompt: {timeframe}.'
    if 'today' in lowered:
        return 'startofday(now())', 'Using a start-of-day filter because the prompt mentioned today.'
    if '24 hour' in lowered or 'last day' in lowered:
        return '24h', 'Using a 24-hour lookback based on the prompt.'
    return '1h', 'Defaulting to a 1-hour lookback because no explicit time range was provided.'


def _extract_filter(intent: str, patterns: list[re.Pattern[str]]) -> str | None:
    lowered = intent.lower()
    for pattern in patterns:
        match = pattern.search(lowered)
        if match:
            return match.group(1)
    return None


def _time_clause(timeframe: str) -> str:
    if timeframe == 'startofday(now())':
        return '| where TimeGenerated >= startofday(now())'
    return f'| where TimeGenerated > ago({timeframe})'


def _inventory_filters(namespace: str | None, service: str | None, pod: str | None, container: str | None, node: str | None) -> list[str]:
    filters: list[str] = []
    if namespace:
        filters.append(f"| where Namespace == '{namespace}'")
    if service:
        filters.append(f"| where PodName has '{service}' or ContainerName has '{service}'")
    if pod:
        filters.append(f"| where PodName == '{pod}'")
    if container:
        filters.append(f"| where ContainerName == '{container}'")
    if node:
        filters.append(f"| where Computer has '{node}'")
    return filters



def _event_filters(namespace: str | None, service: str | None, pod: str | None, node: str | None) -> list[str]:
    filters: list[str] = []
    if namespace:
        filters.append(f"| where Namespace == '{namespace}'")
    if service:
        filters.append(f"| where Name has '{service}' or Message has '{service}'")
    if pod:
        filters.append(f"| where Name has '{pod}' or Message has '{pod}'")
    if node:
        filters.append(f"| where Message has '{node}'")
    return filters



def _container_log_filters(namespace: str | None, service: str | None, pod: str | None, container: str | None, node: str | None) -> list[str]:
    filters: list[str] = []
    if namespace:
        filters.append(f"| where Name has '{namespace}' or LogEntry has '{namespace}'")
    if service:
        filters.append(f"| where Name has '{service}' or LogEntry has '{service}'")
    if pod:
        filters.append(f"| where Name has '{pod}'")
    if container:
        filters.append(f"| where Name has '{container}' or ContainerID has '{container}'")
    if node:
        filters.append(f"| where Computer has '{node}'")
    return filters



def _app_request_filters(service: str | None) -> list[str]:
    if service:
        return [f"| where AppRoleName has '{service}' or OperationName has '{service}'"]
    return []


def _build_query(intent: str, target_table: str, timeframe: str, namespace: str | None, service: str | None, pod: str | None, container: str | None, node: str | None) -> tuple[str, list[str]]:
    lowered = intent.lower()
    explanation = [f'Started from the requested target table `{target_table}`.']

    if target_table == 'KubePodInventory' or 'restart' in lowered:
        if target_table != 'KubePodInventory':
            explanation.append('Restart analysis maps best to KubePodInventory, so the query uses that table.')
        explanation.append('Looking for restart spikes by summarizing ContainerRestartCount.')
        query = [
            'let timeframeStart = ' + ('startofday(now());' if timeframe == 'startofday(now())' else f'ago({timeframe});'),
            'KubePodInventory',
            '| where TimeGenerated > timeframeStart',
            *_inventory_filters(namespace, service, pod, container, node),
            '| where ContainerRestartCount > 0',
            '| summarize LatestRestartCount=max(ContainerRestartCount), LastSeen=max(TimeGenerated) by Namespace, PodName, ContainerName, ClusterName',
            '| order by LatestRestartCount desc, LastSeen desc',
        ]
        return '\n'.join(query), explanation

    if target_table == 'KubeEvents' or any(keyword in lowered for keyword in ('oom', 'crashloop', 'backoff', 'evicted')):
        if target_table != 'KubeEvents':
            explanation.append('The incident keywords map best to Kubernetes events, so the query switches to KubeEvents.')
        reasons = ['OOMKilled', 'BackOff', 'CrashLoopBackOff', 'Evicted', 'Failed']
        query = [
            'KubeEvents',
            _time_clause(timeframe),
            *_event_filters(namespace, service, pod, node),
            f"| where Reason in ({', '.join([repr(reason) for reason in reasons])})",
            '| project TimeGenerated, Namespace, Name, Reason, Message, ClusterName',
            '| order by TimeGenerated desc',
        ]
        return '\n'.join(query), explanation

    if target_table == 'ContainerLog' or any(keyword in lowered for keyword in ('error', 'exception', 'timeout', 'log')):
        if target_table != 'ContainerLog':
            explanation.append('The prompt mentions logs/errors, so the query switches to ContainerLog.')
        else:
            explanation.append('The prompt mentions logs/errors, so the query searches error-oriented container log lines.')
        query = [
            'ContainerLog',
            _time_clause(timeframe),
            *_container_log_filters(namespace, service, pod, container, node),
            "| where LogEntry has_any ('error', 'exception', 'timeout', 'oom', 'throttl', 'failed')",
            '| project TimeGenerated, LogEntry, Computer, ContainerID, Image, Name',
            '| order by TimeGenerated desc',
        ]
        return '\n'.join(query), explanation

    if target_table == 'AppRequests' or any(keyword in lowered for keyword in ('latency', 'slow', 'duration', 'response time', '5xx')):
        if target_table != 'AppRequests':
            explanation.append('Latency and request-failure analysis maps best to AppRequests, so the query switches tables.')
        else:
            explanation.append('The prompt suggests request latency or request failures, so the query aggregates application requests.')
        query = [
            'AppRequests',
            _time_clause(timeframe),
            *_app_request_filters(service),
            "| summarize AvgDurationMs=avg(DurationMs), P95DurationMs=percentile(DurationMs, 95), FailureCount=countif(Success == false) by bin(TimeGenerated, 5m), OperationName, AppRoleName",
            '| order by TimeGenerated desc',
        ]
        return '\n'.join(query), explanation

    if target_table == 'InsightsMetrics' or any(keyword in lowered for keyword in ('cpu', 'memory', 'working set', 'usage')):
        if target_table != 'InsightsMetrics':
            explanation.append('The prompt references resource pressure, so the query switches to InsightsMetrics.')
        else:
            explanation.append('The prompt references resource pressure, so the query summarizes InsightsMetrics for CPU and memory trends.')
        metrics = ['cpuUsageNanoCores', 'memoryWorkingSetBytes', 'cpuLimitNanoCores', 'memoryLimitBytes']
        query = [
            'InsightsMetrics',
            _time_clause(timeframe),
            f"| where Name in ({', '.join([repr(metric) for metric in metrics])})",
            '| extend Namespace=tostring(Tags[\'k8sNamespace\']), PodName=tostring(Tags[\'podName\'])',
            *([f"| where Namespace == '{namespace}'"] if namespace else []),
            *([f"| where PodName has '{service}'"] if service else []),
            '| summarize AvgValue=avg(Val), MaxValue=max(Val) by Name, Namespace, PodName, bin(TimeGenerated, 5m)',
            '| order by TimeGenerated desc',
        ]
        return '\n'.join(query), explanation

    explanation.append('No specialized intent matched, so a generic starter query was generated for the selected table.')
    query = [
        f'{target_table}',
        _time_clause(timeframe),
        '| take 100',
    ]
    return '\n'.join(query), explanation


def main(args: dict[str, Any]) -> dict[str, Any]:
    natural_language_intent = str(args.get('natural_language_intent', '')).strip()
    target_table = str(args.get('target_table', '')).strip() or 'KubePodInventory'

    timeframe, timeframe_explanation = _parse_timeframe(natural_language_intent)
    namespace = _extract_filter(natural_language_intent, NAMESPACE_PATTERNS)
    service = _extract_filter(natural_language_intent, [SERVICE_PATTERN])
    pod = _extract_filter(natural_language_intent, [POD_PATTERN])
    container = _extract_filter(natural_language_intent, [CONTAINER_PATTERN])
    node = _extract_filter(natural_language_intent, [NODE_PATTERN])

    query, explanation = _build_query(
        natural_language_intent,
        target_table,
        timeframe,
        namespace,
        service,
        pod,
        container,
        node,
    )

    explanation.insert(0, timeframe_explanation)
    if namespace:
        explanation.append(f"Applied a namespace filter for `{namespace}`.")
    if service:
        explanation.append(f"Applied a service-oriented filter for `{service}`.")
    if pod:
        explanation.append(f"Applied a pod filter for `{pod}`.")
    if container:
        explanation.append(f"Applied a container filter for `{container}`.")
    if node:
        explanation.append(f"Applied a node filter for `{node}`.")

    return {
        'kql_query': query,
        'explanation': ' '.join(explanation),
    }