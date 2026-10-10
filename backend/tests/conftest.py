import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ["ENVIRONMENT"] = "test"
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_zero_trust.db")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-change-before-deployment-0123456789")
os.environ.setdefault("JWT_ISSUER", "zero-trust-lab")
os.environ.setdefault("JWT_AUDIENCE", "zero-trust-frontend")

import pytest
from fastapi.testclient import TestClient

from app.auth import hash_password
from app.db import Base, SessionLocal, engine, init_db
from app.main import app
from app.models import User


@pytest.fixture
def client():
    Base.metadata.drop_all(bind=engine)
    init_db()
    with TestClient(app) as test_client:
        yield test_client
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def test_user():
    with SessionLocal() as db:
        user = User(username="test-user", password_hash=hash_password("A-Strong-Test-Password-123!"), role="user")
        db.add(user)
        db.commit()
        db.refresh(user)
        user_id = user.id
    yield {"id": user_id, "username": "test-user", "password": "A-Strong-Test-Password-123!"}
