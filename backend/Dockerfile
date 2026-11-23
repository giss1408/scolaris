FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
# Shared platform kit (build context `kit` is declared in compose.platform.yaml). Pin by git tag once the kit has a remote.
COPY --from=kit . /kit
RUN pip install "/kit[sso,fastapi]"
COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app
RUN useradd --create-home --uid 10001 scolaris
USER scolaris
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --retries=5 --start-period=40s CMD python -c "import os,urllib.request as u; u.urlopen(u.Request('http://127.0.0.1:8000/healthz', headers={'Host': os.environ.get('PUBLIC_HOST','localhost'), 'X-Forwarded-Proto': 'https'}), timeout=3)"
# Behind Caddy (and Cloudflare in production).
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --proxy-headers --forwarded-allow-ips='*'"]
