#!/usr/bin/env bash
# bootstrap.sh — Setup completo para AWS Academy
# Uso: ./bootstrap.sh <github_org>
set -euo pipefail

GITHUB_ORG="${1:-SEU_GITHUB_ORG}"
AWS_REGION="us-east-1"
TFSTATE_BUCKET="togglemaster-tfstate-fase3"
TF_DIR="terraform/environments/prod"

echo "=============================================="
echo " ToggleMaster Fase 3 — Bootstrap (Academy)"
echo " GitHub Org : ${GITHUB_ORG}"
echo " Região     : ${AWS_REGION}"
echo "=============================================="

# 1. Verificar dependências
for cmd in aws terraform kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd não encontrado"; exit 1; }
done
echo "✅ Dependências OK"

# 2. Verificar que as credenciais do Academy estão ativas
echo ""
echo "🔍 Verificando identidade AWS..."
aws sts get-caller-identity
echo ""

# 3. Verificar se a LabRole existe
LAB_ROLE=$(aws iam get-role --role-name LabRole --query 'Role.RoleName' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$LAB_ROLE" = "NOT_FOUND" ]; then
  echo "❌ LabRole não encontrada! Verificar o nome correto em IAM → Roles"
  echo "   Editar terraform.tfvars e ajustar lab_role_name"
  exit 1
fi
echo "✅ LabRole encontrada: $LAB_ROLE"

# 4. Criar bucket S3 para tfstate
if aws s3 ls "s3://${TFSTATE_BUCKET}" 2>/dev/null; then
  echo "✅ Bucket ${TFSTATE_BUCKET} já existe"
else
  echo "🪣 Criando bucket S3 para tfstate..."
  aws s3 mb "s3://${TFSTATE_BUCKET}" --region "${AWS_REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${TFSTATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  echo "✅ Bucket criado com versionamento"
fi

# 5. Ajustar github_org no tfvars
sed -i "s/SEU_GITHUB_ORG/${GITHUB_ORG}/g" "${TF_DIR}/terraform.tfvars"

# 6. Terraform
cd "${TF_DIR}"
echo ""
echo "🔧 terraform init..."
terraform init

echo "📋 terraform validate..."
terraform validate

echo "📋 terraform plan..."
terraform plan -out=tfplan

echo ""
echo "⚠️  Revisar o plano acima. Continuar com apply? (s/N)"
read -r CONFIRM
[[ "${CONFIRM}" =~ ^[Ss]$ ]] || { echo "Cancelado."; exit 0; }

echo "🚀 terraform apply... (leva ~15 min)"
terraform apply tfplan

# 7. Configurar kubectl
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
echo ""
echo "⚙️  Configurando kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"
kubectl get nodes

# 8. Instalar nginx-ingress
echo ""
echo "🌐 Instalando nginx-ingress controller..."
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

echo ""
echo "=============================================="
echo " ✅ Infraestrutura criada com sucesso!"
echo "=============================================="
echo ""
echo "📌 PRÓXIMOS PASSOS — Adicionar secrets no GitHub:"
echo ""
echo "   Ir em: Settings → Secrets and variables → Actions"
echo ""
echo "   Secret              Valor"
echo "   ─────────────────── ──────────────────────────────"
echo "   AWS_ACCOUNT_ID      $(aws sts get-caller-identity --query Account --output text)"
echo "   AWS_ACCESS_KEY_ID   (copiar de: Academy → AWS Details → AWS CLI)"
echo "   AWS_SECRET_ACCESS_KEY  (idem)"
echo "   AWS_SESSION_TOKEN   (idem — obrigatório no Academy)"
echo ""
echo "⚠️  As credenciais do Academy expiram em ~4h."
echo "   Renovar os 3 secrets AWS a cada nova sessão de laboratório."
echo ""
echo "📌 ARGOCD:"
echo "   IP: $(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'aguardar provisionamento')"
echo "   $(terraform output -raw argocd_get_password)"
