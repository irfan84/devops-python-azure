import os
from flask import Flask

app = Flask(__name__)

try:
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()
except Exception as e:
    # Telemetry should never crash the app/tests
    print(f"Telemetry init skipped: {e}")

@app.get("/")
def home():
    return "DevOps Python Azure App is running!", 200

@app.get("/health")
def health():
    return {"status": "healthy"}, 200

@app.get("/secret")
def secret():
    return os.getenv("APP_SECRET", "not-set"), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
