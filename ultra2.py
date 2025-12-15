import os
import json
import base64
import requests
import hashlib
import time
import datetime
import sys
import firebase_admin
from firebase_admin import credentials, firestore
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from flask import Flask
from threading import Thread

# ==========================================
# 1. تهيئة فيربيز (بنظام ذكي لكشف الأخطاء)
# ==========================================
cred_var = os.getenv("FIREBASE_CREDENTIALS")

if not cred_var:
    print("❌ CRITICAL ERROR: Variable 'FIREBASE_CREDENTIALS' is missing on Render!")
else:
    try:
        # محاولة فك التشفير إذا كان Base64
        if not cred_var.strip().startswith("{"):
            decoded_bytes = base64.b64decode(cred_var)
            cred_json = json.loads(decoded_bytes.decode("utf-8"))
            print("✅ Detected Base64 Encoded Key.")
        else:
            # قراءة كود JSON مباشر
            cred_json = json.loads(cred_var)
            print("✅ Detected Direct JSON Key.")

        if not firebase_admin._apps:
            cred = credentials.Certificate(cred_json)
            firebase_admin.initialize_app(cred)
            print("✅ Firebase Connected Successfully!")
            
    except Exception as e:
        print(f"❌ Firebase Init Failed: {e}")
        print("💡 Hint: Ensure you pasted the FULL JSON or FULL Base64 string.")

# تعريف قاعدة البيانات
try:
    db = firestore.client()
except:
    db = None

# ==========================================
# 2. سيرفر Flask (لإبقاء البوت حياً)
# ==========================================
app = Flask(__name__)

@app.route('/')
def index():
    return "✅ Bot is Running (Firestore Mode)"

def run_server():
    port = int(os.environ.get("PORT", 8080))
    app.run(host='0.0.0.0', port=port)

def keep_alive():
    t = Thread(target=run_server)
    t.start()

# ==========================================
# 3. إعدادات السحب (Scraping Config)
# ==========================================
BASE_URL = "https://www.ysscores.com"
ALL_RANKS_URL = "https://www.ysscores.com/ar/rank"
CHECK_INTERVAL = 300  # 5 دقائق

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': 'https://www.google.com/',
}

session = requests.Session()
retry = Retry(total=5, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
adapter = HTTPAdapter(max_retries=retry)
session.mount('https://', adapter)
session.headers.update(HEADERS)

def clean_text(text):
    return text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ') if text else "0"

# ==========================================
# 4. منطق السحب (المعدل لسحب الترتيب فقط)
# ==========================================
def get_tournament_data(url, title_hint, logo_hint):
    full_url = url if url.startswith('http') else f"{BASE_URL}{url}"
    try:
        parts = url.split('/rank/')
        doc_id = parts[1].replace('/', '_') if len(parts) > 1 else hashlib.md5(url.encode()).hexdigest()
    except:
        doc_id = hashlib.md5(url.encode()).hexdigest()

    champ_data = {
        "doc_id": doc_id,
        "title": title_hint,
        "logo": logo_hint,
        "url": full_url,
        "has_standings": True, # مفترض وجود ترتيب لأننا سنفلتر الباقي
        "type": "League",
        "groups": [],
        "matches": [] # ستبقى فارغة لأننا نهتم بالترتيب فقط
    }

    try:
        response = session.get(full_url, timeout=25)
        soup = BeautifulSoup(response.content, 'html.parser')

        # تحديث العنوان واللوغو
        header = soup.find('div', class_='champion-title-wrap')
        if header:
            if header.find('h3'): champ_data['title'] = clean_text(header.find('h3').text)
            if header.find('img'): champ_data['logo'] = header.find('img')['src']

        # البحث عن جداول الترتيب
        tables_found = soup.find_all('div', class_='ranking-table')
        valid_tables = [t for t in tables_found if 'players-table' not in t.get('class', [])]

        # 🛑 التعديل الأساسي هنا:
        # إذا لم نجد أي جدول ترتيب صالح، نقوم بإرجاع None فوراً ونتجاهل هذه البطولة
        if not valid_tables:
            return None 

        # إذا وصلنا هنا، فهذا يعني وجود جدول ترتيب (دوري أو مجموعات)
        for tbl in valid_tables:
            group_name = "General"
            parent = tbl.find_parent('div', class_='collapse-item-wrap')
            if parent:
                head = parent.find('div', class_='collapse-header')
                if head and head.find('span'): group_name = clean_text(head.find('span').text)
            
            teams_list = []
            rows = tbl.find_all('div', class_='rank-row')
            for row in rows:
                if 'header' in row.get('class', []): continue
                name_div = row.find('div', class_='name')
                
                # فلتر اللاعبين
                if name_div and name_div.find('a') and "/player/" in name_div.find('a')['href']: continue 

                rank = clean_text(row.find('div', class_='number').text) if row.find('div', class_='number') else "-"
                t_name, t_logo, t_id, qualified = "Unknown", "", "", False
                
                if name_div:
                    if name_div.find('img'): t_logo = name_div.find('img')['src']
                    if name_div.find('a'): t_id = name_div.find('a')['href'].split('/')[-2]
                    info = name_div.find('div', class_='info')
                    if info:
                        if info.find('div', class_='up-text'):
                            qualified = True
                            info.find('div', class_='up-text').extract()
                        t_name = clean_text(info.text)

                if t_name == "Unknown": continue

                played = clean_text(row.find('div', class_='played').text) if row.find('div', class_='played') else "0"
                won = clean_text(row.find('div', class_='win').text) if row.find('div', class_='win') else "0"
                draw = clean_text(row.find('div', class_='equal').text) if row.find('div', class_='equal') else "0"
                lost = clean_text(row.find('div', class_='lose').text) if row.find('div', class_='lose') else "0"
                goals = clean_text(row.find('div', class_='goals').text) if row.find('div', class_='goals') else "0"
                diff = clean_text(row.find('div', class_='diff').text) if row.find('div', class_='diff') else "0"
                pts = clean_text(row.find('div', class_='points').text) if row.find('div', class_='points') else "0"

                teams_list.append({
                    "rank": rank, "team": t_name, "logo": t_logo, "id": t_id, "qualified": qualified,
                    "stats": {"p": played, "w": won, "d": draw, "l": lost, "gs": goals, "gd": diff, "pts": pts}
                })
            
            if teams_list:
                champ_data["groups"].append({"name": group_name, "teams": teams_list})

        # تحقق أخير: إذا بعد كل هذا لم يتم تجميع فرق (مثلاً جدول فارغ)، نرجع None
        if not champ_data["groups"]:
            return None

    except: 
        return None
        
    return champ_data

def main_scraper():
    print("[*] Starting scrape cycle...")
    try:
        response = session.get(ALL_RANKS_URL, timeout=30)
        soup = BeautifulSoup(response.content, 'html.parser')
    except Exception as e:
        print(f"Error fetching main list: {e}")
        return []

    championships = []
    items = soup.find_all('a', class_='champion-item')
    print(f"[*] Found {len(items)} items.")

    for item in items:
        rank_url = item.get('rank')
        title = item.get('title')
        logo = item.find('img').get('src') if item.find('img') else ""
        if rank_url and "javascript" not in rank_url:
            championships.append({"url": rank_url, "title": title, "logo": logo})

    all_data = []
    # تقليل عدد العمال لتجنب الحظر أو الضغط على الذاكرة
    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_url = {
            executor.submit(get_tournament_data, c['url'], c['title'], c['logo']): c 
            for c in championships
        }
        for future in as_completed(future_to_url):
            res = future.result()
            # 🛑 التعديل الثاني: نضيف البيانات فقط إذا لم تكن None
            if res is not None:
                all_data.append(res)
    
    return all_data

# ==========================================
# 5. التحديث والحلقة (Loop)
# ==========================================
def update_firestore(data_list):
    if not db:
        print("❌ Cannot update: DB is None.")
        return False
    try:
        batch = db.batch()
        col = db.collection('standings')
        count = 0
        total = 0
        for item in data_list:
            doc_ref = col.document(str(item['doc_id']))
            batch.set(doc_ref, item)
            count += 1
            if count >= 400: # حد فايرستور
                batch.commit()
                batch = db.batch()
                count = 0
                print(f"Saved batch of 400...")
        if count > 0:
            batch.commit()
        print(f"✅ Firestore Updated: {len(data_list)} docs.")
        return True
    except Exception as e:
        print(f"❌ DB Update Error: {e}")
        return False

def monitor():
    last_hash = ""
    print("🚀 Bot Started Loop.")
    while True:
        try:
            data = main_scraper()
            if data:
                # الفرز لضمان ثبات الهاش
                sorted_data = sorted(data, key=lambda x: x['doc_id'])
                current_str = json.dumps(sorted_data, sort_keys=True)
                current_hash = hashlib.md5(current_str.encode()).hexdigest()
                
                if current_hash != last_hash:
                    print("🔄 Data changed. Updating DB...")
                    if update_firestore(data):
                        last_hash = current_hash
                else:
                    print("💤 No changes.")
            
            # منع استهلاك المعالج بالانتظار
            time.sleep(CHECK_INTERVAL)
            
        except Exception as e:
            print(f"⚠️ Main Loop Error: {e}")
            time.sleep(60)

if __name__ == "__main__":
    keep_alive()
    if not os.getenv("FIREBASE_CREDENTIALS"):
        print("❌ WARNING: FIREBASE_CREDENTIALS not set!")
    monitor()
