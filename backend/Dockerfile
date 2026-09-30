# Multi-stage: compila las dependencias en un venv y copia sólo eso a la imagen final.
# Imagen multi-arch (amd64 y arm64):  docker buildx build --platform linux/amd64,linux/arm64 .
FROM python:3.12-slim AS build
WORKDIR /src
COPY pyproject.toml ./
COPY app ./app
RUN python -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir .

FROM python:3.12-slim
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1
COPY --from=build /opt/venv /opt/venv
RUN useradd --system --uid 10001 --no-create-home dashboard
USER dashboard
EXPOSE 8080
# DASH_PORT sólo cambia el puerto publicado en docker-compose; dentro del contenedor siempre 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
