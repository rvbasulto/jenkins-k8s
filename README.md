# Jenkins-K8S: CI/CD on Kubernetes (Minikube + VirtualBox)

This repository contains my end‑to‑end CI/CD lab running entirely on a local Kubernetes cluster using **Minikube (VirtualBox driver)**. It deploys and wires together **Jenkins**, **SonarQube (+ PostgreSQL)**, **Nexus Repository**, and a sample application (**vprofile**) using plain Kubernetes manifests.

My goal with this project is twofold: (1) practice real DevOps workflows on Kubernetes from scratch, and (2) have a clean, reproducible setup others can clone and run locally.

---

## TL;DR (Quick Start)

```bash
# 0) Requirements (Linux/macOS), see below for full list
# VirtualBox, kubectl, Minikube installed

# 1) Start Minikube with VirtualBox driver
minikube start --driver=virtualbox --cpus=4 --memory=8192 --disk-size=40g

# 2) Enable ingress controller
minikube addons enable ingress

# 3) (Optional) Wait for ingress to be ready
kubectl -n ingress-nginx get pods

# 4) Deploy everything in dependency-safe order
kubectl apply -f jenkins/
kubectl apply -f nexus/
kubectl apply -f sonarqube/postgres/
kubectl apply -f sonarqube/
kubectl apply -f vprofile/

# 5) Map local hosts (replace with your Minikube IP)
echo "$(minikube ip) jenkins.local nexus.local sonarqube.local vprofile.local" | sudo tee -a /etc/hosts

# 6) Verify ingresses
kubectl get ingress -n jenkins
# Open in browser:
#   http://jenkins.local
#   http://nexus.local
#   http://sonarqube.local
#   http://vprofile.local
```

---

## Architecture Overview

* **Kubernetes** (Minikube on VirtualBox) as the orchestration layer
* **Jenkins** for CI/CD (pipelines defined via `Jenkinsfile` in this repo)
* **SonarQube + PostgreSQL** for static code analysis and quality gates
* **Nexus Repository** for artifact and Docker image storage
* **vprofile** as demo application to deploy and validate the workflow
* **NGINX Ingress** for browser access via friendly hostnames

> Networking is handled with per‑app Ingress resources and services are ClusterIP. Everything runs in the `jenkins` namespace for simplicity.

## Project Context & Implementation Journey

I recently built a complete CI/CD pipeline running on a local Kubernetes cluster with **Minikube (VirtualBox driver)**. My goal was to strengthen two critical DevOps skills: (1) building and managing a robust CI/CD pipeline, and (2) designing and running infrastructure on Kubernetes in a way that resembles production.

### Step 1 – Environment Setup

I set up my local environment with Minikube (VirtualBox), installed `kubectl`, and created a dedicated namespace so all project resources stayed isolated.

### Step 2 – Jenkins Deployment

I deployed **Jenkins** using a Deployment and a Service. At first I exposed it via **NodePort**, then added an **Ingress** and a hostname (`jenkins.local`) for easier access. I also configured a **PersistentVolume** and **PersistentVolumeClaim** so Jenkins data would survive Pod restarts—because Pods are ephemeral in Kubernetes and I wanted a production‑like setup.

### Step 3 – Adding SonarQube and Nexus

Next, I deployed **SonarQube** (backed by **PostgreSQL**) and **Nexus Repository Manager**. Both were exposed through **Ingress** as `sonarqube.local` and `nexus.local`. With Jenkins (orchestration), SonarQube (code analysis), and Nexus (artifact & image storage), I had the core CI/CD toolchain ready.

### Step 4 – First Pipelines (Maven)

With the tools up, I created the first pipelines:

* Pull code from GitHub
* Build and test with Maven
* Run Checkstyle and SonarQube analysis
* Upload the `.war` artifact to Nexus

This is the classic flow: **code → build → analyze → store**.

### Step 5 – Multi‑JDK Support

I needed to test with **Java 11, 17, and 21**. Since the default Jenkins image only had JDK 21, I built a **custom Jenkins image** including all three JDKs and configured them in **Jenkins → Global Tool Configuration**. That let me run builds across multiple Java versions, as in a real enterprise environment.

### Step 6 – Moving to Docker Images

I moved beyond plain `.war` uploads and began building **Docker images** for Kubernetes deployments. The challenge was that Jenkins Pods did not have a Docker daemon. The solution was to run **Docker‑in‑Docker (DinD) as a sidecar** and install the Docker CLI in the Jenkins container so build commands could target the DinD daemon. This required small changes in the Jenkins Deployment manifest; after that I could build and tag images successfully.

### Step 7 – Pushing Docker Images to Nexus

I configured the pipeline to push Docker images to the **Nexus** registry. For traceability I implemented a tagging strategy including:

* Jenkins **build number**
* **Short commit** hash
* **Timestamp**

This made rollbacks and targeted deployments much easier.

### Step 8 – Deploying to Kubernetes from Jenkins

Finally, I had Jenkins deploy the app to Kubernetes. First, I baked **`kubectl`** into the Jenkins image. Second, I created a **ServiceAccount** and **ClusterRoleBinding** so the Jenkins Pod had the necessary permissions. With that in place, the pipeline could `kubectl apply -f vprofile/` and expose the app via an **Ingress** at `vprofile.local`.

> Manifests related to these steps can be found under `jenkins/`, `nexus/`, `sonarqube/` (and `sonarqube/postgres/`), and `vprofile/`. The RBAC pieces are in `jenkins/jenkins-rbac.yaml`, and the DinD sidecar & tool changes live in `jenkins/jenkins-deployment.yaml`.

---

## Repository Layout

```
JENKINS-K8S/
├─ jenkins/
│  ├─ jenkins-deployment.yaml
│  ├─ jenkins-service.yaml
│  ├─ jenkins-ingress.yaml
│  ├─ jenkins-pv.yaml
│  ├─ jenkins-pvc.yaml
│  └─ jenkins-rbac.yaml
├─ nexus/
│  ├─ nexus-configmap.yaml
│  ├─ nexus-deployment.yaml
│  ├─ nexus-service.yaml
│  └─ nexus-ingress.yaml
├─ sonarqube/
│  ├─ sonarqube-db-secret.yaml
│  ├─ sonarqube-deployment.yaml
│  ├─ sonarqube-service.yaml
│  ├─ sonarqube-ingress.yaml
│  └─ postgres/
│     ├─ sonarqube-postgres-deployment.yaml
│     ├─ sonarqube-postgres-service.yaml
│     └─ sonarqube-postgres-pvc.yaml
├─ vprofile/
│  ├─ vprofile-deployment.yaml
│  ├─ vprofile-service.yaml
│  └─ vprofile-ingress.yaml
├─ Dockerfile
├─ Jenkinsfile
└─ README.md (this file)
```

**Conventions**

* One resource per file (readable diffs, targeted applies)
* Consistent naming: `<app>-<resource>.yaml`
* Per‑app folders; SonarQube’s DB in its own `sonarqube/postgres` subfolder

---

## Prerequisites

* **OS**: Linux (recommended) or macOS
* **Virtualization**: VirtualBox installed
* **Kubernetes CLI**: `kubectl` ≥ 1.27
* **Minikube**: ≥ 1.32, with VirtualBox driver
* **Resources** (suggested): 4 vCPUs, 8 GB RAM, 40 GB disk for Minikube

> If you already have a Minikube profile, ensure it uses the `virtualbox` driver or create a new one.

---

## Step‑by‑Step Deployment

### 1) Start Minikube

```bash
minikube start --driver=virtualbox --cpus=4 --memory=8192 --disk-size=40g
```

### 2) Enable Ingress

```bash
minikube addons enable ingress
# Wait until all ingress-nginx pods are Ready
kubectl -n ingress-nginx get pods
```

### 3) Deploy components (order matters)

```bash
kubectl apply -f jenkins/
kubectl apply -f nexus/
kubectl apply -f sonarqube/postgres/
kubectl apply -f sonarqube/
kubectl apply -f vprofile/
```

### 4) Map hostnames

```bash
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP jenkins.local nexus.local sonarqube.local vprofile.local" | sudo tee -a /etc/hosts
```

### 5) Verify everything is up

```bash
kubectl get pods -n jenkins
kubectl get svc,ingress -n jenkins
```

Open in your browser:

* Jenkins → `http://jenkins.local`
* Nexus → `http://nexus.local`
* SonarQube → `http://sonarqube.local`
* vprofile → `http://vprofile.local`

---

## First‑Time Access & Default Credentials

> **Important**: These credentials are for local development only. Change them in real environments.

### Jenkins

* Retrieve initial admin password:

```bash
kubectl -n jenkins exec deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

* Then follow the setup wizard, install suggested plugins, and create your admin user.

**Global Tools (inside Jenkins container):**
If you need multiple JDKs for builds, configure them in **Manage Jenkins → Global Tool Configuration** using these paths (already available in my Jenkins image):

* JDK11 → `/opt/jdks/jdk-11`
* JDK17 → `/opt/jdks/jdk-17`
* JDK21 → `/opt/jdks/jdk-21`

Also configure **Maven** (e.g., `MAVEN3.9`) and the **SonarQube Scanner** if your pipelines require it.

### Nexus Repository

* Admin password is inside the container:

```bash
kubectl -n jenkins exec deploy/nexus -- cat /nexus-data/admin.password
```

* Login at `http://nexus.local` with `admin` + the password above. You will be prompted to change it on first login.

### SonarQube

* Default credentials: `admin` / `admin` (you will be asked to change the password).
* After login, create a token if you plan to analyze projects from Jenkins.

---

## Jenkins Pipeline (CI/CD)

This repo includes a `Jenkinsfile` that demonstrates a CI/CD flow:

* Fetch code from SCM
* Build & test (Maven)
* Static analysis (SonarQube)
* Build Docker image(s)
* Push artifact/image(s) to Nexus
* (Optional) Deploy to Kubernetes

### Minimal Jenkins setup for the pipeline

* **Plugins**: Pipeline, Git, Maven Integration, (optional) Docker Pipeline, SonarQube Scanner for Jenkins
* **Global Tools**: JDK(s), Maven
* **Credentials**:

  * `nexuslogin` (username/password) for Nexus artifact &/or Docker registry
  * (Optional) Git credentials if your repo is private
  * (Optional) SonarQube token (configured in Jenkins global settings)
* **SonarQube Server** in Jenkins: set the server URL (e.g., internal service `http://sonarqube.jenkins.svc.cluster.local:9000`) and server authentication token

> If your Jenkins agent does not have access to a Docker daemon, you can use a Docker‑in‑Docker sidecar or connect to a remote Docker host. Adjust the `Jenkinsfile` accordingly.

---

## Troubleshooting

* **Ingress 404 / host not found**: verify `/etc/hosts` points your client to `$(minikube ip)`.
* **Ingress not ready**: check `kubectl -n ingress-nginx get pods` and wait until pods are `Running` and `Ready`.
* **Pods CrashLoopBackOff**: `kubectl -n jenkins logs deploy/<name>` to see the error; confirm PVCs are bound and images are pulled.
* **Nexus/ SonarQube slow start**: first boot initializes data; wait a few minutes and watch logs.
* **Port conflicts**: ensure no local services are bound to 80/443 on your host (Ingress uses Minikube’s VM IP, but conflicts can still occur with proxies).

---

## Clean Up

```bash
kubectl delete -f vprofile/
kubectl delete -f sonarqube/
kubectl delete -f sonarqube/postgres/
kubectl delete -f nexus/
kubectl delete -f jenkins/
minikube delete
```

---

## Notes & Next Steps

* Helm/Kustomize overlays to separate `dev` and `prod` concerns
* Jenkins agents (Kubernetes agents) to offload builds from the controller
* Monitoring & alerting (Prometheus + Grafana)
* TLS for all public endpoints (self‑signed for local or mkcert)

If you run into issues or want to extend this lab, feel free to open an issue or tweak the manifests—everything is intentionally kept readable and modular.
