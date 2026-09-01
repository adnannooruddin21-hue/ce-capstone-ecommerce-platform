import os
import socket
from decimal import Decimal

import requests
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev-only-change-me")


def db_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "cloudcart"),
        user=os.getenv("DB_USER", "cloudcart"),
        password=os.getenv("DB_PASSWORD", "cloudcart"),
        connect_timeout=5,
    )


# Served when the database tier is not reachable yet (e.g. before the RDS
# module is applied). Keeps the storefront rendering; orders are disabled.
FALLBACK_PRODUCTS = [
    {"id": 1, "name": "Cloud Runner Sneakers", "description": "Lightweight everyday sneakers with a clean modern finish.", "price": 89.99, "category": "Fashion", "emoji": "\U0001F45F", "badge": "Best Seller", "stock": 25},
    {"id": 2, "name": "Aurora Backpack", "description": "Water-resistant commuter backpack with a padded laptop sleeve.", "price": 64.99, "category": "Travel", "emoji": "\U0001F392", "badge": "New", "stock": 30},
    {"id": 3, "name": "Pulse Smart Watch", "description": "Minimal smartwatch for activity, notifications and daily routines.", "price": 129.99, "category": "Tech", "emoji": "⌚", "badge": "Popular", "stock": 18},
    {"id": 4, "name": "Studio Headphones", "description": "Comfortable over-ear headphones designed for focused listening.", "price": 149.99, "category": "Tech", "emoji": "\U0001F3A7", "badge": "Top Rated", "stock": 14},
    {"id": 5, "name": "Urban Hoodie", "description": "Soft premium cotton hoodie for relaxed everyday wear.", "price": 54.99, "category": "Fashion", "emoji": "\U0001F9E5", "badge": "Sale", "stock": 35},
    {"id": 6, "name": "Brew Coffee Set", "description": "Modern pour-over coffee set for a better morning ritual.", "price": 39.99, "category": "Home", "emoji": "☕", "badge": "New", "stock": 20},
    {"id": 7, "name": "Desk Lamp Pro", "description": "Adjustable warm LED desk lamp with a compact footprint.", "price": 44.99, "category": "Home", "emoji": "\U0001F4A1", "badge": "Popular", "stock": 22},
    {"id": 8, "name": "Explorer Bottle", "description": "Insulated stainless-steel bottle that keeps drinks cold for hours.", "price": 29.99, "category": "Travel", "emoji": "\U0001F9F4", "badge": "Best Seller", "stock": 40},
]


def init_db():
    """Create the schema and seed a demo catalogue.

    Runs on process start. Safe to run concurrently from every ASG instance:
    CREATE TABLE IF NOT EXISTS is idempotent and the seed uses a UNIQUE
    constraint with ON CONFLICT DO NOTHING. A larger system would use a
    dedicated migration tool (Alembic) run once, not per-instance.
    """
    conn = db_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS products (
            id SERIAL PRIMARY KEY,
            name VARCHAR(120) NOT NULL UNIQUE,
            description TEXT NOT NULL,
            price NUMERIC(10,2) NOT NULL,
            category VARCHAR(50) NOT NULL,
            emoji VARCHAR(10) NOT NULL,
            badge VARCHAR(40),
            stock INTEGER NOT NULL DEFAULT 10
        );
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            customer_name VARCHAR(120) NOT NULL,
            customer_email VARCHAR(180) NOT NULL,
            total NUMERIC(10,2) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'CONFIRMED',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS order_items (
            id SERIAL PRIMARY KEY,
            order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            product_id INTEGER NOT NULL REFERENCES products(id),
            quantity INTEGER NOT NULL CHECK (quantity > 0),
            price NUMERIC(10,2) NOT NULL
        );
    """)
    products = [
        ("Cloud Runner Sneakers", "Lightweight everyday sneakers with a clean modern finish.", 89.99, "Fashion", "\U0001F45F", "Best Seller", 25),
        ("Aurora Backpack", "Water-resistant commuter backpack with a padded laptop sleeve.", 64.99, "Travel", "\U0001F392", "New", 30),
        ("Pulse Smart Watch", "Minimal smartwatch for activity, notifications and daily routines.", 129.99, "Tech", "⌚", "Popular", 18),
        ("Studio Headphones", "Comfortable over-ear headphones designed for focused listening.", 149.99, "Tech", "\U0001F3A7", "Top Rated", 14),
        ("Urban Hoodie", "Soft premium cotton hoodie for relaxed everyday wear.", 54.99, "Fashion", "\U0001F9E5", "Sale", 35),
        ("Brew Coffee Set", "Modern pour-over coffee set for a better morning ritual.", 39.99, "Home", "☕", "New", 20),
        ("Desk Lamp Pro", "Adjustable warm LED desk lamp with a compact footprint.", 44.99, "Home", "\U0001F4A1", "Popular", 22),
        ("Explorer Bottle", "Insulated stainless-steel bottle that keeps drinks cold for hours.", 29.99, "Travel", "\U0001F9F4", "Best Seller", 40),
    ]
    cur.executemany("""
        INSERT INTO products (name, description, price, category, emoji, badge, stock)
        VALUES (%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (name) DO NOTHING
    """, products)
    conn.commit()
    cur.close()
    conn.close()


def imds(path):
    """Read EC2 instance metadata (IMDSv2). Returns 'local-dev' off-instance."""
    try:
        token = requests.put(
            "http://169.254.169.254/latest/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
            timeout=1,
        )
        token.raise_for_status()
        resp = requests.get(
            "http://169.254.169.254/latest/meta-data/" + path,
            headers={"X-aws-ec2-metadata-token": token.text},
            timeout=1,
        )
        resp.raise_for_status()
        return resp.text
    except Exception:
        return "local-dev"


@app.route("/")
def index():
    return render_template("index.html", app_version=os.getenv("APP_VERSION", "2.0.0"))


# --- health endpoints -------------------------------------------------------
@app.route("/health")
def health():
    """Shallow check for the ALB target group: always 200 while the process is up."""
    return jsonify(status="ok"), 200


@app.route("/api/health")
def api_health():
    """Deep check including the database, for dashboards/alarms."""
    try:
        conn = db_connection()
        conn.close()
        return jsonify(status="ok", database="ok"), 200
    except Exception as exc:
        app.logger.exception("Database health check failed")
        return jsonify(status="degraded", database="error", error=str(exc)), 503


# --- catalogue ------------------------------------------------------------
@app.route("/api/categories")
def categories():
    try:
        conn = db_connection()
        cur = conn.cursor()
        cur.execute("SELECT DISTINCT category FROM products ORDER BY category")
        result = ["All"] + [row[0] for row in cur.fetchall()]
        cur.close()
        conn.close()
        return jsonify(result)
    except Exception:
        app.logger.warning("categories(): database unavailable, using fallback")
        cats = sorted({p["category"] for p in FALLBACK_PRODUCTS})
        return jsonify(["All"] + cats)


@app.route("/api/products")
def products():
    category = request.args.get("category", "All")
    search = request.args.get("search", "").strip()

    try:
        conn = db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        query = """
            SELECT id, name, description, price, category, emoji, badge, stock
            FROM products WHERE 1=1
        """
        params = []
        if category != "All":
            query += " AND category = %s"
            params.append(category)
        if search:
            query += " AND (name ILIKE %s OR description ILIKE %s OR category ILIKE %s)"
            term = f"%{search}%"
            params.extend([term, term, term])
        query += " ORDER BY id"
        cur.execute(query, params)
        rows = cur.fetchall()
        cur.close()
        conn.close()
        return jsonify(rows)
    except Exception:
        app.logger.warning("products(): database unavailable, using fallback")
        q = search.lower()
        rows = [
            p for p in FALLBACK_PRODUCTS
            if (category == "All" or p["category"] == category)
            and (not q or q in (p["name"] + p["description"] + p["category"]).lower())
        ]
        return jsonify(rows)


@app.route("/api/products/<int:product_id>")
def product(product_id):
    conn = db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("""
        SELECT id, name, description, price, category, emoji, badge, stock
        FROM products WHERE id = %s
    """, (product_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        return jsonify(error="Product not found"), 404
    return jsonify(row)


# --- orders (transactional, with row locking) ----------------------------
@app.route("/api/orders", methods=["POST"])
def create_order():
    data = request.get_json(silent=True) or {}
    customer = data.get("customer", {})
    items = data.get("items", [])

    name = str(customer.get("name", "")).strip()
    email = str(customer.get("email", "")).strip()
    if not name or not email or "@" not in email:
        return jsonify(error="Valid customer name and email are required"), 400
    if not items:
        return jsonify(error="Cart is empty"), 400

    try:
        conn = db_connection()
    except Exception:
        return jsonify(error="Checkout is temporarily unavailable (database tier not reachable)"), 503

    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        product_ids = [int(item["id"]) for item in items]
        cur.execute(
            "SELECT id, price, stock FROM products WHERE id = ANY(%s) FOR UPDATE",
            (product_ids,),
        )
        db_products = {row["id"]: row for row in cur.fetchall()}

        total = Decimal("0")
        clean_items = []
        for item in items:
            pid = int(item["id"])
            qty = int(item.get("quantity", 0))
            if qty < 1 or pid not in db_products:
                raise ValueError("Invalid order item")
            if qty > db_products[pid]["stock"]:
                raise ValueError("Requested quantity is not available")
            price = db_products[pid]["price"]
            total += price * qty
            clean_items.append((pid, qty, price))

        cur.execute("""
            INSERT INTO orders (customer_name, customer_email, total)
            VALUES (%s, %s, %s) RETURNING id
        """, (name, email, total))
        order_id = cur.fetchone()["id"]

        for pid, qty, price in clean_items:
            cur.execute("""
                INSERT INTO order_items (order_id, product_id, quantity, price)
                VALUES (%s, %s, %s, %s)
            """, (order_id, pid, qty, price))
            cur.execute("UPDATE products SET stock = stock - %s WHERE id = %s", (qty, pid))

        conn.commit()
        return jsonify(
            success=True,
            order_id=f"CC-{order_id:06d}",
            total=f"{total:.2f}",
            message="Order created successfully",
        ), 201
    except (ValueError, KeyError) as exc:
        conn.rollback()
        return jsonify(error=str(exc)), 400
    except Exception:
        conn.rollback()
        app.logger.exception("Order creation failed")
        return jsonify(error="Could not create order"), 500
    finally:
        cur.close()
        conn.close()


# --- infrastructure identity (used by the storefront's "served by" chip) --
@app.route("/api/infra")
def infrastructure():
    return jsonify(
        service="cloudcart-catalog",
        instance_id=imds("instance-id"),
        availability_zone=imds("placement/availability-zone"),
        hostname=socket.gethostname(),
        version=os.getenv("APP_VERSION", "2.0.0"),
        environment=os.getenv("APP_ENV", "production"),
    )


try:
    init_db()
except Exception:
    app.logger.exception("Database init failed at startup; app will still start")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=False)
