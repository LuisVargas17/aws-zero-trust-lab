"""Interactive one-time user creation; does not accept passwords as CLI arguments."""
import argparse
import getpass
import sys

from app.auth import hash_password
from app.db import SessionLocal, init_db
from app.models import User


def main() -> int:
    parser = argparse.ArgumentParser(description="Crear un usuario del laboratorio")
    parser.add_argument("--username", required=True, help="Usuario a crear (máximo 64 caracteres)")
    parser.add_argument("--role", choices=("user", "admin"), default="user")
    args = parser.parse_args()
    username = args.username.strip()
    if not username or len(username) > 64:
        parser.error("El usuario debe contener entre 1 y 64 caracteres")

    password = getpass.getpass("Contraseña (mínimo 12 caracteres): ")
    confirmation = getpass.getpass("Repite la contraseña: ")
    if len(password) < 12:
        print("Error: utiliza al menos 12 caracteres.", file=sys.stderr)
        return 2
    if password != confirmation:
        print("Error: las contraseñas no coinciden.", file=sys.stderr)
        return 2

    init_db()
    with SessionLocal() as db:
        if db.query(User).filter(User.username == username).first():
            print("Error: el usuario ya existe.", file=sys.stderr)
            return 2
        db.add(User(username=username, password_hash=hash_password(password), role=args.role, is_active=True))
        db.commit()
    print(f"Usuario '{username}' creado con rol '{args.role}'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
