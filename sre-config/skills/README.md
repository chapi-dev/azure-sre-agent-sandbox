# Skills for Module D

Skills are custom Python tools that the Azure SRE Agent can invoke during an investigation. They complement built-in tools by adding deterministic logic, custom calculations, and report generation that stay close to the SRE workflow.

## Files in this folder

| Skill | Purpose |
|------|---------|
| `analyze_log_patterns` | Flags anomalous log lines from raw logs or serialized KQL results |
| `cost_impact_estimator` | Estimates business impact from downtime, user count, and ARPU |
| `kql_query_builder` | Deterministically converts a natural-language prompt into starter KQL |
| `generate_incident_pdf` | Produces a base64-encoded PDF report with charts and recommendations |

## Registration model

Each skill is defined by a YAML manifest and a sibling Python entrypoint:

- YAML manifest: metadata, parameter schema, runtime, entrypoint
- Python file: `main(args: dict) -> dict`
- Shared dependencies: `requirements.txt`

`configure-sre-agent.ps1` should register these skills by calling:

```text
POST {agentEndpoint}/api/v2/extendedAgent/skills
```

The upload should be multipart and include:

1. The skill YAML file
2. The Python entrypoint file referenced by `entrypoint`
3. `requirements.txt` when dependencies are required

The companion script in this module, `scripts\upload-skills.ps1`, automates that flow.

## Invocation pattern

Once registered, the agent can invoke them like tools. Example references:

- `Skill: analyze-log-patterns`
- `Skill: cost-impact-estimator`
- `Skill: kql-query-builder`
- `Skill: generate-incident-pdf`

Example usage flow:

1. The agent analyzes recent logs with `analyze-log-patterns`
2. It estimates business impact with `cost-impact-estimator`
3. It builds a reusable investigation query with `kql-query-builder`
4. It assembles a customer-facing report with `generate-incident-pdf`

## Runtime dependencies

The Python runtime dependencies are pinned in `requirements.txt`:

- `scikit-learn` for anomaly detection
- `numpy` for numerical arrays used by the anomaly model
- `matplotlib` for incident trend charts
- `reportlab` for PDF assembly

All dependencies are standard pip-installable packages and should be uploaded with the skill bundle.