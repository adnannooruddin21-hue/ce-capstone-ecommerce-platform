import os, socket, requests
from flask import Flask, jsonify

app = Flask(__name__)

def imds(path):
    try:
        token = requests.put(
            "http://169.254.169.254/latest/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
            timeout=1,
        ).text
        return requests.get(
            "http://169.254.169.254/latest/meta-data/" + path,
            headers={"X-aws-ec2-metadata-token": token},
            timeout=1,
        ).text
    except Exception:
        return "unknown"

@app.get("/")
def index():
    return jsonify(
        service="catalog",
        instance_id=imds("instance-id"),
        availability_zone=imds("placement/availability-zone"),
        hostname=socket.gethostname(),
        version=os.getenv("APP_VERSION", "1.0.0"),
        products=["widget", "gadget", "doohickey", "sprocket"],
    )

@app.get("/health")
def health():
    return jsonify(status="ok"), 200