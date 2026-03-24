# Tech Challenge - Fase 3

Projeto da fase 3 da pós graduação, que visa automatizar toda a infraestrutura e o ciclo de vida dos 5 microsserviços do ToggleMaster (auth, flag, targeting, evaluation, analytics) utilizando as práticas de IaC, CI/CD e DevSecOps.

### Requisitos Técnicos:

**1. Infraestrutura como Código (Terraform):**

Provisionamento da infra na AWS utilizando o terraform: 
 
- Networking: 

VPC, Subnets (Públicas e Privadas), Internet Gateway e Route Tables. 

- Cluster EKS: 

O cluster Kubernetes e seus Node Groups. 

- Bancos de Dados: 
    - 3 instâncias RDS (PostgreSQL). 
    - 1 Cluster ElastiCache (Redis). 
    - 1 Tabela DynamoDB (ToggleMasterAnalytics). 

- Mensageria: 

1 Fila SQS. 

- Repositórios: 

5 repositórios no ECR.

**Requisito de Estado:**

O ```terraform.tfstate``` não pode ficar local. Configure o Backend Remoto usando um Bucket S3 (e opcionalmente a flag use_lockfile para Lock).



**2.  Pipeline de Integração Contínua (CI) & DevSecOps :**

Criar workflows (ex: GitHub Actions) para cada um dos 5 microsserviços. O pipeline deve rodar a cada Pull Request e Push na Main. O pipeline deve conter os seguintes estágios (Jobs): 

- **Build & Unit Test:**

Compilar o código e rodar testes unitários (se houver). 

- **Linter/Static Analysis:** 

Rodar ferramentas de linting (ex: golangci-lint para Go, pylint/flake8 para Python).


- **Security Scan (SAST & SCA):**

  - SCA (Software Composition Analysis):

  Verificar vulnerabilidades nas dependências (ex: usar Trivy em modo fs ou OWASP Dependency Check).


  - SAST (Static Application Security Testing):

  Verificar vulnerabilidades no código fonte (ex: SonarCloud gratuito ou gosec/bandit).

  - Regra de Bloqueio: 
  
  Se uma vulnerabilidade CRÍTICA for encontrada, o pipeline deve falhar e não prosseguir.


- **Docker Build & Push:**

    - Construir a imagem Docker. 
    - Rodar um scan de vulnerabilidades na imagem (Container Scan com Trivy). 
    - Logar no AWS ECR. 
    - Enviar a imagem para o ECR com a tag do commit hash (ex: v1.0.0 a1b2c3d).


**3. Entrega Contínua (CD) & GitOps**

Para o deploy, abandonaremos o push direto via CI. Vamos adotar o GitOps.

- Repositório de GitOps: 

Crie um repositório separado (ou uma pasta separada no monorepo) contendo apenas os manifestos Kubernetes 
(YAMLs) ou Helm Charts das aplicações. 


- Instalação do ArgoCD: 

Instale o ArgoCD no seu cluster EKS (pode usar Helm ou Terraform com provider helm/kubectl). 

- Atualização Automática: 

o Ao final do pipeline de CI (passo anterior), adicione um passo que atualiza a tag da imagem no repositório de GitOps (alterando o arquivo deployment.yaml com a nova tag da imagem gerada). 

- Sync: 

Configure o ArgoCD para monitorar esse repositório e sincronizar automaticamente as mudanças para o cluster EKS. 

Mostre a interface do ArgoCD gerenciando os 5 microsserviços.





---

# ToggleMaster — Fase 3: IaC + DevSecOps + GitOps
## AWS Academy Edition (LabRole)

> **Turma:** 1DCLT · **Fase:** 3 · **Stack:** Terraform · GitHub Actions · ArgoCD · AWS EKS

---

## Restrições do AWS Academy

| Restrição | Como contornamos |
|-----------|-----------------|
| ❌ Não criar `aws_iam_role` | Usamos `data "aws_iam_role" "lab_role"` para buscar a LabRole existente |
| ❌ Não criar `aws_iam_policy` | LabRole já possui as policies necessárias (AmazonEKSClusterPolicy, AmazonEKSWorkerNodePolicy, etc.) |
| ❌ OIDC para GitHub Actions não disponível | Usamos Access Key temporária do Academy como secrets no GitHub |
| ❌ IRSA não disponível | HPA baseado em CPU (mesmo padrão da Fase 2) |
| ⚠️ Credenciais expiram em ~4h | Renovar 3 secrets no GitHub a cada sessão |

---

## Estrutura do Monorepo

```
toggle-master-fase3/
├── .github/workflows/
│   ├── ci-reusable.yml          # Pipeline principal (5 jobs DevSecOps)
│   ├── ci-auth.yml              # Go
│   ├── ci-flag.yml              # Python
│   ├── ci-targeting.yml         # Python
│   ├── ci-evaluation.yml        # Go
│   └── ci-analytics.yml         # Python
│
├── terraform/
│   ├── environments/prod/
│   │   ├── main.tf              # data source LabRole + todos os módulos
│   │   ├── variables.tf         # inclui lab_role_name
│   │   ├── outputs.tf
│   │   ├── versions.tf          # backend S3
│   │   └── terraform.tfvars     # ← PREENCHER: github_org, lab_role_name
│   └── modules/
│       ├── networking/          # VPC, subnets, IGW, NAT, route tables
│       ├── eks/                 # Cluster + Node Group usando LabRole
│       ├── rds/                 # 3x PostgreSQL + senhas aleatórias
│       ├── elasticache/         # Redis
│       ├── dynamodb/            # ToggleMasterAnalytics
│       ├── sqs/                 # Fila analytics + DLQ
│       └── ecr/                 # 5 repositórios
│
├── gitops/
│   ├── apps/togglemaster-apps.yaml   # ArgoCD Applications (App of Apps)
│   └── base/
│       ├── ingress.yaml
│       ├── auth/               # deployment.yaml + service.yaml
│       ├── flag/               # deployment.yaml + service.yaml
│       ├── targeting/          # deployment.yaml + service.yaml
│       ├── evaluation/         # deployment.yaml + service.yaml + HPA
│       └── analytics/          # deployment.yaml + service.yaml + HPA
│
├── services/                   # ← COPIAR código da Fase 2 aqui
│   ├── auth/
│   ├── flag/
│   ├── targeting/
│   ├── evaluation/
│   └── analytics/
│
├── bootstrap.sh                # Script de setup completo
└── README.md
```

---

## Passo a passo completo

### 1. Verificar o nome da LabRole

```bash
aws iam get-role --role-name LabRole --query 'Role.RoleName' --output text
```

Se retornar erro, listar todas as roles e procurar:
```bash
aws iam list-roles --query 'Roles[*].RoleName' --output table | grep -i lab
```

Editar `terraform/environments/prod/terraform.tfvars`:
```hcl
lab_role_name = "LabRole"   # ajustar se o nome for diferente
```

### 2. Criar bucket S3 para o tfstate

```bash
aws s3 mb s3://togglemaster-tfstate-fase3 --region us-east-1
aws s3api put-bucket-versioning \
  --bucket togglemaster-tfstate-fase3 \
  --versioning-configuration Status=Enabled
```

### 3. Copiar serviços da Fase 2

```bash
mkdir -p services/{auth,flag,targeting,evaluation,analytics}
# Copiar código + Dockerfile de cada serviço da Fase 2
```

### 4. Rodar o bootstrap

```bash
./bootstrap.sh SEU_GITHUB_ORG
```

Ou manualmente:
```bash
cd terraform/environments/prod
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 5. Configurar secrets no GitHub

Após o `terraform apply`, ir em **Settings → Secrets and variables → Actions** do repositório e adicionar:

| Secret | Como obter |
|--------|-----------|
| `AWS_ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` |
| `AWS_ACCESS_KEY_ID` | Academy → AWS Details → AWS CLI → aws_access_key_id |
| `AWS_SECRET_ACCESS_KEY` | Academy → AWS Details → AWS CLI → aws_secret_access_key |
| `AWS_SESSION_TOKEN` | Academy → AWS Details → AWS CLI → aws_session_token |

> ⚠️ **Renovar os 3 secrets AWS a cada nova sessão do laboratório** (expiram em ~4h)

### 6. Instalar nginx-ingress

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 7. Configurar ArgoCD

```bash
# Substituir org no arquivo de applications
sed -i 's/SEU_GITHUB_ORG/sua-org/g' gitops/apps/togglemaster-apps.yaml
git add gitops/apps/togglemaster-apps.yaml
git commit -m "chore: set argocd repo url"
git push

# Aplicar as Applications
kubectl apply -f gitops/apps/togglemaster-apps.yaml -n argocd

# Obter IP da UI
kubectl get svc argocd-server -n argocd

# Obter senha inicial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Fluxo GitOps

```
Push para main
    ↓
GitHub Actions
  Job 1: Build + Test
  Job 2: Lint (golangci-lint / flake8)
  Job 3: Security Scan → FALHA se CRITICAL ← DevSecOps gate
  Job 4: Docker Build → Trivy image scan → Push ECR
  Job 5: sed no deployment.yaml → git push [skip ci]
    ↓
ArgoCD detecta mudança no repo (polling ~3min)
    ↓
Rolling update automático no EKS
```

---

## Demo DevSecOps para o vídeo

### Inserir vulnerabilidade proposital (Go)

```go
// services/auth/go.mod — adicionar dependência vulnerável
require github.com/dgrijalva/jwt-go v3.2.0+incompatible
```

Pipeline falhará no Job 3:
```
CRITICAL: CVE-2020-26160 in github.com/dgrijalva/jwt-go
```

### Corrigir

```go
require github.com/golang-jwt/jwt/v5 v5.2.1
```

Pipeline passa → ArgoCD deploya nova versão automaticamente.

---

## Destruir o ambiente

```bash
cd terraform/environments/prod
terraform destroy
```




