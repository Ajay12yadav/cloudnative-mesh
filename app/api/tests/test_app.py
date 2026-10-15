"""Unit tests for the API. No database or Redis needed: they are replaced by fakes."""
import os
import sys

import pytest
import redis as redis_lib

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import app as api  # noqa: E402


class FakeCursor:
    def __init__(self, total):
        self.total = total

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, *args, **kwargs):
        pass

    def fetchone(self):
        return (self.total,)


class FakeConn:
    def __init__(self, total=3):
        self.cur = FakeCursor(total)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def cursor(self):
        return self.cur


class FakeRedis:
    def __init__(self):
        self.store = {}

    def get(self, key):
        return self.store.get(key)

    def setex(self, key, ttl, value):
        self.store[key] = str(value)

    def delete(self, key):
        self.store.pop(key, None)

    def ping(self):
        return True


@pytest.fixture
def client(monkeypatch):
    fake_redis = FakeRedis()
    monkeypatch.setattr(api, "get_redis", lambda: fake_redis)
    monkeypatch.setattr(api, "db_connect", lambda: FakeConn(total=3))
    monkeypatch.setattr(api, "ensure_schema", lambda: None)
    api.app.config["TESTING"] = True
    c = api.app.test_client()
    c.fake_redis = fake_redis
    return c


def test_health_needs_no_dependencies(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_ready_ok(client):
    assert client.get("/ready").status_code == 200


def test_ready_503_when_redis_is_down(client, monkeypatch):
    class BrokenRedis:
        def ping(self):
            raise redis_lib.RedisError("boom")

    monkeypatch.setattr(api, "get_redis", lambda: BrokenRedis())
    resp = client.get("/ready")
    assert resp.status_code == 503
    assert "redis" in resp.get_json()["problems"]


def test_visits_first_from_database_then_from_cache(client):
    first = client.get("/api/visits").get_json()
    assert first == {"total": 3, "source": "database"}
    second = client.get("/api/visits").get_json()
    assert second == {"total": 3, "source": "cache"}


def test_recording_a_visit_invalidates_the_cache(client):
    client.get("/api/visits")                       # fills the cache
    assert client.fake_redis.get("visits:total") == "3"
    assert client.post("/api/visit").status_code == 201
    assert client.fake_redis.get("visits:total") is None


def test_metrics_endpoint_exposes_expected_series(client):
    client.get("/api/visits")
    client.get("/api/visits")
    body = client.get("/metrics").get_data(as_text=True)
    assert "http_requests_total" in body
    assert "http_request_duration_seconds_bucket" in body
    assert "cache_hits_total" in body
    assert "cache_misses_total" in body


def test_unknown_routes_do_not_explode_label_cardinality(client):
    client.get("/definitely/not/a/route/123")
    body = client.get("/metrics").get_data(as_text=True)
    assert 'endpoint="unmatched"' in body
    assert "/definitely/not" not in body
