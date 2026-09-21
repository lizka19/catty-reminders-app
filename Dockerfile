FROM python:3.12

ARG DEPLOY_REF
ENV DEPLOY_REF=$DEPLOY_REF

WORKDIR /catty-reminders-app

COPY requirements.txt .

RUN pip install -r requirements.txt

COPY app/ ./app/
COPY static/ ./static/
COPY templates/ ./templates/
COPY config.json .

EXPOSE 8181

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8181"]
