#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
import re
import urllib.request
import urllib.parse
import http.server
import http.client
import ssl
import threading
import time
from datetime import datetime, timedelta

# Setup directories
BASE_DIR = os.environ.get("AIMETER_DATA_DIR", os.path.expanduser("~/.aimeter"))
os.makedirs(BASE_DIR, exist_ok=True)
DB_PATH = os.path.join(BASE_DIR, "usage.db")
PRICE_MAP_PATH = os.path.join(BASE_DIR, "model_prices.json")

# Fallback pricing dictionary (cost per 1 Million tokens)
FALLBACK_PRICING = {
    # Anthropic
    "claude-3-5-sonnet": {"input": 3.00, "output": 15.00},
    "claude-3.5-sonnet": {"input": 3.00, "output": 15.00},
    "claude-3-5-haiku": {"input": 0.80, "output": 4.00},
    "claude-3-opus": {"input": 15.00, "output": 75.00},
    # OpenAI
    "gpt-4o": {"input": 2.50, "output": 10.00},
    "gpt-4o-mini": {"input": 0.15, "output": 0.60},
    "o1-preview": {"input": 15.00, "output": 60.00},
    "o1-mini": {"input": 3.00, "output": 12.00},
    # Gemini
    "gemini-1.5-pro": {"input": 1.25, "output": 5.00},
    "gemini-1.5-flash": {"input": 0.075, "output": 0.30},
    "gemini-2.0-flash": {"input": 0.075, "output": 0.30},
}

# Provider mapping helper
PROVIDER_MAPPING = {
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "gemini": "Google Gemini",
    "google": "Google Gemini",
    "claude_code": "Claude Code"
}

# --- Database Management ---

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()
    
    # Usage logs
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS usage_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cost REAL NOT NULL,
        source TEXT NOT NULL,
        request_id TEXT UNIQUE NOT NULL
    )
    """)
    
    # App configuration
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS config (
        key TEXT UNIQUE NOT NULL,
        value TEXT NOT NULL
    )
    """)
    
    # Custom pricing overrides
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS pricing_overrides (
        model TEXT UNIQUE NOT NULL,
        input_cost_per_m REAL NOT NULL,
        output_cost_per_m REAL NOT NULL
    )
    """)
    
    # Set default config
    cursor.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('daily_budget', '5.00')")
    cursor.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('port', '5333')")
    
    conn.commit()
    conn.close()
    print(f"Database initialized at {DB_PATH}")

def log_usage(provider, model, input_tokens, output_tokens, cost, source, request_id):
    conn = get_db()
    cursor = conn.cursor()
    try:
        cursor.execute("""
        INSERT INTO usage_logs (timestamp, provider, model, input_tokens, output_tokens, cost, source, request_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (datetime.now().isoformat(), provider, model, input_tokens, output_tokens, cost, source, request_id))
        conn.commit()
        print(f"[{source}] Logged request {request_id}: {model} ({input_tokens} -> {output_tokens}) Cost: ${cost:.6f}")
    except sqlite3.IntegrityError:
        # Ignore duplicates
        pass
    finally:
        conn.close()

# --- LiteLLM Price Registry ---

class PriceRegistry:
    def __init__(self):
        self.prices = {}
        self.load_cache()
        # Fetch updates in background
        threading.Thread(target=self.fetch_latest_prices, daemon=True).start()
        
    def load_cache(self):
        if os.path.exists(PRICE_MAP_PATH):
            try:
                with open(PRICE_MAP_PATH, 'r') as f:
                    self.prices = json.load(f)
                print(f"Loaded {len(self.prices)} models from cached LiteLLM registry.")
            except Exception as e:
                print(f"Error reading cached prices: {e}")
                
    def fetch_latest_prices(self):
        url = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
        try:
            print("Fetching latest model pricing registry from LiteLLM...")
            req = urllib.request.Request(url, headers={'User-Agent': 'AIMeter/1.0'})
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                self.prices = data
                with open(PRICE_MAP_PATH, 'w') as f:
                    json.dump(data, f)
                print(f"LiteLLM pricing registry successfully updated and cached ({len(self.prices)} models).")
        except Exception as e:
            print(f"Failed to fetch remote prices: {e}. Using cached or fallback.")
            
    def get_pricing(self, model_name):
        # 1. Check custom overrides first
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT input_cost_per_m, output_cost_per_m FROM pricing_overrides WHERE model = ?", (model_name,))
        row = cursor.fetchone()
        conn.close()
        
        if row:
            return {"input": row["input_cost_per_m"], "output": row["output_cost_per_m"]}
            
        # 2. Check LiteLLM prices (keys match model name or prefix)
        clean_name = model_name.lower().strip()
        
        # Exact match or substring search in LiteLLM registry
        matched_key = None
        if clean_name in self.prices:
            matched_key = clean_name
        else:
            # Try to find a key that is a substring or close match
            for k in self.prices.keys():
                if k.lower() in clean_name or clean_name in k.lower():
                    matched_key = k
                    break
                    
        if matched_key and "input_cost_per_token" in self.prices[matched_key]:
            entry = self.prices[matched_key]
            input_cost = entry.get("input_cost_per_token", 0.0) * 1_000_000
            output_cost = entry.get("output_cost_per_token", 0.0) * 1_000_000
            return {"input": input_cost, "output": output_cost}
            
        # 3. Fallback to hardcoded list
        for key, value in FALLBACK_PRICING.items():
            if key in clean_name:
                return value
                
        # Default fallback (very cheap standard model guess if unknown)
        return {"input": 2.00, "output": 10.00}

# Global registry instance
price_registry = PriceRegistry()

# --- Claude Code Log Watcher ---

class ClaudeLogWatcher:
    def __init__(self):
        self.running = True
        self.file_positions = {}
        
    def start(self):
        print("Starting Claude Code log watcher thread...")
        threading.Thread(target=self.watch_loop, daemon=True).start()
        
    def stop(self):
        self.running = False
        
    def watch_loop(self):
        # Allow system to boot up
        time.sleep(2)
        
        claude_dir = os.path.expanduser("~/.claude/projects")
        
        # Check alternative env variable for custom configuration directory
        env_dir = os.environ.get("CLAUDE_CONFIG_DIR")
        if env_dir:
            claude_dir = os.path.join(os.path.expanduser(env_dir), "projects")
            
        print(f"Watching Claude Code projects directory: {claude_dir}")
        
        while self.running:
            try:
                if os.path.exists(claude_dir):
                    self.scan_projects(claude_dir)
            except Exception as e:
                print(f"Error in Claude log watcher: {e}")
            time.sleep(3)
            
    def scan_projects(self, path):
        # Walk ~/.claude/projects/
        for root, dirs, files in os.walk(path):
            for file in files:
                if file.endswith(".jsonl"):
                    file_path = os.path.join(root, file)
                    self.process_file(file_path, file.replace(".jsonl", ""))
                    
    def process_file(self, path, session_id):
        try:
            stat = os.stat(path)
            curr_size = stat.st_size
            last_size = self.file_positions.get(path, 0)
            
            # If file was truncated or is new
            if curr_size < last_size:
                last_size = 0
                
            if curr_size > last_size:
                with open(path, 'r', encoding='utf-8') as f:
                    f.seek(last_size)
                    new_lines = f.readlines()
                    self.file_positions[path] = f.tell()
                    
                    for idx, line in enumerate(new_lines):
                        if not line.strip():
                            continue
                        try:
                            # Generate unique ID for this line to prevent double-logging
                            request_id = f"claude_code_{session_id}_{last_size}_{idx}"
                            self.parse_and_log_line(line, request_id)
                        except Exception as parse_err:
                            pass
        except Exception as e:
            # File might be locked or deleted
            pass
            
    def parse_and_log_line(self, line_str, request_id):
        data = json.loads(line_str)
        # We look for lines containing usage metrics
        
        usage = data.get("usage")
        if not usage:
            # Check nested structure
            msg = data.get("message", {})
            if isinstance(msg, dict):
                usage = msg.get("usage")
                
        if usage and isinstance(usage, dict):
            # Extract tokens
            input_tokens = usage.get("input_tokens", 0) or usage.get("prompt_tokens", 0) or usage.get("promptTokenCount", 0)
            output_tokens = usage.get("output_tokens", 0) or usage.get("completion_tokens", 0) or usage.get("candidatesTokenCount", 0)
            
            if input_tokens == 0 and output_tokens == 0:
                return
                
            # Find model
            model = data.get("model") or data.get("message", {}).get("model") or data.get("metadata", {}).get("model") or "unknown"
            
            # Fetch cost
            pricing = price_registry.get_pricing(model)
            cost = ((input_tokens * pricing["input"]) + (output_tokens * pricing["output"])) / 1_000_000.0
            
            log_usage(
                provider="Anthropic",
                model=model,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cost=cost,
                source="Claude Code",
                request_id=request_id
            )

# --- Reverse Proxy and Web Server ---

class ThreadingHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True

class APILocalProxyHandler(http.server.BaseHTTPRequestHandler):
    
    def log_message(self, format, *args):
        pass
        
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()
        
    def send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-api-key, anthropic-version, stripe-signature')
        
    def do_GET(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        
        if path == "/api/stats":
            self.handle_api_stats()
        elif path == "/api/config":
            self.handle_api_config_get()
        elif path.startswith("/openai") or path.startswith("/anthropic") or path.startswith("/gemini") or path.startswith("/openrouter"):
            self.handle_proxy_request("GET", path)
        else:
            self.handle_static_files(path)
            
    def do_POST(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        
        if path == "/api/config":
            self.handle_api_config_post()
        elif path == "/api/reset":
            self.handle_api_reset()
        elif path == "/api/sync":
            self.send_response(200)
            self.send_cors_headers()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "success", "message": "Manual sync triggered"}).encode())
        elif path.startswith("/openai") or path.startswith("/anthropic") or path.startswith("/gemini") or path.startswith("/openrouter"):
            self.handle_proxy_request("POST", path)
        else:
            self.send_error(404, "Not Found")
            
    # --- API Handlers ---
    
    def handle_api_stats(self):
        conn = get_db()
        cursor = conn.cursor()
        
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
        
        cursor.execute("SELECT SUM(cost) as total, SUM(input_tokens) as input, SUM(output_tokens) as output FROM usage_logs WHERE timestamp >= ?", (today_start,))
        summary = cursor.fetchone()
        today_cost = summary["total"] if summary["total"] is not None else 0.0
        today_input = summary["input"] if summary["input"] is not None else 0
        today_output = summary["output"] if summary["output"] is not None else 0
        
        cursor.execute("""
        SELECT provider, SUM(cost) as cost, SUM(input_tokens) as input, SUM(output_tokens) as output 
        FROM usage_logs WHERE timestamp >= ? GROUP BY provider
        """, (today_start,))
        providers = {r["provider"]: {"cost": r["cost"], "input": r["input"], "output": r["output"]} for r in cursor.fetchall()}
        
        for prov in ["Anthropic", "OpenAI", "Google Gemini", "Claude Code", "OpenRouter"]:
            if prov not in providers:
                providers[prov] = {"cost": 0.0, "input": 0, "output": 0}
                
        cursor.execute("""
        SELECT model, provider, SUM(cost) as cost, SUM(input_tokens) as input, SUM(output_tokens) as output 
        FROM usage_logs WHERE timestamp >= ? GROUP BY model ORDER BY cost DESC
        """, (today_start,))
        models = [dict(r) for r in cursor.fetchall()]
        
        cursor.execute("SELECT * FROM usage_logs ORDER BY timestamp DESC LIMIT 20")
        recent = [dict(r) for r in cursor.fetchall()]
        
        # Calculate 7-day trend
        trend = []
        now = datetime.now()
        for i in range(6, -1, -1):
            day = now - timedelta(days=i)
            start_time = day.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
            end_time = day.replace(hour=23, minute=59, second=59, microsecond=999999).isoformat()
            cursor.execute("SELECT SUM(cost) as total FROM usage_logs WHERE timestamp >= ? AND timestamp <= ?", (start_time, end_time))
            row = cursor.fetchone()
            cost_val = row["total"] if row and row["total"] is not None else 0.0
            trend.append({
                "day": day.strftime("%a"),
                "cost": cost_val
            })
            
        cursor.execute("SELECT key, value FROM config")
        config = {r["key"]: r["value"] for r in cursor.fetchall()}
        
        conn.close()
        
        response_data = {
            "today": {
                "cost": today_cost,
                "input_tokens": today_input,
                "output_tokens": today_output
            },
            "providers": providers,
            "models": models,
            "recent_logs": recent,
            "trend": trend,
            "config": config
        }
        
        self.send_response(200)
        self.send_cors_headers()
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())
        
    def handle_api_config_get(self):
        conn = get_db()
        cursor = conn.cursor()
        
        cursor.execute("SELECT key, value FROM config")
        config = {r["key"]: r["value"] for r in cursor.fetchall()}
        
        cursor.execute("SELECT * FROM pricing_overrides")
        overrides = [dict(r) for r in cursor.fetchall()]
        
        conn.close()
        
        self.send_response(200)
        self.send_cors_headers()
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"config": config, "overrides": overrides}).encode())
        
    def handle_api_config_post(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode()
        data = json.loads(body)
        
        conn = get_db()
        cursor = conn.cursor()
        
        if "daily_budget" in data:
            cursor.execute("INSERT OR REPLACE INTO config (key, value) VALUES ('daily_budget', ?)", (str(data["daily_budget"]),))
            
        if "overrides" in data:
            for item in data["overrides"]:
                model = item.get("model")
                input_cost = item.get("input_cost_per_m")
                output_cost = item.get("output_cost_per_m")
                if model and input_cost is not None and output_cost is not None:
                    if float(input_cost) < 0:
                        cursor.execute("DELETE FROM pricing_overrides WHERE model = ?", (model,))
                    else:
                        cursor.execute("""
                        INSERT OR REPLACE INTO pricing_overrides (model, input_cost_per_m, output_cost_per_m)
                        VALUES (?, ?, ?)
                        """, (model, float(input_cost), float(output_cost)))
                    
        conn.commit()
        conn.close()
        
        self.send_response(200)
        self.send_cors_headers()
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "success", "message": "Configuration updated"}).encode())
        
    def handle_api_reset(self):
        conn = get_db()
        cursor = conn.cursor()
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
        cursor.execute("DELETE FROM usage_logs WHERE timestamp >= ?", (today_start,))
        conn.commit()
        conn.close()
        
        self.send_response(200)
        self.send_cors_headers()
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "success", "message": "Today's log cleared"}).encode())
        
    def handle_static_files(self, path):
        if path == "/":
            path = "/index.html"
            
        clean_path = path.lstrip('/')
        file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), clean_path)
        
        if os.path.exists(file_path) and os.path.isfile(file_path):
            content_type = 'text/plain'
            if path.endswith('.html'):
                content_type = 'text/html'
            elif path.endswith('.css'):
                content_type = 'text/css'
            elif path.endswith('.js'):
                content_type = 'application/javascript'
            elif path.endswith('.png'):
                content_type = 'image/png'
            elif path.endswith('.ico'):
                content_type = 'image/x-icon'
                
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.end_headers()
            
            with open(file_path, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_error(404, "File Not Found")
            
    # --- Proxy Request Handler ---
    
    def handle_proxy_request(self, method, path):
        real_host = ""
        real_path = ""
        provider = ""
        
        if path.startswith("/openai"):
            real_host = "api.openai.com"
            real_path = path.replace("/openai", "")
            provider = "OpenAI"
        elif path.startswith("/anthropic"):
            real_host = "api.anthropic.com"
            real_path = path.replace("/anthropic", "")
            provider = "Anthropic"
        elif path.startswith("/gemini"):
            real_host = "generativelanguage.googleapis.com"
            real_path = path.replace("/gemini", "")
            provider = "Google Gemini"
        elif path.startswith("/openrouter"):
            real_host = "openrouter.ai"
            real_path = path.replace("/openrouter", "")
            provider = "OpenRouter"
        else:
            self.send_error(400, "Bad Request: Unknown Proxy Path")
            return
            
        content_length = int(self.headers.get('Content-Length', 0))
        req_body = self.rfile.read(content_length) if content_length > 0 else b''
        
        headers = {}
        for header, value in self.headers.items():
            if header.lower() not in ['host', 'accept-encoding']:
                headers[header] = value
        headers['Host'] = real_host
        headers['Accept-Encoding'] = 'identity'
        
        try:
            context = ssl.create_default_context()
            conn = http.client.HTTPSConnection(real_host, context=context, timeout=30)
            conn.request(method, real_path, body=req_body, headers=headers)
            resp = conn.getresponse()
            
            self.send_response(resp.status)
            self.send_cors_headers()
            self.send_header('Connection', 'close')
            for header, value in resp.getheaders():
                if header.lower() not in ['transfer-encoding', 'content-encoding', 'access-control-allow-origin', 'connection']:
                    self.send_header(header, value)
            self.end_headers()
            
            response_chunks = []
            while True:
                chunk = resp.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
                response_chunks.append(chunk)
                
            conn.close()
            self.close_connection = True
            
            full_response = b''.join(response_chunks)
            
            threading.Thread(
                target=self.analyze_and_log_proxy_call,
                args=(provider, req_body, full_response),
                daemon=True
            ).start()
            
        except Exception as e:
            print(f"Proxy Connection Error: {e}")
            self.send_response(502)
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"Proxy error: {str(e)}"}).encode())

    # --- Analysis & Logging ---
    
    def analyze_and_log_proxy_call(self, provider, req_bytes, resp_bytes):
        try:
            req_str = req_bytes.decode('utf-8', errors='ignore')
            resp_str = resp_bytes.decode('utf-8', errors='ignore')
            
            model_match = re.search(r'"model"\s*:\s*"([^"]+)"', req_str)
            model = model_match.group(1) if model_match else "unknown"
            
            input_tokens = 0
            output_tokens = 0
            
            input_match = (
                re.search(r'"prompt_tokens"\s*:\s*(\d+)', resp_str) or
                re.search(r'"input_tokens"\s*:\s*(\d+)', resp_str) or
                re.search(r'"promptTokenCount"\s*:\s*(\d+)', resp_str)
            )
            if input_match:
                input_tokens = int(input_match.group(1))
                
            output_match = (
                re.search(r'"completion_tokens"\s*:\s*(\d+)', resp_str) or
                re.search(r'"output_tokens"\s*:\s*(\d+)', resp_str) or
                re.search(r'"candidatesTokenCount"\s*:\s*(\d+)', resp_str)
            )
            if output_match:
                output_tokens = int(output_match.group(1))
                
            if input_tokens == 0:
                inputs = [int(m) for m in re.findall(r'"input_tokens"\s*:\s*(\d+)', resp_str)]
                if inputs:
                    input_tokens = max(inputs)
            if output_tokens == 0:
                outputs = [int(m) for m in re.findall(r'"output_tokens"\s*:\s*(\d+)', resp_str)]
                if outputs:
                    output_tokens = max(outputs)
                    
            if input_tokens == 0 and output_tokens == 0:
                messages_match = re.findall(r'"content"\s*:\s*"([^"]+)"', req_str)
                input_char_len = sum(len(m) for m in messages_match)
                if input_char_len > 0:
                    input_tokens = max(5, int(input_char_len / 3.8))
                    
                contents_match = re.findall(r'"content"\s*:\s*"([^"]+)"', resp_str)
                if not contents_match:
                    contents_match = re.findall(r'"text"\s*:\s*"([^"]+)"', resp_str)
                output_char_len = sum(len(c) for c in contents_match)
                if output_char_len > 0:
                    output_tokens = max(5, int(output_char_len / 3.8))
                    
            if input_tokens == 0 and output_tokens == 0:
                return
                
            pricing = price_registry.get_pricing(model)
            cost = ((input_tokens * pricing["input"]) + (output_tokens * pricing["output"])) / 1_000_000.0
            
            req_id_match = re.search(r'"id"\s*:\s*"([^"]+)"', resp_str)
            request_id = req_id_match.group(1) if req_id_match else f"proxy_{int(time.time()*1000)}_{input_tokens}_{output_tokens}"
            
            log_usage(
                provider=provider,
                model=model,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                cost=cost,
                source="API Proxy",
                request_id=request_id
            )
            
        except Exception as e:
            print(f"Error analyzing proxy call logs: {e}")

# --- Daemon Execution ---

def run_server(port):
    server = ThreadingHTTPServer(('127.0.0.1', port), APILocalProxyHandler)
    print(f"API cost tracking proxy server listening at http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Proxy server shutting down...")

def main():
    # Redirect stdout and stderr to a log file for diagnostics
    log_file_path = os.path.join(BASE_DIR, "daemon.log")
    log_file = open(log_file_path, "a", encoding="utf-8", buffering=1)
    sys.stdout = log_file
    sys.stderr = log_file
    
    print(f"\n--- Daemon Started at {datetime.now().isoformat()} ---")
    init_db()
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM config WHERE key = 'port'")
    row = cursor.fetchone()
    port = int(row["value"]) if row else 5333
    conn.close()
    
    watcher = ClaudeLogWatcher()
    watcher.start()
    
    run_server(port)

if __name__ == "__main__":
    main()
