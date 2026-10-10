from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from typing_extensions import Annotated

Username = Annotated[str, StringConstraints(min_length=1, max_length=64, strip_whitespace=True)]
Password = Annotated[str, StringConstraints(min_length=1, max_length=256)]
TaskTitle = Annotated[str, StringConstraints(min_length=1, max_length=120, strip_whitespace=True)]
TaskDescription = Annotated[str, StringConstraints(max_length=2000)]


class LoginRequest(BaseModel):
    username: Username
    password: Password
    model_config = ConfigDict(extra="forbid")


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    id: int
    username: str
    role: str


class TaskCreate(BaseModel):
    title: TaskTitle
    description: TaskDescription = ""
    model_config = ConfigDict(extra="forbid")


class TaskResponse(BaseModel):
    id: int
    title: str
    description: str
    created_at: datetime
    owner_id: int
    model_config = ConfigDict(from_attributes=True)
