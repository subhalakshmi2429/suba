FROM  python:3.9-slim

WORKDIR /app

RUN yum -y update && \
    yum -y install python3-pip python3 && \
    pip3 install --upgrade pip

COPY . .

RUN pip3 install --no-cache-dir -r requirements.txt

EXPOSE 5000

CMD ["python3", "app.py"]
