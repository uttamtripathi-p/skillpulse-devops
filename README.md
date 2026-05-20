# SkillPulse — Production DevOps Pipeline on AWS

> A 3-tier Go + React + MySQL application with a fully automated CI/CD pipeline, observability stack, and Infrastructure as Code.
> One `git push` → running update on AWS EC2 in under 2 minutes. No human pressing any button.

---

## What This Project Covers

- **CI/CD** — GitHub Actions pipeline (build → push → deploy)
- **Containerization** — Docker + Docker Compose (app stack + monitoring stack)
- **Kubernetes** — kind cluster with full manifest set + ArgoCD
- **IaC** — Terraform provisions AWS infrastructure (VPC, EC2, SG)
- **Config Management** — Ansible configures EC2
- **Observability** — Prometheus + Grafana + Loki + Promtail + Node Exporter
- **Secrets Management** — GitHub Secrets injected into EC2 at deploy time
- **Cost Control** — EC2 auto-start before deploy, auto-stop after

---

## Architecture

```
Developer
    │ git push → main
    ▼
┌─────────────────────┐
│   CI Workflow       │
│   - Build images    │
│   - Tag :sha+latest │
│   - Push Docker Hub │
└────────┬────────────┘
         │ workflow_run: success
         ▼
┌──────────────────────┐
│   CD Workflow        │
│   - Start EC2 (AWS)  │
│   - SSH into EC2     │
│   - git pull         │
│   - Inject secrets   │
│   - docker compose   │
│   - Stop EC2         │
└────────┬─────────────┘
         ▼
┌─────────────────────────────────────────────┐
│  AWS EC2 t3.medium — Ubuntu 22.04           │
│                                             │
│  App Stack          Monitoring Stack        │
│  ┌──────────┐       ┌────────────┐          │
│  │ frontend │:80    │ Prometheus │:9090      │
│  │ backend  │:8080  │ Grafana    │:3000      │
│  │ mysql    │:3306  │ Loki       │:3100      │
│  └──────────┘       │ Promtail   │           │
│                     │ Node Exp.  │:9100      │
│                     └────────────┘          │
└─────────────────────────────────────────────┘
```

---

## Prerequisites

Install these on your local machine before starting:

| Tool | Purpose | Install |
|---|---|---|
| Git | Version control | `sudo apt install git` |
| Docker + Docker Compose | Containerization | [docs.docker.com](https://docs.docker.com/engine/install/) |
| AWS CLI | Manage AWS resources | `pip install awscli` |
| Terraform | Provision infrastructure | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| Ansible | Configure EC2 | `pip install ansible` |
| kubectl | Kubernetes CLI | `sudo snap install kubectl --classic` |
| kind | Local Kubernetes cluster | `go install sigs.k8s.io/kind@latest` |
| make | Run Makefile targets | `sudo apt install make` |

---

## Step 1 — Fork and Clone

```bash
# Fork this repo on GitHub first, then:
git clone https://github.com/<your-username>/skillpulse-devops.git
cd skillpulse-devops
```

---

## Step 2 — Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region:        ap-south-1
# Default output format: json
```

Verify:
```bash
aws sts get-caller-identity
```

---

## Step 3 — Provision Infrastructure with Terraform

Terraform creates: VPC, public subnet, internet gateway, route table, security group, EC2 (t3.medium, Ubuntu 22.04).

```bash
cd terraform

# Review what will be created
terraform init
terraform plan -var-file=prod.tfvars

# Create infra
terraform apply -var-file=prod.tfvars -auto-approve
```

Or use the Makefile shortcut from the root:
```bash
make infra
```

After apply, note the output:
```
ec2_public_ip = "65.x.x.x"
```

---

## Step 4 — Configure EC2 with Ansible

Ansible installs Docker, Docker Compose, AWS CLI, and sets up the project directory on EC2.

**Update inventory first:**
```bash
# edit ansible/inventory.ini
[ec2]
65.x.x.x ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/your-key.pem
```

Then run:
```bash
make setup-ec2
# or directly:
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
```

---

## Step 5 — Set Up Docker Hub

1. Create account at [hub.docker.com](https://hub.docker.com)
2. Create two repositories:
   - `<username>/skillpulse-backend`
   - `<username>/skillpulse-frontend`
3. Generate a Personal Access Token:
   - Docker Hub → Account Settings → Security → New Access Token
   - Scope: **Read & Write**
   - Copy the token (shown only once)

---

## Step 6 — Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → Secrets tab**

| Secret Name | How to get it |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS Console → IAM → Your user → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Same as above |
| `EC2_INSTANCE_ID` | `aws ec2 describe-instances --region ap-south-1 --query "Reservations[].Instances[].[InstanceId]" --output text` |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | `cat ~/.ssh/your-key.pem` — paste entire contents |
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Token from Step 5 |
| `MYSQL_ROOT_PASSWORD` | Any strong password e.g. `rootpassword123` |
| `DB_NAME` | `skillpulse` |
| `DB_USER` | `skillpulse` |
| `DB_PASSWORD` | Any password e.g. `skillpulse123` |

---

## Step 7 — Add GitHub Variable

Go to repo → **Settings → Secrets and variables → Actions → Variables tab**

| Variable | Value |
|---|---|
| `DEPLOY_ENABLED` | `true` |

> Set to `false` to disable all deployments without touching pipeline code.

---

## Step 8 — Open EC2 Security Group Ports

AWS Console → EC2 → Security Groups → your SG → Inbound Rules → Add:

| Port | Purpose |
|---|---|
| 22 | SSH |
| 80 | Frontend |
| 3000 | Grafana |
| 9090 | Prometheus |
| 3100 | Loki |

> Terraform handles this automatically if you used `make infra`.

---

## Step 9 — Trigger the Pipeline

```bash
git commit --allow-empty -m "ci: trigger first deploy"
git push origin main
```

Watch at `https://github.com/<your-username>/skillpulse-devops/actions`:

- **CI** → builds + pushes images to Docker Hub (~1.5 min)
- **CD** → starts EC2, SSHes in, pulls images, starts all containers, stops EC2 (~2 min)

App is live at: `http://<your-ec2-ip>`

---

## Step 10 — Verify Everything is Running

SSH into EC2:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<ec2-ip>
cd ~/skillpulse-devops
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"
```

Expected:
```
NAMES           PORTS                     STATUS
frontend        0.0.0.0:80->80/tcp        Up
backend         8080/tcp                  Up
db              0.0.0.0:3306->3306/tcp    Up (healthy)
prometheus      0.0.0.0:9090->9090/tcp    Up
grafana         0.0.0.0:3000->3000/tcp    Up
loki            0.0.0.0:3100->3100/tcp    Up
promtail                                  Up
node-exporter   9100/tcp                  Up
```

---

## Access Points

| Service | URL |
|---|---|
| SkillPulse App | `http://<ec2-ip>` |
| Prometheus | `http://<ec2-ip>:9090` |
| Grafana | `http://<ec2-ip>:3000` (admin / admin) |
| Loki | `http://<ec2-ip>:3100` |

---

## Run Locally (Docker Compose)

```bash
cp .env.example .env        # fill in values
docker compose up -d --build
# App: http://localhost

docker compose -f docker-compose.monitoring.yml up -d
# Grafana:    http://localhost:3000
# Prometheus: http://localhost:9090

# Tear down
docker compose down -v
```

---

## Run on Kubernetes (kind)

Full local Kubernetes cluster with namespace, deployments, services, statefulset, PVC, and monitoring.

**Prerequisites:** Docker running, `kind` and `kubectl` installed.

```bash
# One-shot: build images, create cluster, load images, apply all manifests
make up

# App:        http://localhost:8888
# Prometheus: http://localhost:9090
# Grafana:    http://localhost:3000

# Tear down
make down
```

What `make up` runs internally:
```bash
docker build -t uttamtripathi/skillpulse-backend:latest  ./backend
docker build -t uttamtripathi/skillpulse-frontend:latest ./frontend
kind create cluster --config k8s/kind-config.yaml --name skillpulse
kind load docker-image uttamtripathi/skillpulse-backend:latest  --name skillpulse
kind load docker-image uttamtripathi/skillpulse-frontend:latest --name skillpulse
kubectl apply -f k8s/manifests/00-namespace.yaml \
              -f k8s/manifests/10-mysql.yaml \
              -f k8s/manifests/20-backend.yaml \
              -f k8s/manifests/30-frontend.yaml \
              -f k8s/manifests/40-monitoring.yaml
kubectl rollout status statefulset/mysql     -n skillpulse --timeout=180s
kubectl rollout status deployment/backend    -n skillpulse --timeout=120s
kubectl rollout status deployment/frontend   -n skillpulse --timeout=60s
kubectl rollout status deployment/prometheus -n skillpulse --timeout=60s
kubectl rollout status deployment/grafana    -n skillpulse --timeout=60s
kubectl rollout status deployment/loki       -n skillpulse --timeout=60s
```

### Makefile Commands

| Command | What it does |
|---|---|
| `make up` | Build + create cluster + apply all manifests |
| `make down` | Delete the kind cluster |
| `make build` | Build backend + frontend Docker images |
| `make load` | Load images into kind node |
| `make apply` | Apply all k8s manifests |
| `make restart` | Rebuild images + rolling restart deployments |
| `make status` | Show pods, services, endpoints |
| `make logs` | Tail logs from all workloads |
| `make mysql` | Open MySQL shell in StatefulSet pod |
| `make argocd-install` | Install ArgoCD into the cluster |
| `make argocd-password` | Get ArgoCD admin password |
| `make argocd-ui` | Port-forward ArgoCD UI to localhost:8081 |
| `make infra` | Terraform init + apply AWS infra |
| `make setup-ec2` | Run Ansible playbook on EC2 |
| `make deploy-ec2` | Manual deploy to EC2 (bypasses CI/CD) |

### Smoke Test

```bash
curl http://localhost:8888/health           # {"status":"healthy"}
curl http://localhost:8888/api/dashboard    # summary counters
curl -s http://localhost:8888/ | grep title # SkillPulse
```

---

## ArgoCD (GitOps)

```bash
# Install ArgoCD into kind cluster
make argocd-install

# Get admin password
make argocd-password

# Open UI at https://localhost:8081
make argocd-ui

# Apply the ArgoCD app manifest
kubectl apply -f k8s/argocd-app.yaml
```

ArgoCD watches the repo and auto-syncs manifest changes to the cluster.

---

## CI/CD Pipeline Details

### CI — `.github/workflows/ci.yml`

Trigger: every push to `main` (ignores `*.md`, `k8s/`, `docs/`)

```
1. Checkout code on clean Ubuntu runner
2. Login to Docker Hub using secrets
3. Build backend image  (multi-stage: golang:alpine → alpine)
4. Build frontend image (nginx:alpine)
5. Tag each image: :<commit-sha> + :latest
6. Push both images to Docker Hub
```

### CD — `.github/workflows/cd.yml`

Trigger: `workflow_run` on CI success + `DEPLOY_ENABLED == 'true'`

```
1. Configure AWS credentials
2. Check EC2 state → start if stopped → wait until running
3. Fetch Elastic IP
4. SSH into EC2
   ├── Clone repo if first deploy, else git pull
   ├── Inject all secrets into .env
   ├── docker network create skillpulse || true
   ├── docker compose pull + up -d --remove-orphans
   ├── docker compose -f docker-compose.monitoring.yml pull + up -d
   └── docker image prune -f
5. Stop EC2 (always runs — even on failure)
```

---

## Secrets Quick Reference

If you ever forget your secret values:

```bash
# EC2 instance ID
aws ec2 describe-instances --region ap-south-1 \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]" \
  --output table

# Current .env values on EC2
ssh -i ~/.ssh/your-key.pem ubuntu@<ec2-ip> "cat ~/skillpulse-devops/.env"

# AWS credentials on local
cat ~/.aws/credentials

# SSH key content for EC2_SSH_KEY secret
cat ~/.ssh/your-key.pem
```

---

## Project Layout

```
.
├── .github/workflows/
│   ├── ci.yml                     Build + push images on push to main
│   └── cd.yml                     Deploy to EC2 on CI success
├── backend/                       Go + Gin REST API
│   ├── Dockerfile                 Multi-stage build
│   ├── main.go
│   ├── database/db.go
│   └── handlers/                  skills, logs, dashboard endpoints
├── frontend/                      Static UI + Nginx reverse proxy
│   ├── Dockerfile
│   ├── nginx.conf                 Proxies /api/ to backend:8080
│   └── index.html, css/, js/
├── mysql/init.sql                 Schema + seed data
├── monitoring/
│   ├── prometheus.yml             Scrape configs
│   └── promtail-config.yml        Log shipping to Loki
├── docker-compose.yml             App stack: db, backend, frontend
├── docker-compose.monitoring.yml  Prometheus, Grafana, Loki, Promtail, Node Exporter
├── k8s/
│   ├── kind-config.yaml           3-node cluster (1 control-plane + 2 workers)
│   ├── argocd-app.yaml            ArgoCD Application manifest
│   └── manifests/
│       ├── 00-namespace.yaml
│       ├── 10-mysql.yaml          StatefulSet + PVC + headless Service
│       ├── 20-backend.yaml        Deployment + ClusterIP Service
│       ├── 30-frontend.yaml       Deployment + NodePort (30080)
│       └── 40-monitoring.yaml     Prometheus, Grafana, Loki
├── terraform/
│   ├── main.tf                    VPC, Subnet, IGW, SG, EC2
│   ├── variables.tf
│   ├── outputs.tf                 Prints EC2 public IP
│   ├── providers.tf
│   └── prod.tfvars
├── ansible/
│   ├── inventory.ini              EC2 IP + SSH key path
│   └── playbook.yml               Installs Docker, Docker Compose, AWS CLI
└── Makefile                       All shortcuts in one place
```

---

## API Reference

```
GET    /api/skills           List all skills + total hours
POST   /api/skills           Create a skill
GET    /api/skills/:id       Get one skill + its logs
DELETE /api/skills/:id       Delete skill (cascades logs)
POST   /api/skills/:id/log   Log a study session
GET    /api/dashboard        Summary counters
GET    /health               DB ping — used by Docker healthcheck
GET    /metrics              Prometheus metrics endpoint
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `make: command not found` on EC2 | Inline make target in cd.yml or `sudo apt install make` |
| CD skipped after CI passed | Set `DEPLOY_ENABLED = true` in repo Variables tab |
| `ERR_CONNECTION_REFUSED` on port 80 | Add port 80 to EC2 Security Group inbound rules |
| Backend/frontend containers not starting | `.env` missing DB vars — verify secret injection in cd.yml |
| EC2 SSH timeout in CD | EC2 not fully booted — increase `sleep` duration in CD workflow |
| Docker Hub push fails | Token expired — regenerate PAT and update `DOCKERHUB_TOKEN` secret |
| `terraform.tfstate` committed to repo | Add to `.gitignore` and run `git rm --cached terraform/terraform.tfstate` |

---

*Built during the TrainWithShubham GitHub Actions & Kubernetes Hackathon — 48 hours.*
