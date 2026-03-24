# --- Estágio 1: Compilação (Builder) ---
FROM golang:1.21-alpine AS builder

# Define o diretório de trabalho dentro do container
WORKDIR /app

# Instala dependências necessárias para compilar pacotes que usam C (opcional)
RUN apk add --no-cache git

# Copia os arquivos de definição de dependências primeiro (otimiza cache)
COPY go.mod go.sum ./

# Baixa as dependências
RUN go mod download

# Copia o restante do código fonte
COPY . .

# Remove imports não utilizados via sed (Remoção forçada para o build passar)
RUN sed -i '/"crypto\/sha256"/d' handlers.go && \
    sed -i '/"encoding\/hex"/d' handlers.go && \
    sed -i '/"fmt"/d' key.go && \
    sed -i '/"fmt"/d' main.go && \
    sed -i 's|"github.com/jackc/pgx/v4/stdlib"|_ "github.com/jackc/pgx/v4/stdlib"|g' main.go

# Compila o binário de forma estática (ideal para containers leves)
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# --- Estágio 2: Execução (Final) ---
FROM alpine:latest

# Instala certificados CA (necessário se seu app fizer requisições HTTPS)
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copia apenas o binário compilado do estágio builder
COPY --from=builder /app/main .

# Expõe a porta da aplicação
EXPOSE 8080

# Comando para rodar a aplicação
CMD ["./main"]