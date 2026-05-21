# Multi-model configuration

Azure SRE Agent can run the same workflow against different model providers. For this lab, declare the provider in subagent YAML with `spec.modelProvider`.

## Provider field

```yaml
spec:
  name: review-autonomy-handler-aoai
  modelProvider: AzureOpenAI
```

Supported values for this lab:

- `AzureOpenAI`
- `AnthropicClaude`

## When to pick which

| Provider | Best fit | Why |
|---|---|---|
| `AzureOpenAI` | EU data boundary needs, structured output, high-volume operational tasks | Good fit for fast tool execution, approval packages, and cost-sensitive scheduled work. |
| `AnthropicClaude` | Deep reasoning, long-context incident analysis, richer narrative explanations | Strong fit for exploratory investigations, code-heavy correlation, and comparison demos. |

## A/B testing pattern

The safest way to compare providers is to deploy the **same** subagent twice:

1. Keep the prompt, tools, hooks, and autonomy the same.
2. Change only `spec.name` and `spec.modelProvider`.
3. Invoke both with the same incident prompt.
4. Compare latency, AAU consumption, reasoning style, and remediation quality.

Recommended names for this module:

- `review-autonomy-handler-aoai`
- `review-autonomy-handler-claude`

## Sample YAML examples

```yaml
api_version: azuresre.ai/v1
kind: AgentConfiguration
spec:
  name: review-autonomy-handler-aoai
  modelProvider: AzureOpenAI
  autonomy_mode: Review
  access_level: High
  agent_type: Autonomous
```

```yaml
api_version: azuresre.ai/v1
kind: AgentConfiguration
spec:
  name: review-autonomy-handler-claude
  modelProvider: AnthropicClaude
  autonomy_mode: Review
  access_level: High
  agent_type: Autonomous
```

## Practical guidance

- Use **one provider per benchmark run**; do not compare different prompts.
- Keep hooks identical so safety does not skew the results.
- Capture both **AAU** and **response time**; cheap but slow is not always better.
- Use `scripts\compare-models.ps1` to run the same prompt against both variants and save the raw responses locally.
