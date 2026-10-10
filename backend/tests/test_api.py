def test_healthcheck_has_no_secret_details(client):
    response = client.get("/api/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["cache-control"] == "no-store"


def test_dashboard_requires_authentication(client):
    response = client.get("/api/dashboard")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_login_and_access_dashboard(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"username": test_user["username"], "password": test_user["password"]},
    )
    assert login.status_code == 200
    token = login.json()["access_token"]
    assert login.json()["token_type"] == "bearer"

    dashboard = client.get("/api/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert dashboard.status_code == 200
    assert dashboard.json()["user"]["username"] == test_user["username"]


def test_invalid_password_is_rejected(client, test_user):
    response = client.post(
        "/api/auth/login",
        json={"username": test_user["username"], "password": "wrong-password"},
    )
    assert response.status_code == 401


def test_users_can_create_and_list_their_tasks(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"username": test_user["username"], "password": test_user["password"]},
    )
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    create = client.post("/api/tasks", json={"title": "Prueba Zero Trust", "description": "Demo"}, headers=headers)
    assert create.status_code == 201
    assert create.json()["title"] == "Prueba Zero Trust"

    listing = client.get("/api/tasks", headers=headers)
    assert listing.status_code == 200
    assert len(listing.json()) == 1


def test_malformed_token_is_rejected(client):
    response = client.get("/api/dashboard", headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401
