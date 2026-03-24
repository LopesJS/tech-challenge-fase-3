# ---------- Base ----------
FROM python:3.9-slim

# Evita arquivos .pyc e melhora logs
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Diretório de trabalho
WORKDIR /app

# Dependências de sistema (opcional, mas recomendado)
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# ---------- Dependências Python ----------
COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ---------- Aplicação ----------
COPY . .

# ---------- Segurança ----------
RUN useradd -m appuser
USER appuser

# Porta do health check
EXPOSE 8005

# ---------- Execução ----------
#CMD ["gunicorn", "--bind", "0.0.0.0:8005", "--workers", "1", "app:app"]
CMD ["python", "app.py"]