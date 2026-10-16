from app import app

def test_hello():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert b"1.4" in response.data

def test_health():
    client = app.test_client()
    assert client.get("/health").json == {"status": "ok"}