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

# === تعديل: استيراد firestore ===
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask
from threading import Thread

# ==========================================
# ⚙️ إعدادات البوت والبيئة
# ==========================================
FIREBASE_CREDENTIALS_JSON = os.getenv("FIREBASE_CREDENTIALS") # محتوى ملف JSON الخاص بالمفتاح

TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

# فحص كل 5 دقائق (300 ثانية)
CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", 300)) 

# ==========================================
# إعداد سيرفر وهمي (Flask) للبقاء نشطاً
# ==========================================
app = Flask('')

@app.route('/')
def home():
    return "I am alive! Standings Bot is running..."

def run():
    app.run(host='0.0.0.0', port=8080)

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
# 🛠️ دوال المعالجة والسحب (Scraping Logic)
# (نفس المنطق السابق بدون تغيير)
# ==========================================

def clean_text(text):
    if text:
        return text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ')
    return "0"

def get_only_teams_standings(url, title_hint, logo_hint):
    full_url = url if url.startswith('http') else f"{BASE_URL}{url}"
    
    champ_data = {
        "title": title_hint,
        "logo": logo_hint,
        "url": full_url,
        "has_standings": False,
        "tables": [] 
    }

    try:
        response = session.get(full_url, timeout=20)
        response.encoding = 'utf-8'
        soup = BeautifulSoup(response.text, 'html.parser')

        header = soup.find('div', class_='champion-title-wrap')
        if header:
            if header.find('h3'): champ_data['title'] = clean_text(header.find('h3').text)
            if header.find('img'): champ_data['logo'] = header.find('img')['src']

        teams_container = soup.find('div', class_=re.compile(r'teams_rank'))
        search_context = teams_container if teams_container else soup

        tables_found = search_context.find_all('div', class_='ranking-table')
        
        if tables_found:
            for tbl in tables_found:
                if 'players-table' in tbl.get('class', []):
                    continue 

                group_name = "General Standings"
                parent_collapse = tbl.find_parent('div', class_='collapse-item-wrap')
                if parent_collapse:
                    head_div = parent_collapse.find('div', class_='collapse-header')
                    if head_div and head_div.find('span'):
                        group_name = clean_text(head_div.find('span').text)
                
                teams_data = []
                rows = tbl.find_all('div', class_='rank-row')
                
                for row in rows:
                    if 'header' in row.get('class', []): continue

                    name_div = row.find('div', class_='name')
                    team_link = ""
                    
                    if name_div:
                        a_tag = name_div.find('a')
                        if a_tag:
                            team_link = a_tag.get('href', '')
                    
                    if "/player/" in team_link:
                        continue 

                    rank = clean_text(row.find('div', class_='number').text) if row.find('div', class_='number') else "-"
                    
                    team_name = "Unknown"
                    team_logo = ""
                    team_id = ""
                    is_qualified = False

                    if name_div:
                        if name_div.find('img'): team_logo = name_div.find('img')['src']
                        if team_link: team_id = team_link.split('/')[-2]
                        
                        info_div = name_div.find('div', class_='info')
                        if info_div:
                            if info_div.find('div', class_='up-text'):
                                is_qualified = True
                                info_div.find('div', class_='up-text').extract()
                            team_name = clean_text(info_div.text)

                    if team_name == "Unknown" and not team_id:
                        continue

                    played = clean_text(row.find('div', class_='played').text) if row.find('div', class_='played') else "0"
                    won = clean_text(row.find('div', class_='win').text) if row.find('div', class_='win') else "0"
                    draw = clean_text(row.find('div', class_='equal').text) if row.find('div', class_='equal') else "0"
                    lost = clean_text(row.find('div', class_='lose').text) if row.find('div', class_='lose') else "0"
                    
                    goals = clean_text(row.find('div', class_='goals').text) if row.find('div', class_='goals') else "0"
                    diff = clean_text(row.find('div', class_='diff').text) if row.find('div', class_='diff') else "0"
                    points = clean_text(row.find('div', class_='points').text) if row.find('div', class_='points') else "0"

                    teams_data.append({
                        "rank": rank,
                        "team_name": team_name,
                        "team_logo": team_logo,
                        "team_id": team_id,
                        "qualified": is_qualified,
                        "stats": {
                            "played": played, "won": won, "draw": draw, "lost": lost,
                            "goals": goals, "goal_diff": diff, "points": points
                        }
                    })
                
                if teams_data:
                    champ_data["tables"].append({
                        "group_name": group_name,
                        "teams": teams_data
                    })
            
            if champ_data["tables"]:
                champ_data["has_standings"] = True

    except Exception as e:
        print(f"Error parsing {full_url}: {e}")
        pass 

    return champ_data

def main_scraper():
    print(f"[*] Fetching main rank list from {ALL_RANKS_URL}...")
    try:
        response = session.get(ALL_RANKS_URL, timeout=30)
        soup = BeautifulSoup(response.text, 'html.parser')
    except Exception as e:
        print(f"[!] Connection Error: {e}")
        return None

    championships_list = []
    items = soup.find_all('a', class_='champion-item')
    
    for item in items:
        rank_url = item.get('rank')
        title = item.get('title')
        logo = item.find('img').get('src') if item.find('img') else ""

        if rank_url and "javascript" not in rank_url:
            championships_list.append({"url": rank_url, "title": title, "logo": logo})

    print(f"[*] Found {len(championships_list)} championships. Processing details...")
    
    all_data = []
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_url = {
            executor.submit(get_only_teams_standings, c['url'], c['title'], c['logo']): c 
            for c in championships_list
        }
        
        for future in as_completed(future_to_url):
            data = future.result()
            if data['has_standings']:
                all_data.append(data)
    
    return all_data

# ==========================================
# 🔄 دوال التحديث (Firestore) والتنبيهات
# ==========================================

def update_firestore_db(content_json):
    """
    دالة لحفظ البيانات في Cloud Firestore
    """
    try:
        # التحقق وتجهيز الاتصال لمرة واحدة
        if not firebase_admin._apps:
            if not FIREBASE_CREDENTIALS_JSON:
                print("❌ Missing Firebase Credentials")
                return False
                
            cred_dict = json.loads(FIREBASE_CREDENTIALS_JSON)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)

        # إنشاء كائن للتعامل مع قاعدة البيانات
        db_client = firestore.client()

        # === طريقة الحفظ في Firestore ===
        # سنحفظ البيانات في "Collection" اسمه standings
        # وداخل "Document" اسمه "all_leagues" (أو يمكنك تغييره كما تحب)
        
        doc_ref = db_client.collection('standings').document('all_leagues')
        
        # حفظ البيانات (نلفها داخل قاموس لأن فيرستور يحتاج root object)
        doc_ref.set({
            'leagues': content_json,
            'last_update': datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
        })

        print("✅ Firestore Updated Successfully.")
        return True
    except Exception as e:
        print(f"❌ Firestore Error: {e}")
        return False

def send_telegram_alert(message):
    if TELEGRAM_TOKEN and TELEGRAM_CHAT_ID:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = {"chat_id": TELEGRAM_CHAT_ID, "text": message}
        try: session.post(url, data=data, timeout=5)
        except: pass

def monitor_standings():
    last_hash = ""
    
    print(f"🚀 Standings Bot Started (Firestore Mode)...")
    send_telegram_alert("🚀 Standings Bot Started on Server (Firestore Mode).")

    while True:
        try:
            # 1. سحب البيانات
            current_data = main_scraper()
            
            if current_data:
                # 2. إنشاء بصمة (Hash) للبيانات الحالية
                current_json_str = json.dumps(current_data, sort_keys=True)
                current_hash = hashlib.md5(current_json_str.encode('utf-8')).hexdigest()
                
                # 3. المقارنة
                if current_hash != last_hash:
                    print(f"🔄 Change detected! Updating Firestore...")
                    
                    # حفظ البيانات في فيرستور
                    if update_firestore_db(current_data):
                        last_hash = current_hash
                        send_telegram_alert(f"✅ Standings Updated on Firestore: {len(current_data)} Leagues processed.")
                else:
                    print("💤 No changes in standings.")
            
            time.sleep(CHECK_INTERVAL)

        except Exception as e:
            print(f"⚠️ Loop Error: {e}")
            time.sleep(60)

if __name__ == "__main__":
    keep_alive()
    
    if not FIREBASE_CREDENTIALS_JSON:
        print("❌ Error: FIREBASE_CREDENTIALS env var is missing!")
    else:
        monitor_standings()
