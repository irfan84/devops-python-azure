from flask import Flask
import os

app = Flask(__name__)

@app.get("/")
def home():
    return "OK", 200

@app.get("/health")
def health():
    return "Healthy", 200

@app.get("/secret")
def secret():
    return os.getenv("APP_SECRET", "not-set"), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
