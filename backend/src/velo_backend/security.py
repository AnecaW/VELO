import base64
import hashlib
import hmac
import secrets
import time
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
_hasher = PasswordHasher()

def digest(token): return hashlib.sha256(token.encode()).hexdigest()

def password_hash(password):
    return _hasher.hash(password)

def password_valid(password, encoded):
    if encoded.startswith("$argon2id$"):
        try: return _hasher.verify(encoded, password)
        except (VerificationError, InvalidHashError): return False
    try:
        method,salt,key = encoded.split("$")
        if method != "scrypt": return False
        actual = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=16384, r=8, p=1)
        return hmac.compare_digest(actual, base64.b64decode(key))
    except (ValueError, TypeError): return False

def session(db, user, family=None, connection=None):
    token, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    now = int(time.time())
    family = family or secrets.token_hex(16)
    import contextlib
    with (contextlib.nullcontext(connection) if connection is not None else db.connect(True)) as con:
        con.execute("INSERT INTO sessions VALUES(?,?,?,?)", (digest(token),user,now+db.settings.session_seconds,now))
        con.execute("INSERT INTO refresh_tokens VALUES(?,?,?,?,?,?,?)", (digest(refresh),user,digest(token),family,now+2592000,0,now))
    return {"access_token":token,"refresh_token":refresh,"token_type":"Bearer","expires_at":now+db.settings.session_seconds}
