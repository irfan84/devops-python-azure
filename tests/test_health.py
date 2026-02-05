import sys, os
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "app"))
from main import app

def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
