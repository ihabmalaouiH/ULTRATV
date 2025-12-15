import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup
import json
import re
import sys
import time
import hashlib
import datetime
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from flask import Flask
from threading import Thread

# [NEW] استيراد مكتبات فيربيز (Firestore)
import firebase_admin
from firebase_admin import credentials, firestore

# ==========================================
# ⚙️ إعدادات البوت والبيئة
# ==========================================
FIREBASE_CREDENTIALS_JSON = os.getenv("FIREBASE_CREDENTIALS")
# لم نعد بحاجة لرابط الداتا بيز مع Firestore (نستخدم اسم المشروع من ملف JSON)

TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", 300)) 

# ==========================================
# [NEW] تهيئة اتصال Firestore
# ==========================================
if FIREBASE_CREDENTIALS_JSON:
    try:
        if not firebase_admin._apps:
            cred_dict = json.loads(FIREBASE_CREDENTIALS_JSON)
            cred = credentials.Certificate(cred_dict)
            # مع Firestore لا نضع databaseURL، هو يعرف المشروع من الـ credentials
            firebase_admin.initialize_app(cred)
            print("✅ Firestore Initialized Successfully.")
    except Exception as e:
        print(f"❌ Firestore Init Error: {e}")

# تعريف عميل قاعدة البيانات (Firestore Client)
try:
    db = firestore.client()
except:
    db = None
    print("⚠️ Warning: Firestore client not initialized (Check Credentials).")

# ==========================================
# إعداد سيرفر وهمي (Flask)
# ==========================================
app = Flask('')

@app.route('/')
def home():
    return "I am alive! Standings Bot (Firestore) is running..."

def run():
    # استخدام المنفذ الذي يحدده Render أو 8080 افتراضياً
    port = int(os.environ.get("PORT", 8080))
    app.run(host='0.0.0.0', port=port)

def keep_alive():
    t = Thread(target=run)
    t.start()

# ==========================================
# 1. إعدادات الاتصال 
# ==========================================
BASE_URL = "https://www.ysscores.com"
ALL_RANKS_URL = "https://www.ysscores.com/ar/rank"

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Referer': 'https://www.google.com/',
}

session = requests.Session()
retry_strategy = Retry(
    total=5, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(pool_connections=20, pool_maxsize=20, max_retries=retry_strategy)
session.mount("https://", adapter)
session.mount("http://", adapter)
session.headers.update(HEADERS)

# ==========================================
# 🛠️ دوال المعالجة والسحب (كما هي)
# ==========================================

def clean_text(text):
    if text:
        return text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ')
    return "0"

def get_tournament_data(url, title_hint, logo_hint):
    full_url = url if url.startswith('http') else f"{BASE_URL}{url}"
    
    # إنشاء ID فريد للمستند في فايرستور
    try:
        # نحاول أخذ الرقم والاسم من الرابط: /rank/899741/Arab-Cup -> 899741_Arab-Cup
        parts = url.split('/rank/')
        if len(parts) > 1:
            doc_id = parts[1].replace('/', '_')
        else:
            doc_id = hashlib.md5(url.encode()).hexdigest()
    except:
        doc_id = hashlib.md5(url.encode()).hexdigest()

    champ_data = {
        "doc_id": doc_id, # [NEW] معرف المستند
        "title": title_hint,
        "logo": logo_hint,
        "url": full_url,
        "has_standings": False,
        "type": "Unknown",
        "groups": [],
        "matches": []
    }

    try:
        response = session.get(full_url, timeout=20)
        response.encoding = 'utf-8'
        soup = BeautifulSoup(response.text, 'html.parser')

        header = soup.find('div', class_='champion-title-wrap')
        if header:
            if header.find('h3'): champ_data['title'] = clean_text(header.find('h3').text)
            if header.find('img'): champ_data['logo'] = header.find('img')['src']

        # 1. البحث عن الجداول
        tables_found = soup.find_all('div', class_='ranking-table')
        
        # استبعاد جداول الهدافين
        valid_tables = [t for t in tables_found if 'players-table' not in t.get('class', [])]

        if valid_tables:
            champ_data["type"] = "League"
            champ_data["has_standings"] = True
            
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
                    if name_div and name_div.find('a') and "/player/" in name_div.find('a')['href']:
                        continue 

                    rank = clean_text(row.find('div', class_='number').text) if row.find('div', class_='number') else "-"
                    
                    t_name = "Unknown"
                    t_logo = ""
                    t_id = ""
                    qualified = False
                    
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

        # 2. البحث عن المباريات (للكؤوس)
        if not champ_data["groups"]:
            matches_box = soup.find_all('div', class_='item-match')
            if not matches_box: matches_box = soup.find_all('a', class_='match-container')
            
            if matches_box:
                champ_data["type"] = "Cup"
                for m in matches_box:
                    try:
                        teams = m.find_all('div', class_='team-name')
                        if len(teams) >= 2:
                            home = clean_text(teams[0].text)
                            away = clean_text(teams[1].text)
                            res = m.find('div', class_='result')
                            score = clean_text(res.text) if res else "-:-"
                            champ_data["matches"].append({"home": home, "away": away, "score": score})
                    except: continue
            else:
                champ_data["type"] = "Empty"

    except Exception:
        pass

    return champ_data

def main_scraper():
    print(f"[*] Fetching main rank list...")
    try:
        response = session.get(ALL_RANKS_URL, timeout=30)
        soup = BeautifulSoup(response.text, 'html.parser')
    except Exception as e:
        print(f"[!] Error: {e}")
        return []

    championships = []
    items = soup.find_all('a', class_='champion-item')
    print(f"[*] Found {len(items)} championships.")

    for item in items:
        rank_url = item.get('rank')
        title = item.get('title')
        logo = item.find('img').get('src') if item.find('img') else ""

        if rank_url and "javascript" not in rank_url:
            championships.append({"url": rank_url, "title": title, "logo": logo})

    all_data = []
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_url = {
            executor.submit(get_tournament_data, c['url'], c['title'], c['logo']): c 
            for c in championships
        }
        
        for future in as_completed(future_to_url):
            data = future.result()
            # حفظ كل شيء (دوريات وكؤوس)
            all_data.append(data)
    
    return all_data

# ==========================================
# 🔄 دوال التحديث (Firestore Update)
# ==========================================

def update_firestore(data_list):
    """
    حفظ البيانات في Cloud Firestore
    """
    if not db:
        print("❌ Firestore DB client is missing.")
        return False

    try:
        # استخدام Batch Write لتقليل عدد الطلبات وزيادة السرعة
        batch = db.batch()
        collection_ref = db.collection('standings')
        
        count = 0
        for item in data_list:
            # نستخدم doc_id الذي أنشأناه ليكون معرف المستند
            doc_ref = collection_ref.document(str(item['doc_id']))
            batch.set(doc_ref, item)
            count += 1
            
            # Firestore Batch limit is 500
            if count >= 450:
                batch.commit()
                batch = db.batch()
                count = 0
        
        if count > 0:
            batch.commit()
            
        print(f"✅ Firestore Updated Successfully ({len(data_list)} docs) at {datetime.datetime.now().strftime('%H:%M')}")
        return True
    except Exception as e:
        print(f"❌ Firestore Update Error: {e}")
        return False

def send_telegram_alert(message):
    if TELEGRAM_TOKEN and TELEGRAM_CHAT_ID:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = {"chat_id": TELEGRAM_CHAT_ID, "text": message}
        try: session.post(url, data=data, timeout=5)
        except: pass

def monitor_standings():
    last_hash = ""
    
    print(f"🚀 Standings Bot (Firestore Mode) Started...")
    send_telegram_alert("🚀 Bot Started (Firestore Config).")

    while True:
        try:
            # 1. سحب البيانات
            current_data = main_scraper()
            
            if current_data:
                # 2. إنشاء بصمة (Hash)
                # نقوم بفرز القائمة لضمان ثبات الترتيب عند إنشاء الهاش
                current_data_sorted = sorted(current_data, key=lambda x: x['doc_id'])
                current_json_str = json.dumps(current_data_sorted, sort_keys=True)
                current_hash = hashlib.md5(current_json_str.encode('utf-8')).hexdigest()
                
                # 3. المقارنة
                if current_hash != last_hash:
                    print(f"🔄 Change detected! Updating Firestore...")
                    
                    if update_firestore(current_data):
                        last_hash = current_hash
                        send_telegram_alert(f"✅ Updated {len(current_data)} tournaments on Firestore.")
                else:
                    print("💤 No changes.")
            
            time.sleep(CHECK_INTERVAL)

        except Exception as e:
            print(f"⚠️ Loop Error: {e}")
            time.sleep(60)

if __name__ == "__main__":
    keep_alive()
    
    if not FIREBASE_CREDENTIALS_JSON:
        print("❌ Error: FIREBASE_CREDENTIALS is missing!")
    else:
        monitor_standings()
