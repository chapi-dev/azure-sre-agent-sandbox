# Network and Connectivity Investigation Runbook

Diagnose and remediate network connectivity issues in the AKS cluster running the Movistar BSS application. Covers network policy blocks, service selector mismatches, and DNS resolution failures.

---

## Step 1: Identify the Network Issue

**Symptoms to look for:**
- Requests timing out between services
- Services returning connection refused errors
- Service endpoints list is empty
- Line activations not processing despite all pods being "Running"

| Symptom | Likely Cause | Jump To |
|---------|-------------|---------|
| Connection refused / timeout between pods | Network policy blocking traffic | Step 2A |
| Service has 0 endpoints, pods are Running | Selector mismatch on Service | Step 2B |
| DNS resolution failures | CoreDNS or service naming issue | Step 2C |
| External traffic cannot reach customer-portal | Ingress / LoadBalancer misconfiguration | Step 2D |

---

## Step 2A: Network Policy Block

**Symptoms:** Pods are Running and Ready, but inter-service communication fails

**Diagnostic steps:**
1. List network policies:
   ```bash
   kubectl get networkpolicies -n movistar
   ```
2. Inspect the blocking policy:
   ```bash
   kubectl describe networkpolicy <policy-name> -n movistar
   ```
3. Test connectivity between pods:
   ```bash
   kubectl exec <source-pod> -n movistar -- curl -s --connect-timeout 5 http://activation-service:3000/health
   ```
4. Check if the policy denies all ingress:
   ```bash
   kubectl get networkpolicy <policy-name> -n movistar -o jsonpath='{.spec.ingress}'
   ```

**Remediation:**
- Delete the blocking network policy:
  ```bash
  kubectl delete networkpolicy <policy-name> -n movistar
  ```
- Or apply the healthy baseline which removes scenario-injected policies:
  ```bash
  kubectl apply -f k8s/base/application.yaml
  ```

---

## Step 2B: Service Selector Mismatch

**Symptoms:** Service exists, pods are Running, but the Service has zero endpoints. Traffic to the service fails silently.

**Diagnostic steps:**
1. Check service endpoints:
   ```bash
   kubectl get endpoints activation-service -n movistar
   ```
2. Compare the Service selector to pod labels:
   ```bash
   kubectl get svc activation-service -n movistar -o jsonpath='{.spec.selector}'
   kubectl get pods -n movistar -l app=activation-service --show-labels
   ```
3. Look for label drift:
   ```bash
   kubectl get deployment activation-service -n movistar -o jsonpath='{.spec.template.metadata.labels}'
   kubectl get svc activation-service -n movistar -o yaml | grep activation-service-v2
   ```

**Key insight:** This is a *silent failure* — all pods appear healthy, but traffic never reaches them because the Service selector does not match the pod labels. In this scenario, the Service can drift to `app=activation-service-v2` while the deployment still labels pods as `app=activation-service`.

**Remediation:**
- Fix the Service selector to match pod labels
- Apply healthy baseline: `kubectl apply -f k8s/base/application.yaml`

---

## Step 2C: DNS Resolution

**Symptoms:** Services cannot resolve each other by name

**Diagnostic steps:**
1. Test DNS from inside a pod:
   ```bash
   kubectl exec <pod-name> -n movistar -- nslookup subscriber-db.movistar.svc.cluster.local
   ```
2. Check CoreDNS pods:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```
3. Check CoreDNS logs:
   ```bash
   kubectl logs -l k8s-app=kube-dns -n kube-system --tail=50
   ```

**Remediation:**
- Restart CoreDNS if it is unhealthy
- Verify Service names match what applications expect

---

## Step 2D: External Access Issues

**Symptoms:** External users cannot reach the customer-portal

**Diagnostic steps:**
1. Check the LoadBalancer service:
   ```bash
   kubectl get svc customer-portal -n movistar
   ```
2. Verify an external IP is assigned:
   ```bash
   kubectl get svc customer-portal -n movistar -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
3. Test external connectivity:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://<external-ip>
   ```

**Remediation:**
- Wait for the LoadBalancer IP to be provisioned
- Check NSG rules on the AKS subnet
- Verify the `customer-portal` pod is healthy and listening on the correct port

---

## Dependency Map

```
customer-portal ──→ activation-service ──→ subscriber-db
    │                     │
    └──→ catalog-service ──→ subscriber-db
                  │
                  └──→ provisioning-queue
                          │
               provisioning-service ──→ subscriber-db
```

When investigating connectivity issues, trace the dependency chain to determine which link is broken.
