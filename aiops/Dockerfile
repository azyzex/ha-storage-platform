FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY detector.py .
RUN useradd --uid 10002 --no-create-home --shell /usr/sbin/nologin aiops
USER 10002
EXPOSE 9100
CMD ["python", "detector.py"]
