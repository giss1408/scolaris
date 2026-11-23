"""Fail-closed config, security headers, request ids, private metrics (platform security phase)."""

import base64
import logging

import pytest
from pydantic import ValidationError

from app.config import Settings

GOOD = {
    "env": "prod",
    "database_url": "postgresql://role_scolaris:" + "p" * 30 + "@postgres:5432/db_scolaris",
    "field_encryption_key": base64.b64encode(bytes(range(32))).decode(),
    "hash_key": base64.b64encode(bytes(range(32, 64))).decode(),
    "sso_issuer": "https://auth-api.regisse.com",
    "service_key": "k" * 43,
    "metrics_token": "m" * 40,
}


def make(**over):
    return Settings(_env_file=None, **{**GOOD, **over})


def test_a_correct_prod_config_starts():
    assert make().env == "prod"


@pytest.mark.parametrize("over,why", [
    ({"database_url": "postgresql://scolaris:scolaris@localhost:5440/scolaris"}, "database_url"),
    ({"hash_key": base64.b64encode(b"h" * 32).decode()}, "hash_key"),
    ({"field_encryption_key": base64.b64encode(b"e" * 32).decode()}, "field_encryption_key"),
    ({"hash_key": GOOD["field_encryption_key"]}, "must differ"),
    ({"service_key": "short"}, "service_key"),
    ({"metrics_token": "short"}, "metrics_token"),
])
def test_weak_config_is_refused_in_prod_and_staging(over, why):
    for env in ("prod", "staging"):
        with pytest.raises(ValidationError) as e:
            make(env=env, **over)
        assert why in str(e.value)


@pytest.mark.parametrize("over,why", [
    ({"sso_issuer": "http://auth-api.regisse.com"}, "sso_issuer"),
    ({"sso_issuer": "https://auth-api.localhost"}, "sso_issuer"),
    ({"allow_test_numbers": True}, "allow_test_numbers"),
])
def test_prod_only_rules(over, why):
    with pytest.raises(ValidationError) as e:
        make(**over)
    assert why in str(e.value)
    assert make(env="staging", **over).env == "staging"  # the local rehearsal stack is staging on http://localhost


async def test_security_headers_request_id_and_private_metrics(client, monkeypatch):
    r = await client.get("/healthz", headers={"X-Request-ID": "req-abc-123"})
    assert r.headers["x-request-id"] == "req-abc-123"
    assert r.headers["x-content-type-options"] == "nosniff" and r.headers["x-frame-options"] == "DENY"
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert (await client.get("/metrics")).status_code == 401
    assert (await client.get("/metrics", headers={"Authorization": "Bearer wrong"})).status_code == 401
    ok = await client.get("/metrics", headers={"Authorization": "Bearer " + "t" * 40})
    assert ok.status_code == 200 and 'service="scolaris"' in ok.text


async def test_denied_money_actions_are_counted_without_data(client):
    await client.get("/v1/me")  # no token: 401 missing_token
    body = (await client.get("/metrics", headers={"Authorization": "Bearer " + "t" * 40})).text
    assert 'security_events_total{event="401_missing_token",service="scolaris"}' in body
