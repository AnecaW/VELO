"""Email accounts and rotating opaque credentials. Only digests reach SQLite."""
import re
import secrets
import sqlite3
import time
import uuid
from fastapi import Depends, Request, BackgroundTasks
from fastapi.responses import HTMLResponse
import html
from urllib.parse import parse_qs
from pydantic import BaseModel, Field, ConfigDict, field_validator
from .security import digest, password_hash, password_valid, session

class EmailCredentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(max_length=254)
    password: str = Field(min_length=12, max_length=256)
    @field_validator("email")
    @classmethod
    def email_valid(cls, value):
        value = value.strip().lower()
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Invalid email")
        return value

class Refresh(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=256)

class ChangePassword(BaseModel):
    current_password: str = Field(max_length=256)
    new_password: str = Field(min_length=12, max_length=256)

class ResetRequest(BaseModel):
    email: str = Field(max_length=254)


def install_accounts(app, db, user, Problem):
    dummy = password_hash(secrets.token_urlsafe(32))

    def limit(request, action, maximum):
        key = digest(action + ":" + (request.client.host if request.client else "unknown"))
        now = int(time.time())
        with db.connect(True) as con:
            row = con.execute("SELECT * FROM attempts WHERE key=?", (key,)).fetchone()
            count = row['count'] + 1 if row and row['until_at'] > now else 1
            until = row['until_at'] if row and row['until_at'] > now else now + 900
            con.execute("INSERT OR REPLACE INTO attempts VALUES(?,?,?)", (key, count, until))
        if count > maximum:
            raise Problem(429, "Te veel pogingen. Probeer later opnieuw.", "rate_limit")

    @app.post('/api/v1/accounts/register', status_code=201)
    def register(body: EmailCredentials, request: Request):
        limit(request, 'email-register', 5)
        identifier = uuid.uuid4().hex
        with db.connect(True) as con:
            if not con.execute("SELECT 1 FROM users WHERE role='admin'").fetchone():
                raise Problem(503, 'De beheerder moet de installatie eerst lokaal afronden.', 'setup_required')
            try:
                con.execute('INSERT INTO users(id,username,email,password_hash,role,created_at) VALUES(?,?,?,?,?,?)',
                            (identifier, identifier, body.email, password_hash(body.password), 'user', int(time.time())))
            except sqlite3.IntegrityError:
                raise Problem(400, 'Registratie niet mogelijk. Probeer inloggen of wachtwoordherstel.', 'registration_failed') from None
        return {**session(db, identifier), 'user': {'id': identifier, 'email': body.email, 'role': 'user'}}

    @app.post('/api/v1/accounts/login')
    def login(body: EmailCredentials, request: Request):
        limit(request, 'email-login', 20)
        with db.connect() as con:
            account = con.execute('SELECT * FROM users WHERE email=?', (body.email,)).fetchone()
        if not password_valid(body.password, account['password_hash'] if account else dummy):
            raise Problem(401, 'E-mailadres of wachtwoord is onjuist.', 'invalid_credentials')
        return {**session(db, account['id']), 'user': {'id': account['id'], 'email': account['email'], 'role': account['role']}}

    @app.post('/api/v1/accounts/refresh')
    def refresh(body: Refresh, request: Request):
        limit(request, 'refresh', 120)
        replay = False
        with db.connect(True) as con:
            row = con.execute('SELECT * FROM refresh_tokens WHERE digest=?', (digest(body.refresh_token),)).fetchone()
            if not row or row['expires_at'] <= time.time():
                raise Problem(401, 'Sessie verlopen. Meld opnieuw aan.', 'session_expired')
            if row['used']:
                con.execute('DELETE FROM sessions WHERE digest IN (SELECT access_digest FROM refresh_tokens WHERE family=?)', (row['family'],))
                con.execute('DELETE FROM refresh_tokens WHERE family=?', (row['family'],))
                replay = True
            else:
                con.execute('UPDATE refresh_tokens SET used=1 WHERE digest=?', (row['digest'],))
                con.execute('DELETE FROM sessions WHERE digest=?', (row['access_digest'],))
                result = session(db, row['user_id'], row['family'], connection=con)
        if replay:
            raise Problem(401, 'Sessie ingetrokken. Meld opnieuw aan.', 'session_expired')
        return result

    @app.post('/api/v1/accounts/logout')
    def logout(body: Refresh):
        with db.connect(True) as con:
            row = con.execute('SELECT family FROM refresh_tokens WHERE digest=?', (digest(body.refresh_token),)).fetchone()
            if row:
                con.execute('DELETE FROM sessions WHERE digest IN (SELECT access_digest FROM refresh_tokens WHERE family=?)', (row['family'],))
                con.execute('DELETE FROM refresh_tokens WHERE family=?', (row['family'],))
        return {'logged_out': True}

    @app.post('/api/v1/accounts/password')
    def password(body: ChangePassword, request: Request, current=Depends(user)):
        limit(request, 'password-change', 10)
        if not password_valid(body.current_password, current['password_hash']):
            raise Problem(401, 'Wachtwoord is onjuist.', 'invalid_credentials')
        with db.connect(True) as con:
            con.execute('UPDATE users SET password_hash=? WHERE id=?', (password_hash(body.new_password), current['id']))
            con.execute('DELETE FROM sessions WHERE user_id=?', (current['id'],))
            con.execute('DELETE FROM refresh_tokens WHERE user_id=?', (current['id'],))
            con.execute('DELETE FROM password_resets WHERE user_id=?', (current['id'],))
        return {'changed': True, 'login_required': True}

    @app.post('/api/v1/accounts/password-reset')
    def reset(body: ResetRequest, request: Request, background: BackgroundTasks):
        limit(request, 'password-reset', 5)
        if not db.settings.smtp_ready:
            raise Problem(503, 'Wachtwoordherstel is momenteel niet beschikbaar. Neem contact op met VELO.', 'email_not_configured')
        with db.connect(True) as con:
            account = con.execute('SELECT id,email FROM users WHERE email=?', (body.email.strip().lower(),)).fetchone()
            if account:
                token = secrets.token_urlsafe(48)
                con.execute('DELETE FROM password_resets WHERE user_id=?', (account['id'],))
                con.execute('INSERT INTO password_resets VALUES(?,?,?)', (digest(token), account['id'], int(time.time())+1800))
                background.add_task(send_reset, db.settings, account['email'], token)
        return {'message': 'Als dit account bestaat, ontvang je instructies per e-mail.'}

    @app.get('/account/reset', response_class=HTMLResponse)
    def reset_form(token: str = ''):
        if not 32 <= len(token) <= 128:
            raise Problem(400, 'Ongeldige herstellink.', 'invalid_reset')
        return HTMLResponse('<!doctype html><html lang="nl"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>VELO wachtwoordherstel</title><h1>Nieuw VELO-wachtwoord</h1><form method="post" action="/account/reset"><input type="hidden" name="token" value="'+html.escape(token, quote=True)+'"><label>Nieuw wachtwoord <input type="password" name="password" minlength="12" maxlength="256" autocomplete="new-password" required></label><button>Wachtwoord wijzigen</button></form></html>')

    @app.post('/account/reset', response_class=HTMLResponse)
    async def reset_complete(request: Request):
        limit(request, 'password-reset-confirm', 10)
        if not db.settings.smtp_ready:
            raise Problem(503, 'E-mailherstel is uitgeschakeld.', 'email_not_configured')
        raw = await request.body()
        if len(raw)>4096:raise Problem(413, 'Verzoek te groot.', 'validation')
        values = parse_qs(raw.decode('utf-8', errors='replace'))
        token = values.get('token', [''])[0]
        password = values.get('password', [''])[0]
        if not 12 <= len(password) <= 256 or not 32 <= len(token) <= 128:
            raise Problem(422, 'Gebruik een geldig token en minstens twaalf tekens.', 'validation')
        with db.connect(True) as con:
            row = con.execute('SELECT * FROM password_resets WHERE digest=? AND expires_at>?', (digest(token), int(time.time()))).fetchone()
            if not row:raise Problem(400, 'Herstellink is verlopen of al gebruikt.', 'invalid_reset')
            con.execute('UPDATE users SET password_hash=? WHERE id=?', (password_hash(password), row['user_id']))
            for table in ('sessions','refresh_tokens','password_resets'):
                con.execute('DELETE FROM '+table+' WHERE user_id=?', (row['user_id'],))
        return HTMLResponse('<!doctype html><html lang="nl"><meta charset="utf-8"><title>VELO</title><h1>Wachtwoord gewijzigd</h1><p>Open VELO en meld opnieuw aan.</p></html>')


def send_reset(settings, recipient, token):
    import logging
    import smtplib
    import ssl
    from email.message import EmailMessage
    message = EmailMessage()
    message['From'], message['To'], message['Subject'] = settings.smtp_from, recipient, 'VELO wachtwoordherstel'
    message.set_content('Wijzig je wachtwoord binnen 30 minuten via deze eenmalige link: '+settings.public_url+'/account/reset?token='+token+'\nHeb je dit niet aangevraagd? Negeer dit bericht.')
    try:
        factory = smtplib.SMTP_SSL if settings.smtp_security == 'ssl' else smtplib.SMTP
        options = {'context': ssl.create_default_context()} if settings.smtp_security == 'ssl' else {}
        with factory(settings.smtp_host, settings.smtp_port, timeout=20, **options) as smtp:
            if settings.smtp_security == 'starttls':smtp.starttls(context=ssl.create_default_context())
            if settings.smtp_username:smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(message)
    except Exception:
        logging.getLogger('velo.mail').error('Password reset email delivery failed; check SMTP configuration.')
