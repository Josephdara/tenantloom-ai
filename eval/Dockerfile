FROM python:3.12-slim@sha256:b18b261e1b4974b4f321451ad5251ded85abb22c2b8b262da527dda1d031ab30

ARG HARNESS_COMMIT=unknown
ENV HARNESS_COMMIT=${HARNESS_COMMIT} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config ./config
COPY prompts ./prompts
COPY rubrics ./rubrics
COPY schema ./schema
COPY harness ./harness

USER nobody
ENTRYPOINT ["python", "-m", "harness"]
