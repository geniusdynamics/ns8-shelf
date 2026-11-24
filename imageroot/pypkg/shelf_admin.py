"""Manage Shelf instance administrator membership."""
import subprocess


def set_admin(action, email):
    statements = {
        "grant": """
            INSERT INTO "_RoleToUser" ("A", "B")
            SELECT role_id, user_id FROM target
            ON CONFLICT DO NOTHING
            RETURNING 1
        """,
        "revoke": """
            DELETE FROM "_RoleToUser" AS membership USING target
            WHERE membership."A" = target.role_id AND membership."B" = target.user_id
            RETURNING 1
        """,
    }
    local_account = 'AND member."deletedAt" IS NULL AND NOT member.sso' if action == "grant" else ""
    sql = f"""
        WITH target AS (
            SELECT role.id AS role_id, member.id AS user_id
            FROM "Role" AS role, "User" AS member
            WHERE role.name = 'ADMIN' AND member.email = :'email' {local_account}
        ), changed AS ({statements[action]})
        SELECT EXISTS (SELECT FROM target), EXISTS (SELECT FROM changed);
    """
    result = subprocess.run(
        ["podman", "exec", "-i", "shelf-db", "psql", "-XAt", "-v", "ON_ERROR_STOP=1",
         "-h", "127.0.0.1", "-U", "postgres", "-d", "postgres", "-v", f"email={email}"],
        input=sql, text=True, stdout=subprocess.PIPE, check=True,
    ).stdout.strip()
    return {
        "t|t": "updated",
        "t|f": "unchanged",
        "f|f": "no_eligible_account",
    }[result]
