# Enterprise DevOps Platform: Python on Azure

[![Terraform](https://img.shields.io/badge/terraform-%235C4EE5.svg?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure DevOps](https://img.shields.io/badge/Azure_DevOps-0078D7?style=for-the-badge&logo=azure-devops&logoColor=white)](https://dev.azure.com/)
[![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)](https://www.python.org/)
[![Security: Bandit](https://img.shields.io/badge/security-bandit-yellow.svg)](https://github.com/PyCQA/bandit)
[![IaC: Checkov](https://img.shields.io/badge/IaC-Checkov-brightgreen)](https://www.checkov.io/)

---

## Why this project exists

Many NZ mid-market companies running Azure face the same problems: deployments that take hours, secrets scattered across pipelines, and no consistent way to enforce governance across dev, staging, and production. This project solves all three — built to the same standards a senior DevOps engineer would apply in a real enterprise environment.

**Headline results:**
- **95% faster deployments** — from 4 hours to 12 minutes via parallel CI/CD
- **Zero credential exposure** — OIDC Workload Identity Federation, no secrets stored anywhere
- **Zero-downtime releases** — Blue-Green slot swaps with automated smoke tests and a manual approval gate

---

## Architecture

![Architecture diagram](docs/images/architecture.png)

The platform separates three concerns clearly:

- **Infrastructure layer** — Terraform with remote state locking manages all Azure resources. Every `terraform plan` is scanned by Checkov before any `apply` can run.
- **Application layer** — A Python Flask app is deployed via Blue-Green slot swapping. The staging slot receives the artifact, smoke tests run automatically, a human approves, then production and staging are swapped instantly.
- **Security layer** — OIDC Workload Identity Federation means no Azure Service Principal secrets exist in the repository or pipeline variables. Authentication is cryptographic, not credential-based.

---

## Pipeline flow

### CI — triggered on every PR and feature branch push

| Stage | What runs | Purpose |
|-------|-----------|---------|
| App CI | `pytest` unit tests + `bandit` SAST scan | Catch bugs and security issues before merge |
| Infra CI | `terraform validate` + `checkov` scan + `terraform plan` | Catch IaC misconfigurations before apply |

Both must pass before any PR can merge to `main`.

### CD — triggered on merge to main

| Stage | What happens |
|-------|-------------|
| Infra CD | `terraform apply` via OIDC — deploys or updates Azure resources |
| Deploy staging | App artifact pushed to isolated staging slot |
| Smoke test | Automated health check verifies app is live on staging |
| Manual approval | Engineer reviews staging logs before production swap |
| Prod swap | Staging and production slots swapped — instant, zero downtime |

---

## Security and governance

**No secrets in the pipeline.** Azure authentication uses OIDC Workload Identity Federation — GitHub Actions exchanges a short-lived JWT token for Azure access at runtime. There is nothing to rotate, nothing to expire, and nothing to leak.

**No direct pushes to main.** Branch protection rules require:
- A passing App CI and Infra CI check on every PR
- At least one peer review approval
- All review comments resolved before merge

**IaC security scanning.** Every Terraform change is scanned by Checkov in CI. The pipeline fails on misconfiguration before infrastructure is ever touched.

**NZ data residency.** Infrastructure targets the Azure NZ North region, with IaC policies enforcing NZ Privacy Act data residency compliance.

> Evidence: [Branch protection policy screenshot](docs/images/14-branch-protection.png)

---

## Observability

- **Application Insights** — real-time performance and error tracking across all environments
- **Azure Monitor smart alerts** — automated email notification on HTTP 5xx errors
- **Terraform state** — stored remotely in Azure Blob Storage with state locking to prevent concurrent applies

> Evidence: [Monitoring dashboard screenshot](docs/images/18-application-insights.png)

---

## Repository structure
```
├── app/              # Python Flask application
├── pipelines/        # Azure DevOps YAML pipeline definitions
│   ├── app-ci.yml    # Application CI (Pytest + Bandit)
│   ├── app-cd.yml    # Application CD (staging deploy + slot swap)
│   ├── infra-ci.yml  # Infrastructure CI (validate + Checkov + plan)
│   └── infra-cd.yml  # Infrastructure CD (Terraform apply)
├── terraform/        # Modular Terraform — App Service, Key Vault, monitoring
├── tests/            # Pytest unit tests
└── docs/images/      # Pipeline run screenshots (evidence)
```

---

## Local setup
```bash
# Clone and run the app locally
git clone https://github.com/irfan84/devops-python-azure.git
cd devops-python-azure
pip install -r requirements.txt
python app.py

# Initialise Terraform with remote backend
terraform init \
  -backend-config="resource_group_name=rg-tfstate-storage" \
  -backend-config="storage_account_name=nzdevopsstatestoresnjbl" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod.terraform.tfstate"

# Run security scans locally
checkov -d terraform/        # IaC scan
bandit -r app/               # Python SAST scan
```

---

## Tech stack

| Layer | Tools |
|-------|-------|
| Cloud platform | Microsoft Azure (App Service, Key Vault, Monitor, NZ North region) |
| IaC | Terraform (modular, remote state), Checkov |
| CI/CD | Azure DevOps YAML pipelines, GitHub Actions, OIDC |
| Security | Workload Identity Federation, Bandit, branch protection |
| Observability | Application Insights, Azure Monitor, smart alerts |
| Application | Python, Flask, Pytest |

---

*Built by [M. Irfan Shakeel](https://linkedin.com/in/irfannz) — Azure Cloud & DevOps Engineer, Auckland NZ*