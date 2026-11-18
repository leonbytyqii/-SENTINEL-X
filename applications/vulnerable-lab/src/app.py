"""
SENTINEL-X Test Web Application
Provides endpoints that trigger WAF detection patterns.
No real database or file system access — patterns are reflected in responses only.
"""
import os
import html
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "sentinel-webapp"}), 200

@app.route("/")
def index():
    return jsonify({
        "application": "SENTINEL-X Test Lab",
        "version": "1.0.0",
        "endpoints": ["/health", "/search", "/api/users", "/api/items", "/contact"]
    })

@app.route("/search")
def search():
    """
    Search endpoint. Reflects the query parameter — WAF should detect XSS/SQLi payloads.
    The reflection is HTML-escaped server-side; the WAF intercepts at the request level.
    """
    query = request.args.get("q", "")
    safe = html.escape(query)
    return jsonify({"query": safe, "results": [], "count": 0})

@app.route("/api/users")
def users():
    """
    User lookup endpoint. The 'id' param pattern triggers SQLi detection rules.
    """
    user_id = request.args.get("id", "1")
    # No DB — simulated response
    return jsonify({"id": user_id, "users": [{"id": 1, "name": "Admin"}]})

@app.route("/api/items")
def items():
    """
    Item listing. Accepts 'category' and 'sort' params for filter testing.
    """
    category = request.args.get("category", "all")
    sort     = request.args.get("sort", "id")
    return jsonify({"category": category, "sort": sort, "items": []})

@app.route("/contact", methods=["GET", "POST"])
def contact():
    """
    Contact form. POST body content triggers request-body WAF inspection.
    """
    if request.method == "POST":
        name    = html.escape(request.form.get("name", ""))
        message = html.escape(request.form.get("message", ""))
        return jsonify({"status": "received", "name": name})
    return jsonify({"form": "contact", "fields": ["name", "email", "message"]})

@app.route("/files")
def files():
    """
    File info endpoint. The 'name' param triggers path traversal detection rules.
    No actual file system access occurs.
    """
    filename = request.args.get("name", "readme.txt")
    safe = html.escape(filename)
    return jsonify({"requested": safe, "note": "WAF inspection target only"})

@app.route("/admin")
def admin():
    """
    Restricted admin path — returns 403. Used to test scanner detection.
    """
    return jsonify({"error": "Forbidden"}), 403

if __name__ == "__main__":
    port = int(os.environ.get("FLASK_PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
