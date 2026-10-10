import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.auth import (
    get_current_user,
    issue_access_token,
    verify_password,
    verify_unknown_user_password,
)
from app.db import get_db, init_db
from app.models import Task, User
from app.schemas import LoginRequest, TaskCreate, TaskResponse, TokenResponse, UserResponse

logger = logging.getLogger("zero_trust.auth")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="Zero Trust Lab API",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
    lifespan=lifespan,
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    return response


@app.get("/api/healthz")
def healthz():
    # Liveness only; do not expose versions, environment variables or database details.
    return {"status": "ok"}


@app.post("/api/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    username = payload.username.strip()
    user = db.query(User).filter(User.username == username).first()
    client_ip = request.client.host if request.client else "unknown"

    if user is None:
        verify_unknown_user_password(payload.password)
        logger.warning("login_failed client_ip=%s", client_ip)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not verify_password(payload.password, user.password_hash) or not user.is_active:
        logger.warning("login_failed client_ip=%s", client_ip)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token, expires_in = issue_access_token(user)
    return TokenResponse(access_token=token, expires_in=expires_in)


@app.get("/api/auth/me", response_model=UserResponse)
def me(current_user: User = Depends(get_current_user)):
    return UserResponse(id=current_user.id, username=current_user.username, role=current_user.role)


@app.get("/api/dashboard")
def dashboard(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(Task)
    if current_user.role != "admin":
        query = query.filter(Task.owner_id == current_user.id)
    tasks = query.order_by(Task.created_at.desc()).all()
    return {
        "message": "Acceso autorizado: identidad y permisos verificados en el Backend.",
        "user": {"id": current_user.id, "username": current_user.username, "role": current_user.role},
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "task_count": len(tasks),
    }


@app.get("/api/tasks", response_model=list[TaskResponse])
def list_tasks(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(Task)
    if current_user.role != "admin":
        query = query.filter(Task.owner_id == current_user.id)
    return query.order_by(Task.created_at.desc()).all()


@app.post("/api/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(
    payload: TaskCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    task = Task(title=payload.title.strip(), description=payload.description.strip(), owner_id=current_user.id)
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@app.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if task is None:
        raise HTTPException(status_code=404, detail="Recurso no encontrado")
    if current_user.role != "admin" and task.owner_id != current_user.id:
        # 404 avoids confirming that another user's resource exists.
        raise HTTPException(status_code=404, detail="Recurso no encontrado")
    db.delete(task)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
