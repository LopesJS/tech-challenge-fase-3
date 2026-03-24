#!/bin/bash
set -e

echo "Criando recursos AWS no LocalStack..."

awslocal sqs create-queue \
  --queue-name my-queue

awslocal dynamodb create-table \
  --table-name my-table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "Recursos criados com sucesso!"
