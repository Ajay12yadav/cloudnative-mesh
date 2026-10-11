"""
CloudNative-Mesh sample API.

  GET  /health       liveness  (process is up; checks nothing external)
  GET  /ready        readiness (Postgres AND Redis reachable)
  GET  /api/visits   total visits; cached in Redis for 10 s
  POST /api/visit    record one visit in Postgres, invalidate the cache
  GET  /metrics      Prometheus metrics
"""
import json
import logging
import os
import time

import boto3
import psycopg2
import redis
from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("api")
app = Flask(__name__)

# ---------------- Prometheus metrics ----------------
REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "endpoint", "status"])
LATENCY = Histogram(
    "http_request_duration_seconds", "Request latency in seconds", ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
CACHE_HITS = Counter("cache_hits_total", "Redis cache hits")
CACHE_MISSES = Counter("cache_misses_total", "Redis cache misses")


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def record_metrics(resp):
    # Use the route pattern, never the raw URL, to keep label cardinality low.
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    if endpoint != "/metrics":
        LATENCY.labels(request.method, endpoint).observe(time.perf_counter() - g.start)
        REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
    return resp


# ---------------- Configuration ----------------
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_SECRET_ARN = os.environ.get("DB_SECRET_ARN")  # Secrets Manager secret made by RDS
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
REDIS_TLS = os.environ.get("REDIS_TLS", "true").lower() == "true"
CACHE_KEY, CACHE_TTL = "visits:total", 10

_creds = None
_schema_ready = False


def get_credentials():
    """Username/password: from Secrets Manager (preferred) or env vars (local dev)."""
    global _creds
    if _creds is None:
        if DB_SECRET_ARN:
            sm = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "ap-south-1"))
            secret = json.loads(sm.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
            _creds = (secret["username"], secret["password"])
        else:
            _creds = (os.environ.get("DB_USER", "appadmin"), os.environ.get("DB_PASSWORD", ""))
    return _creds


def db_connect():
    user, password = get_credentials()
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=user, password=password,
        sslmode="require",  # the RDS parameter group rejects non-SSL connections
        connect_timeout=3,
    )


def ensure_schema():
    global _schema_ready
    if _schema_ready:
        return
    with db_connect() as conn, conn.cursor() as cur:
        cur.execute(
            "CREATE TABLE IF NOT EXISTS visits (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ DEFAULT now())"
        )
    _schema_ready = True


_redis = None


def get_redis():
    global _redis
    if _redis is None:
        _redis = redis.Redis(
            host=REDIS_HOST, port=REDIS_PORT, ssl=REDIS_TLS,
            socket_connect_timeout=2, socket_timeout=2, decode_responses=True,
        )
    return _redis


# ---------------- Routes ----------------
@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/ready")
def ready():
    problems = {}
    try:
        ensure_schema()
    except Exception as exc:  # noqa: BLE001
        problems["postgres"] = str(exc)[:200]
    try:
        get_redis().ping()
    except Exception as exc:  # noqa: BLE001
        problems["redis"] = str(exc)[:200]
    if problems:
        return jsonify(status="not ready", problems=problems), 503
    return jsonify(status="ready")


@app.get("/api/visits")
def visits():
    try:
        cached = get_redis().get(CACHE_KEY)
        if cached is not None:
            CACHE_HITS.inc()
            return jsonify(total=int(cached), source="cache")
        CACHE_MISSES.inc()
    except redis.RedisError as exc:
        log.warning("redis unavailable, falling back to database: %s", exc)

    ensure_schema()
    with db_connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM visits")
        total = cur.fetchone()[0]
    try:
        get_redis().setex(CACHE_KEY, CACHE_TTL, total)
    except redis.RedisError:
        pass
    return jsonify(total=total, source="database")


@app.post("/api/visit")
def add_visit():
    ensure_schema()
    with db_connect() as conn, conn.cursor() as cur:
        cur.execute("INSERT INTO visits DEFAULT VALUES")
    try:
        get_redis().delete(CACHE_KEY)  # cache is now stale
    except redis.RedisError:
        pass
    return jsonify(status="recorded"), 201


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
