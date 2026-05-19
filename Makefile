CLUSTER  ?= skillpulse
NAMESPACE ?= skillpulse
BACKEND_IMAGE  ?= uttamtripathi/skillpulse-backend:latest
FRONTEND_IMAGE ?= uttamtripathi/skillpulse-frontend:latest

.PHONY: up down build load apply status logs mysql restart argocd-install argocd-password argocd-ui

up: ## One-shot: build images, create cluster, load images, apply manifests
	$(MAKE) build
	kind create cluster --config k8s/kind-config.yaml --name $(CLUSTER)
	$(MAKE) load
	$(MAKE) apply
	@echo
	@echo "  SkillPulse is live at http://localhost:8888"
	@echo "  Prometheus is live at http://localhost:9090"
	@echo "  Grafana is live at    http://localhost:3000"
	@echo

build: ## Build backend + frontend images for the host's architecture
	docker build -t $(BACKEND_IMAGE)  ./backend
	docker build -t $(FRONTEND_IMAGE) ./frontend
push: ## Push images to Docker Hub
	docker push $(BACKEND_IMAGE)
	docker push $(FRONTEND_IMAGE)

load: ## Push built images into the kind node
	kind load docker-image $(BACKEND_IMAGE)  --name $(CLUSTER)
	kind load docker-image $(FRONTEND_IMAGE) --name $(CLUSTER)

apply: ## Apply manifests and wait for rollouts
	kubectl apply -f k8s/manifests/00-namespace.yaml \
	              -f k8s/manifests/10-mysql.yaml \
	              -f k8s/manifests/20-backend.yaml \
	              -f k8s/manifests/30-frontend.yaml \
	              -f k8s/manifests/40-monitoring.yaml
	kubectl rollout status statefulset/mysql    -n $(NAMESPACE) --timeout=180s
	kubectl rollout status deployment/backend   -n $(NAMESPACE) --timeout=120s
	kubectl rollout status deployment/frontend  -n $(NAMESPACE) --timeout=60s
	kubectl rollout status deployment/prometheus -n $(NAMESPACE) --timeout=60s
	kubectl rollout status deployment/grafana    -n $(NAMESPACE) --timeout=60s
	kubectl rollout status deployment/loki       -n $(NAMESPACE) --timeout=60s

down: ## Delete the cluster
	kind delete cluster --name $(CLUSTER)

status: ## Quick health snapshot
	@kubectl get pods,svc,endpoints -n $(NAMESPACE)

logs: ## Tail all three workloads at once
	@kubectl logs -n $(NAMESPACE) -l 'app in (mysql,backend,frontend,prometheus,grafana,loki)' --all-containers --tail=50 -f --max-log-requests=10

mysql: ## Open a mysql shell into the StatefulSet pod
	kubectl exec -it -n $(NAMESPACE) mysql-0 -- mysql -uskillpulse -pskillpulse123 skillpulse

restart: ## Rebuild + reload images, roll backend + frontend
	$(MAKE) build
	$(MAKE) load
	kubectl rollout restart deployment/backend deployment/frontend -n $(NAMESPACE)
	kubectl rollout status  deployment/backend  -n $(NAMESPACE) --timeout=120s
	kubectl rollout status  deployment/frontend -n $(NAMESPACE) --timeout=60s

argocd-install: ## Install ArgoCD into the cluster
	kubectl create namespace argocd || true
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
	@echo "Waiting for ArgoCD components to be ready..."
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

argocd-password: ## Get the initial admin password for ArgoCD
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

argocd-ui: ## Port-forward the ArgoCD UI to localhost:8081
	@echo "ArgoCD UI will be available at https://localhost:8081"
	kubectl port-forward svc/argocd-server -n argocd 8081:443
